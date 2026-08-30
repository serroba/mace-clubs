// A minimal, Playwright-flavored driver for the Garmin Connect IQ
// simulator. There is no official automation API for this app on any
// platform, so every OS-specific mechanic (how to send a key, capture the
// screen, read text) lives behind the Platform seam in platform.ts -
// platform-macos.ts and platform-linux.ts implement it, and each documents
// the empirical findings behind its own approach. This file is the
// platform-agnostic part: launch sequencing and retries, settle-waiting,
// and the press/hold/read API the tests use.
//
// See docs/e2e-testing.md for how to write a new test against this driver.

import { spawn, type ChildProcess } from "node:child_process";
import { homedir } from "node:os";
import { isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

import { resolve as resolveTool } from "../resolve-tool.ts";
import { screensDiffer } from "./pixel-diff.ts";
import { LinuxPlatform } from "./platform-linux.ts";
import { MacosPlatform } from "./platform-macos.ts";
import type { Button, Platform } from "./platform.ts";

export type { Button } from "./platform.ts";

// tools/e2e/ -> tools/ -> repo root. `prgPath` is resolved against this,
// not process.cwd(), so a caller's working directory never matters -
// run-e2e.ts spawns each test file with cwd set to this directory, which
// would otherwise silently resolve a relative "bin/mace-clubs.prg" to
// tools/e2e/bin/mace-clubs.prg (nonexistent) instead of the real one at the
// repo root.
const REPO_ROOT = fileURLToPath(new URL("../..", import.meta.url));

// The screenshot crop geometry in each platform backend is specific to this
// one device's skin - other devices' simulator.json report entirely
// different display locations (fenix7 {x:77,y:146,260x260}, venu3
// {x:91,y:206,454x454}), so supporting another device means finding and
// adding its constants, not just passing an id. launch() fails fast rather
// than silently cropping the wrong region.
const DEFAULT_DEVICE = "instinct3solar45mm";

function createPlatform(): Platform {
    switch (process.platform) {
        case "darwin":
            return new MacosPlatform();
        case "linux":
            return new LinuxPlatform();
        default:
            throw new Error(`the e2e driver supports macOS and Linux, not "${process.platform}"`);
    }
}

/** Module-level so run-e2e.ts's signal handlers can clean up a simulator
 * left behind by a killed test process without constructing a driver. */
const platform = createPlatform();

/** connectiq is launched `detached` (its own process group), so a Ctrl-C
 * during a hung test run won't reach it via the terminal's SIGINT - it'd be
 * orphaned, silently costing memory, until the next launch()'s pre-kill.
 * Exported so run-e2e.ts's signal handlers can call the same cleanup
 * Simulator.close() uses instead of duplicating the kill. */
export function killSimulatorProcess(): void {
    platform.killSimulator();
}

async function sleep(ms: number): Promise<void> {
    await new Promise<void>((res) => {
        setTimeout(res, ms);
    });
}

async function waitFor(
    condition: () => boolean | Promise<boolean>,
    timeoutMs: number,
    description: string,
): Promise<void> {
    const start = Date.now();
    while (!(await condition())) {
        if (Date.now() - start > timeoutMs) {
            throw new Error(`timed out after ${String(timeoutMs)}ms waiting for ${description}`);
        }
        await sleep(250);
    }
}

export interface SimulatorOptions {
    /** Path to the built .prg to load (e.g. `bin/mace-clubs.prg`). */
    prgPath: string;
    /** Connect IQ device id. Defaults to the gyro-validated Instinct 3 Solar. */
    device?: string;
    /** Max time to wait for the screen to stop changing after each
     * press()/hold(), not a flat delay - see waitForStable(). */
    settleMs?: number;
}

export class Simulator {
    private readonly settleMs: number;
    private readonly platform: Platform;
    private monkeydoProcess: ChildProcess | null = null;

    private constructor(settleMs: number, platformImpl: Platform) {
        this.settleMs = settleMs;
        this.platform = platformImpl;
    }

    /** Always starts a genuinely fresh simulator process, even if one is
     * already running. A reused process can have an app loaded mid-workout
     * from a previous test file, and the simulator's own "Kill App" menu
     * command wasn't reliable enough at clearing that on its own (it left
     * the app unresponsive at least once during development). A full
     * process restart is slower per test file but is the version of this
     * that has actually proven reliable. */
    static async launch(options: SimulatorOptions): Promise<Simulator> {
        const device = options.device ?? DEFAULT_DEVICE;
        if (device !== DEFAULT_DEVICE) {
            throw new Error(
                `Simulator only supports device "${DEFAULT_DEVICE}" today - screenshot geometry is ` +
                    `hardcoded to its skin. Passing "${device}" would silently crop the wrong region.`,
            );
        }
        const prgPath = isAbsolute(options.prgPath) ? options.prgPath : join(REPO_ROOT, options.prgPath);
        const monkeydoBin = resolveTool("monkeydo", homedir(), process.env["PATH"] ?? "");

        if (platform.isSimulatorRunning()) {
            platform.killSimulator();
            await waitFor(() => !platform.isSimulatorRunning(), 10_000, "the previous simulator process to exit");
        }

        platform.startSimulator();
        const sim = new Simulator(options.settleMs ?? 1500, platform);
        try {
            await waitFor(() => platform.isSimulatorRunning(), 20_000, "the simulator process to start");
            await sleep(3000); // the simulator needs time to finish booting its own UI

            await sim.loadApp(monkeydoBin, prgPath, device);

            await waitFor(() => platform.windowExists(), 30_000, "the simulator window to appear");
            await platform.prepareWindow();
            // Immediately after the window appears it can briefly render
            // blank before the app repaints - two consecutive blank frames
            // look "stable" to waitForStable() even though nothing real has
            // drawn yet, which would make the very first press() below look
            // like it navigated somewhere when it actually just revealed the
            // launcher screen for the first time. Wait for real
            // (OCR-readable) content instead of just pixel stability.
            // A cold simulator can take a good while to actually boot the
            // device and render its first frame after monkeydo connects -
            // observed up to ~25s. This is a one-time cost per launch(), not
            // per test, so it's worth being generous here.
            await waitFor(async () => (await sim.readText()).length > 0, 45_000, "the launcher screen to render");
            // The launcher screen still has a brief reveal animation on top
            // of that first paint; wait it out so the first real interaction
            // doesn't land mid-transition.
            await sim.waitForStable(4000, 300);
            return sim;
        } catch (error) {
            // A failed launch still leaves a real simulator (and possibly
            // monkeydo) process running - left alone, it just sits there
            // consuming memory until the next launch()'s pre-kill, which
            // compounds exactly the kind of system memory pressure that
            // causes launches to fail in the first place. Clean up now.
            sim.close();
            throw error;
        }
    }

    /** monkeydo refuses to queue a load and just prints "Unable to connect"
     * if the simulator hasn't finished booting yet - this is a known,
     * already-documented flake (see visual_check.sh's identical retry) and
     * needs a real retry loop, not a fixed sleep-and-hope. */
    private async loadApp(monkeydoBin: string, prgPath: string, device: string): Promise<void> {
        const maxAttempts = 8;
        for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
            const chunks: Buffer[] = [];
            const child = spawn(monkeydoBin, [prgPath, device]);
            child.stdout.on("data", (chunk: Buffer) => chunks.push(chunk));
            child.stderr.on("data", (chunk: Buffer) => chunks.push(chunk));
            this.monkeydoProcess = child;

            await sleep(6000); // matches visual_check.sh's proven timing for this exact check
            const output = Buffer.concat(chunks).toString("utf8");
            if (!output.includes("Unable to connect")) {
                return;
            }
            if (attempt === maxAttempts) {
                throw new Error(`monkeydo could not reach the simulator after ${String(maxAttempts)} attempts`);
            }
            await sleep(2000);
        }
    }

    async press(button: Button): Promise<void> {
        this.platform.focus();
        await this.platform.pressKey(button);
        // Wait for the redraw to finish rather than a fixed delay - some
        // transitions (e.g. a reveal animation) take longer than others,
        // and a fixed sleep either wastes time or races a slow one.
        await this.waitForStable(this.settleMs, 100);
    }

    /** Presses a button repeatedly until the screen visibly changes, up to
     * maxAttempts - the app can swallow the first press or two right after
     * a screen transition (observed on the initial launch screen), so a
     * single press isn't always reliable immediately after navigating. */
    async pressUntilChanged(button: Button, maxAttempts = 6): Promise<Buffer> {
        let before = await this.screenshot();
        for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
            await this.press(button);
            const after = await this.screenshot();
            if (screensDiffer(after, before)) {
                return after;
            }
            before = after;
        }
        throw new Error(`screen did not change after ${String(maxAttempts)} presses of "${button}"`);
    }

    /** MENU is the only held button this device exposes (a long-press of UP).
     * Both platforms implement it as a mouse press-and-hold on the skin's
     * UP-button hotspot - the simulator maps keyboard input to taps only, so
     * no synthesized key event of any kind produces a hold. */
    async hold(_button: "menu", holdMs = 1200): Promise<void> {
        this.platform.focus();
        await this.platform.holdMenu(holdMs);
        await this.waitForStable(this.settleMs, 100);
    }

    /** Screenshot of just the watch screen (176x176), not the device bezel. */
    async screenshot(): Promise<Buffer> {
        return await this.platform.captureScreen();
    }

    /** Polls screenshots until two consecutive captures agree within
     * NOISE_TOLERANCE_PIXELS (or timeoutMs elapses) - for waiting out an
     * animation/countdown of unknown duration instead of guessing a fixed
     * delay. Exact byte equality is deliberately not used: two captures of
     * the same static screen can still differ by a few pixels from
     * capture/PNG-encoding jitter alone. */
    async waitForStable(timeoutMs = 5000, pollMs = 200): Promise<Buffer> {
        const start = Date.now();
        let previous = await this.screenshot();
        while (Date.now() - start < timeoutMs) {
            await sleep(pollMs);
            const next = await this.screenshot();
            if (!screensDiffer(next, previous)) {
                return next;
            }
            previous = next;
        }
        return previous;
    }

    /** OCRs the current screen and returns one string per recognized
     * line/region. Prefer this over a screenshot baseline for asserting
     * *what state the app is in* (e.g. "did we reach the rest screen") - it
     * survives font hinting/anti-aliasing noise that would flake a pixel
     * comparison, and reads far more clearly in a test than a wall of
     * screenshot diffs. Keep screenshot()/expectScreenshotMatches() for
     * asserting *layout*. */
    async readText(): Promise<string[]> {
        return await this.platform.ocr(await this.screenshot());
    }

    close(): void {
        this.monkeydoProcess?.kill();
        this.platform.killSimulator();
    }
}
