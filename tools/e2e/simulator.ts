// A minimal, Playwright-flavored driver for the Garmin Connect IQ simulator
// on macOS. There is no official automation API for this app; everything
// here is AppleScript (osascript) + screencapture, with the mechanics
// discovered empirically:
//
// - `click window 1` (the title bar) is required before sending key events,
//   or the simulator silently swallows them - `set frontmost to true` alone
//   is not enough to get real OS-level key focus for this app.
// - Buttons map to standard macOS virtual key codes: SELECT=Return(36),
//   BACK=Escape(53), UP=126, DOWN=125.
// - MENU is a long-press of UP, per this device's own simulator.json `keys`
//   array (`{"behavior":"onMenu","id":"menu","isHold":true}` at the same
//   `location` as `"up"`) - so it's a key-down/key-up pair with a delay
//   between, not a distinct key code.
// - The watch's actual screen (not the surrounding device bezel art) sits
//   at a fixed offset within the window: simulator.json's
//   `display.location` gives {x:101, y:158, width:176, height:176} within
//   the device image; the image itself starts 28pt below the window's
//   top-left (a standard macOS title bar). Screenshots are cropped to
//   exactly that region so baselines contain only app UI pixels, never
//   bezel art (which would make every baseline device-skin-specific for no
//   reason).
//
// See docs/e2e-testing.md for how to write a new test against this driver.

