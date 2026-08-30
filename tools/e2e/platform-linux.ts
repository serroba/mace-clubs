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

import { type DeviceProfile, isGestureDriven } from "./device-profile.ts";
import { resolve as resolveTool } from "../resolve-tool.ts";
import type { Button, Platform } from "./platform.ts";

const execFileAsync = promisify(execFile);

const SIMULATOR_PROCESS_PATTERN = "bin/simulator";
const WINDOW_NAME = "CIQ Simulator";
const DISPLAY = process.env["DISPLAY"] ?? ":1";
// `import -window` output carries the window manager's decoration on top of
// the skin's own coordinates, measured at +1x/+31y. Verified by OCR against
// real screens (tools/e2e/linux/probe.sh). It is a property of openbox, not
// of the device, so it applies to every skin. xdotool mousemove --window
// measures from the decorated origin too, so the same offset applies there.
const DECORATION_OFFSET = { x: 1, y: 31 } as const;

// Big enough for the largest device skin the SDK ships plus decoration
// (descentmk351mm is 847x1089, so its window is 847x1145). A skin that does
// not fit the virtual display gets a window clipped at the edge, and clicks
// on a button past that edge go nowhere - the same failure that made
// hold("menu") a silent no-op on venu3 under macOS.
const XVFB_GEOMETRY = "1400x1400x24";

// Where Menu2 draws its first item, as a fraction of screen height - measured
// on venu3 and vivoactive6. Used only for the touch SELECT below.
const FIRST_MENU_ROW_FRACTION = 0.37;

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
    readonly device: DeviceProfile;
    private readonly env = { ...process.env, DISPLAY };

    constructor(device: DeviceProfile) {
        this.device = device;
    }

    /** Brings up Xvfb and a window manager if they aren't already running,
     * then the simulator itself. A window manager is not optional here: it's
     * what lets the app take real input focus (without one, every key press
     * is silently dropped). */
    startSimulator(): void {
        if (!isProcessRunning(`Xvfb ${DISPLAY}`)) {
            spawn("Xvfb", [DISPLAY, "-screen", "0", XVFB_GEOMETRY], {
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
        // 30 manifest devices have no UP/DOWN keys and drop the arrow-key
        // event entirely; a swipe raises the same next/previous-page
        // behaviour there. Verified on vivoactive6, where a swipe up cycles
        // the preset exactly as DOWN does on the Instinct.
        if (isGestureDriven(this.device)) {
            if (button === "up" || button === "down") {
                await this.swipe(button);
                return;
            }
            if (button === "select") {
                await this.tapSelect();
                return;
            }
            // Only BACK is left at this point.
            const esc = this.device.escHotspot;
            if (esc !== null) {
                await execFileAsync(
                    "xdotool",
                    [
                        "mousemove",
                        "--window",
                        this.requireWindow(),
                        String(Math.round(esc.x + DECORATION_OFFSET.x)),
                        String(Math.round(esc.y + DECORATION_OFFSET.y)),
                        "click",
                        "1",
                    ],
                    { env: this.env },
                );
                return;
            }
        }
        await execFileAsync("xdotool", ["key", "--clearmodifiers", KEYSYMS[button]], { env: this.env });
    }

    /** SELECT as a screen tap - see platform-macos.ts's tapSelect for why a
     * touch device with no UP/DOWN keys needs one. */
    private async tapSelect(): Promise<void> {
        const window = this.requireWindow();
        const screen = this.device.screen;
        const x = Math.round(screen.x + DECORATION_OFFSET.x + screen.width / 2);
        const y = Math.round(screen.y + DECORATION_OFFSET.y + screen.height * FIRST_MENU_ROW_FRACTION);
        await execFileAsync("xdotool", ["mousemove", "--window", window, String(x), String(y), "click", "1"], {
            env: this.env,
        });
    }

    /** DOWN (next page) is a swipe *up* the screen, and vice versa. The
     * intermediate mousemove steps matter: without the pointer visibly
     * travelling, a down/up pair at two points is just a click at the
     * second one. */
    private async swipe(button: "up" | "down"): Promise<void> {
        const window = this.requireWindow();
        const screen = this.device.screen;
        const x = Math.round(screen.x + DECORATION_OFFSET.x + screen.width / 2);
        const top = Math.round(screen.y + DECORATION_OFFSET.y + screen.height * 0.3);
        const bottom = Math.round(screen.y + DECORATION_OFFSET.y + screen.height * 0.7);
        const [from, to] = button === "down" ? [bottom, top] : [top, bottom];

        const move = async (y: number): Promise<void> => {
            await execFileAsync("xdotool", ["mousemove", "--window", window, String(x), String(y)], {
                env: this.env,
            });
        };
        await move(from);
        await execFileAsync("xdotool", ["mousedown", "1"], { env: this.env });
        const steps = 14;
        for (let step = 1; step <= steps; step += 1) {
            await move(Math.round(from + ((to - from) * step) / steps));
            await sleep(12);
        }
        await execFileAsync("xdotool", ["mouseup", "1"], { env: this.env });
    }

    async holdMenu(holdMs: number): Promise<void> {
        const hotspot = this.device.menuHotspot;
        if (hotspot === null) {
            throw new Error(`device "${this.device.id}" has no MENU key - a test needing hold("menu") must skip it`);
        }
        const window = this.requireWindow();
        await execFileAsync(
            "xdotool",
            [
                "mousemove",
                "--window",
                window,
                String(hotspot.x + DECORATION_OFFSET.x),
                String(hotspot.y + DECORATION_OFFSET.y),
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
            const screen = this.device.screen;
            await execFileAsync("import", ["-window", window, rawPath], { env: this.env });
            await execFileAsync("convert", [
                rawPath,
                "-crop",
                `${String(screen.width)}x${String(screen.height)}` +
                    `+${String(screen.x + DECORATION_OFFSET.x)}+${String(screen.y + DECORATION_OFFSET.y)}`,
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
