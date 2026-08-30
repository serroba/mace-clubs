// Linux implementation of the e2e Platform seam: Xvfb for the display,
// xdotool for input, ImageMagick for screenshots, Tesseract for OCR - in
// place of macOS's AppleScript/screencapture/Vision. Needs device fonts
// present (see tools/e2e/linux/README.md; CI fetches them through Garmin's
// authenticated API at job time). Mechanics found empirically via the probe
// scripts in tools/e2e/linux/:
//
// - `xdotool key --window <id> ...` is IGNORED by this app - synthetic
//   window-targeted key events don't register at all. Global-focus input
//   works instead: `xdotool windowactivate --sync <id>` then a plain,
//   non---window `xdotool key`.
// - Mouse events are the opposite: `xdotool mousemove --window <id>` DOES
//   work, so the MENU press-and-hold targets the window directly and needs
//   no global-coordinate math.
// - `import -window <id>` captures the window including the window
//   manager's decoration, which shifts the watch screen from the skin's own
//   {x:101, y:158} to {x:102, y:189} within the captured image.
// - openbox (or some window manager) must be running: without one the app
//   never gets real input focus and every key press is dropped.

import { execFile, spawn, spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

import { resolve as resolveTool } from "../resolve-tool.ts";
import { type Button, type Platform, SCREEN_SIZE } from "./platform.ts";

const execFileAsync = promisify(execFile);

const SIMULATOR_PROCESS_PATTERN = "bin/simulator";
const WINDOW_NAME = "CIQ Simulator";
const DISPLAY = process.env["DISPLAY"] ?? ":1";
const SCREEN_SIZE_STR = `${String(SCREEN_SIZE.width)}x${String(SCREEN_SIZE.height)}`;

// The skin's own display.location is {x:101, y:158}; `import -window` output
// carries the window manager's decoration on top of that, measured at
// +1x/+31y. Verified by OCR against real screens (tools/e2e/linux/probe.sh).
const DECORATION_OFFSET = { x: 1, y: 31 } as const;
const SCREEN_OFFSET = { x: 101 + DECORATION_OFFSET.x, y: 158 + DECORATION_OFFSET.y } as const;
// Center of the UP/MENU button's hotspot from simulator.json's `keys` array
// ({x:2, y:212, w:33, h:68}), in the same decorated-window coordinate space
// (xdotool mousemove --window measures from the decorated origin too).
const MENU_BUTTON_CENTER = {
    x: 2 + 33 / 2 + DECORATION_OFFSET.x,
    y: 212 + 68 / 2 + DECORATION_OFFSET.y,
} as const;

const KEYSYMS: Record<Button, string> = {
    select: "Return",
    back: "Escape",
    up: "Up",
    down: "Down",
};

async function sleep(ms: number): Promise<void> {
    await new Promise<void>((res) => setTimeout(res, ms));
}

function isProcessRunning(pattern: string): boolean {
    return spawnSync("pgrep", ["-f", pattern]).status === 0;
}

export class LinuxPlatform implements Platform {
    readonly name = "linux";
    private readonly env = { ...process.env, DISPLAY };

    /** Brings up Xvfb and a window manager if they aren't already running,
     * then the simulator itself. A window manager is not optional here: it's
     * what lets the app take real input focus (without one, every key press
     * is silently dropped). */
    startSimulator(): void {
        if (!isProcessRunning(`Xvfb ${DISPLAY}`)) {
            spawn("Xvfb", [DISPLAY, "-screen", "0", "1280x1024x24"], {
                detached: true,
                stdio: "ignore",
            }).unref();
        }
        if (!isProcessRunning("openbox")) {
            spawn("openbox", [], { detached: true, stdio: "ignore", env: this.env }).unref();
        }
        const simulatorBin = resolveTool("simulator", homedir(), process.env["PATH"] ?? "");
        spawn(simulatorBin, [], { detached: true, stdio: "ignore", env: this.env }).unref();
    }

    isSimulatorRunning(): boolean {
        return isProcessRunning(SIMULATOR_PROCESS_PATTERN);
    }

    killSimulator(): void {
        spawnSync("pkill", ["-9", "-f", SIMULATOR_PROCESS_PATTERN]);
    }

    windowExists(): boolean {
        return this.findWindow() !== null;
    }

    /** Nothing to do: unlike macOS's resizable window, the simulator window
     * here comes up at a fixed size and the crop is measured relative to the
     * window itself, so there's no geometry to normalize. */
    async prepareWindow(): Promise<void> {
        return Promise.resolve();
    }

    focus(): void {
        const window = this.requireWindow();
        spawnSync("xdotool", ["windowactivate", "--sync", window], { env: this.env });
    }

    /** Deliberately NOT `--window`-targeted: this app ignores synthetic
     * window-targeted key events entirely. focus() has already activated the
     * window, so a plain global key press lands on it. */
    async pressKey(button: Button): Promise<void> {
        await execFileAsync("xdotool", ["key", "--clearmodifiers", KEYSYMS[button]], { env: this.env });
    }

    async holdMenu(holdMs: number): Promise<void> {
        const window = this.requireWindow();
        await execFileAsync(
            "xdotool",
            [
                "mousemove",
                "--window",
                window,
                String(MENU_BUTTON_CENTER.x),
                String(MENU_BUTTON_CENTER.y),
                "mousedown",
                "1",
            ],
            { env: this.env },
        );
        await sleep(holdMs);
        await execFileAsync("xdotool", ["mouseup", "1"], { env: this.env });
    }

    async captureScreen(): Promise<Buffer> {
        const window = this.requireWindow();
        const dir = await mkdtemp(join(tmpdir(), "mace-clubs-e2e-"));
        const rawPath = join(dir, "raw.png");
        const cropPath = join(dir, "crop.png");
        try {
            await execFileAsync("import", ["-window", window, rawPath], { env: this.env });
            await execFileAsync("convert", [
                rawPath,
                "-crop",
                `${SCREEN_SIZE_STR}+${String(SCREEN_OFFSET.x)}+${String(SCREEN_OFFSET.y)}`,
                cropPath,
            ]);
            return await readFile(cropPath);
        } finally {
            await rm(dir, { recursive: true, force: true });
        }
    }

    /** Tesseract needs real preprocessing to read this screen: it's trained
     * on dark text on light backgrounds at document sizes, and the raw
     * 176x176 white-on-black watch screen reads as garbage ("Lad ii" for
     * "REST"). Upscaling and thresholding fixes the size and antialiasing;
     * inverting fixes the polarity (measured across preprocessing and
     * page-segmentation combinations in tools/e2e/linux/probe-ocr.sh).
     *
     * The catch: a Menu2's *selected* row is drawn already inverted, so a
     * single global negate reads every normal line perfectly and garbles
     * exactly the highlighted one ("Settings" clean but "History" as
     * "» Bila"). Both polarities are OCR'd and their lines merged, so
     * whichever pass renders a given row dark-on-light contributes it.
     *
     * Applied here rather than in captureScreen() so screenshots keep the
     * screen's real pixels for baseline comparison. */
    async ocr(png: Buffer): Promise<string[]> {
        const dir = await mkdtemp(join(tmpdir(), "mace-clubs-e2e-ocr-"));
        const pngPath = join(dir, "shot.png");
        try {
            await writeFile(pngPath, png);
            const passes = await Promise.all([
                this.ocrPass(dir, pngPath, "negated", true),
                this.ocrPass(dir, pngPath, "direct", false),
            ]);
            return [...new Set(passes.flat())];
        } finally {
            await rm(dir, { recursive: true, force: true });
        }
    }

    private async ocrPass(dir: string, pngPath: string, tag: string, negate: boolean): Promise<string[]> {
        const processedPath = join(dir, `${tag}.png`);
        await execFileAsync("convert", [
            pngPath,
            "-resize",
            "400%",
            ...(negate ? ["-negate"] : []),
            "-threshold",
            "50%",
            processedPath,
        ]);
        // psm 6 ("a single uniform block of text") beat the sparse-text
        // modes here - the watch screen is a small set of centered lines,
        // not scattered labels.
        const { stdout } = await execFileAsync("tesseract", [processedPath, "-", "--psm", "6"]);
        return stdout
            .split("\n")
            .map((line) => line.trim())
            .filter((line) => line.length > 0);
    }

    private findWindow(): string | null {
        const result = spawnSync("xdotool", ["search", "--name", WINDOW_NAME], {
            encoding: "utf8",
            env: this.env,
        });
        const id = result.stdout.split("\n")[0]?.trim();
        return id !== undefined && id.length > 0 ? id : null;
    }

    private requireWindow(): string {
        const window = this.findWindow();
        if (window === null) {
            throw new Error(`no window named "${WINDOW_NAME}" on DISPLAY ${DISPLAY}`);
        }
        return window;
    }
}