import { execFile, execFileSync, spawn, spawnSync, type ChildProcess } from "node:child_process";
import { readFile, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { resolve as resolveTool } from "../resolve-tool.ts";
import { screensDiffer } from "./pixel-diff.ts";

const OCR_SCRIPT = fileURLToPath(new URL("ocr.swift", import.meta.url));

const DEFAULT_DEVICE = "instinct3solar45mm";
const TITLE_BAR_POINTS = 28;
// From this device's simulator.json: display.location.
const SCREEN_OFFSET = { x: 101, y: 158 } as const;
const SCREEN_SIZE = { width: 176, height: 176 } as const;
// The device.png skin's native size (381x496) plus the app's own status
// bar - the window can briefly report a different (e.g. zero/tiny) size
// while macOS is still animating it open, which would make an early
// screenshot capture garbage (window chrome instead of the watch screen).
const EXPECTED_WINDOW_SIZE = { width: 381, height: 552 } as const;

const KEY_CODES = {
    select: 36,
    back: 53,
    up: 126,
    down: 125,
} as const;

export type Button = keyof typeof KEY_CODES;

interface Bounds {
    x: number;
    y: number;
    width: number;
    height: number;
}

function runAppleScript(script: string): string {
    return execFileSync("osascript", [], { input: script, encoding: "utf8" });
}

const execFileAsync = promisify(execFile);

function isSimulatorProcessRunning(): boolean {
    return spawnSync("pgrep", ["-f", "ConnectIQ.app/Contents/MacOS/simulator"]).status === 0;
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
    private monkeydoProcess: ChildProcess | null = null;

    private constructor(settleMs: number) {
        this.settleMs = settleMs;
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
        const connectiqBin = resolveTool("connectiq", homedir(), process.env["PATH"] ?? "");
        const monkeydoBin = resolveTool("monkeydo", homedir(), process.env["PATH"] ?? "");

        if (isSimulatorProcessRunning()) {
            spawnSync("pkill", ["-9", "-f", "ConnectIQ.app/Contents/MacOS/simulator"]);
            await waitFor(() => !isSimulatorProcessRunning(), 10_000, "the previous simulator process to exit");
        }

        spawn(connectiqBin, [], { detached: true, stdio: "ignore" }).unref();
        await waitFor(() => isSimulatorProcessRunning(), 20_000, "the simulator process to start");
        await sleep(3000); // the simulator needs time to finish booting its own UI

        const sim = new Simulator(options.settleMs ?? 1500);
        await sim.loadApp(monkeydoBin, options.prgPath, device);

        await waitFor(() => sim.windowExists(), 30_000, "the simulator window to appear");
        // The window is a normal resizable macOS window - a previous
        // session (or the user dragging it) can leave it at any size, which
        // would break the fixed SCREEN_OFFSET/SCREEN_SIZE math below. Force
        // it back to the size that math assumes rather than hoping for it.
        sim.setWindowSize(EXPECTED_WINDOW_SIZE.width, EXPECTED_WINDOW_SIZE.height);
        await waitFor(
            () => {
                const bounds = sim.windowBounds();
                return bounds.width === EXPECTED_WINDOW_SIZE.width && bounds.height === EXPECTED_WINDOW_SIZE.height;
            },
            5000,
            "the simulator window to resize",
        );
        // Immediately after a resize the window can briefly render blank
        // before the app repaints - two consecutive blank frames look
        // "stable" to waitForStable() even though nothing real has drawn
        // yet, which would make the very first press() below look like it
        // navigated somewhere when it actually just revealed the launcher
        // screen for the first time. Wait for real (OCR-readable) content
        // instead of just pixel stability.
        // A cold simulator can take a good while to actually boot the
        // device and render its first frame after monkeydo connects -
        // observed up to ~25s on this machine. This is a one-time cost per
        // launch(), not per test, so it's worth being generous here.
        await waitFor(async () => (await sim.readText()).length > 0, 45_000, "the launcher screen to render");
        // The launcher screen still has a brief reveal animation on top of
        // that first paint; wait it out so the first real interaction
        // doesn't land mid-transition.
        await sim.waitForStable(4000, 300);
        return sim;
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

    private windowExists(): boolean {
        try {
            const out = runAppleScript(
                'tell application "System Events" to tell process "simulator" to return count of windows',
            ).trim();
            return Number(out) > 0;
        } catch {
            return false;
        }
    }

    private setWindowSize(width: number, height: number): void {
        runAppleScript(`
            tell application "System Events"
                tell process "simulator"
                    set size of window 1 to {${String(width)}, ${String(height)}}
                end tell
            end tell
        `);
    }

    private windowBounds(): Bounds {
        const out = runAppleScript(`
            tell application "System Events"
                tell process "simulator"
                    set win to window 1
                    set {px, py} to position of win
                    set {sw, sh} to size of win
                    return (px as string) & "," & (py as string) & "," & (sw as string) & "," & (sh as string)
                end tell
            end tell
        `).trim();
        const parts = out.split(",").map(Number);
        const [x, y, width, height] = parts;
        if (x === undefined || y === undefined || width === undefined || height === undefined) {
            throw new Error(`could not parse simulator window bounds from "${out}"`);
        }
        return { x, y, width, height };
    }

    /** Real OS-level key focus needs an actual click on the window - being
     * "frontmost" per System Events is not sufficient for this app. */
    private focus(): void {
        runAppleScript(`
            tell application "System Events"
                tell process "simulator"
                    set frontmost to true
                    click window 1
                end tell
            end tell
        `);
    }

    async press(button: Button): Promise<void> {
        this.focus();
        runAppleScript(`tell application "System Events" to key code ${String(KEY_CODES[button])}`);
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

    /** MENU is the only held button this device exposes (a long-press of UP). */
    async hold(_button: "menu", holdMs = 1200): Promise<void> {
        this.focus();
        const code = KEY_CODES.up;
        runAppleScript(`
            tell application "System Events"
                key down ${String(code)}
                delay ${String(holdMs / 1000)}
                key up ${String(code)}
            end tell
        `);
        await this.waitForStable(this.settleMs, 100);
    }

    /** Screenshot of just the watch screen (176x176pt), not the device bezel. */
    async screenshot(): Promise<Buffer> {
        const bounds = this.windowBounds();
        const screenX = bounds.x + SCREEN_OFFSET.x;
        const screenY = bounds.y + TITLE_BAR_POINTS + SCREEN_OFFSET.y;
        const tmpPath = join("/tmp", `mace-clubs-e2e-${String(Date.now())}-${String(Math.random()).slice(2)}.png`);
        await execFileAsync("screencapture", [
            "-x",
            `-R${String(screenX)},${String(screenY)},${String(SCREEN_SIZE.width)},${String(SCREEN_SIZE.height)}`,
            tmpPath,
        ]);
        try {
            return await readFile(tmpPath);
        } finally {
            await rm(tmpPath, { force: true });
        }
    }

    /** Polls screenshots until two consecutive captures agree within
     * NOISE_TOLERANCE_PIXELS (or timeoutMs elapses) - for waiting out an
     * animation/countdown of unknown duration instead of guessing a fixed
     * delay. Exact byte equality is deliberately not used: two captures of
     * the same static screen can still differ by a few pixels from
     * screencapture/PNG-encoding jitter alone. */
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

    /** OCRs the current screen (via macOS's built-in Vision framework - see
     * ocr.swift) and returns one string per recognized line/region. Prefer
     * this over a screenshot baseline for asserting *what state the app is
     * in* (e.g. "did we reach the rest screen") - it survives font
     * hinting/anti-aliasing noise that would flake a pixel comparison, and
     * reads far more clearly in a test than a wall of screenshot diffs.
     * Keep screenshot()/expectScreenshotMatches() for asserting *layout*. */
    async readText(): Promise<string[]> {
        const png = await this.screenshot();
        const tmpPath = join("/tmp", `mace-clubs-e2e-ocr-${String(Date.now())}-${String(Math.random()).slice(2)}.png`);
        await writeFile(tmpPath, png);
        try {
            const { stdout } = await execFileAsync("swift", [OCR_SCRIPT, tmpPath]);
            return stdout
                .split("\n")
                .map((line) => line.trim())
                .filter((line) => line.length > 0);
        } finally {
            await rm(tmpPath, { force: true });
        }
    }

    close(): void {
        this.monkeydoProcess?.kill();
        spawnSync("pkill", ["-9", "-f", "ConnectIQ.app/Contents/MacOS/simulator"]);
    }
}
