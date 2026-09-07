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

// Upscale factors the OCR tries.
//
// 400% alone was the original, and it reads small text well - which is what
// the Instinct's 176px screen is made of. It fails in the other direction:
// a glyph that is already large gets magnified past what Tesseract's models
// expect, and is dropped silently rather than misread. The movement picker's
// "360" on a 240px Forerunner 945 is 60px tall on the watch and 240px after
// a 400% resize; every page-segmentation mode read the title and none of
// them read the number. The same image at 200% reads "Choose movement 360".
//
// So scale is a second axis alongside polarity, and for the same reason:
// four cheap passes whose lines are unioned, each contributing the rows it
// happens to render legibly, beats one pass tuned for a screen size we do
// not have only one of.
//
// **Order matters, and 400% has to stay first.** The union keeps each line's
// first occurrence, so the leading pass is what sets reading order for every
// line more than one pass can see - and reading order is load-bearing:
// rest-screen.e2e.test.ts identifies the countdown as the time-shaped value
// sitting directly before the "SELECT: work" label. Putting 200% first put
// its own ordering in charge and floated the countdown above the "REST" row,
// so both landmarks resolved to the wall clock and the test reported the
// PR #125 regression against a screen that was drawing correctly. Lower
// scales exist to contribute lines nothing else can read; they are appended,
// never interleaved.
const OCR_SCALES = [400, 200] as const;

/** One OCR'd line and where it sat on the watch screen. */
export interface OcrLine {
    readonly text: string;
    /** Top edge in the *screen's* pixels, i.e. divided back out by the
     * pass's upscale factor so lines from different scales are comparable. */
    readonly top: number;
}

/**
 * Tesseract's TSV output, grouped back into lines.
 *
 * The columns are level, page, block, paragraph, line, word, left, top,
 * width, height, confidence, text. Words (level 5) carry the text; a line is
 * every word sharing a block/paragraph/line triple, joined in word order.
 * Confidence -1 marks Tesseract's structural rows, which carry no text.
 */
export function parseTsvLines(tsv: string, scale: number): OcrLine[] {
    const rows = tsv.split("\n").slice(1);
    const lines = new Map<string, { words: string[]; top: number }>();
    for (const row of rows) {
        const cols = row.split("\t");
        if (cols.length < 12 || cols[0] !== "5") {
            continue;
        }
        const text = (cols[11] ?? "").trim();
        const top = Number(cols[7]);
        if (text.length === 0 || Number.isNaN(top)) {
            continue;
        }
        const key = `${cols[2] ?? ""}/${cols[3] ?? ""}/${cols[4] ?? ""}`;
        const existing = lines.get(key);
        if (existing === undefined) {
            lines.set(key, { words: [text], top });
        } else {
            existing.words.push(text);
            existing.top = Math.min(existing.top, top);
        }
    }
    return [...lines.values()].map((line) => ({
        text: line.words.join(" "),
        top: line.top / (scale / 100),
    }));
}

/**
 * The union of every pass's lines, in top-to-bottom screen order.
 *
 * Deduplicated on text, keeping the topmost sighting: the same row read by
 * two passes should appear once, at the position they agree on. Ties break
 * on first sighting, which keeps the leading pass's ordering for rows drawn
 * at the same height.
 */
export function mergeByPosition(lines: OcrLine[]): string[] {
    const best = new Map<string, { top: number; order: number }>();
    lines.forEach((line, index) => {
        const seen = best.get(line.text);
        if (seen === undefined || line.top < seen.top) {
            best.set(line.text, { top: line.top, order: seen?.order ?? index });
        }
    });
    return [...best.entries()]
        .sort(([, a], [, b]) => (a.top === b.top ? a.order - b.order : a.top - b.top))
        .map(([text]) => text);
}

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
     * "» Bila"). Both polarities are OCR'd at both scales (see OCR_SCALES)
     * and their lines merged, so whichever pass renders a given row legibly
     * contributes it.
     *
     * The merge is by position on the screen, not by the order the passes
     * happened to run, because callers read meaning out of the order:
     * rest-screen.e2e.test.ts identifies the big countdown as the
     * time-shaped value sitting directly *before* the "SELECT: work" label.
     * Concatenating passes cannot express that. A row only the 200% pass can
     * read - which on a 240px Forerunner 945 is exactly the countdown, the
     * largest glyphs on the screen - would land at the end of the array
     * rather than in its slot, and the test would resolve both of its
     * landmarks to the wall clock and report a regression against a screen
     * that is drawing correctly. So every pass reports each line's y
     * coordinate (Tesseract's TSV output, normalised back through the
     * pass's own scale factor) and the union is sorted by it.
     *
     * Applied here rather than in captureScreen() so screenshots keep the
     * screen's real pixels for baseline comparison. */
    async ocr(png: Buffer): Promise<string[]> {
        const dir = await mkdtemp(join(tmpdir(), "mace-clubs-e2e-ocr-"));
        const pngPath = join(dir, "shot.png");
        try {
            await writeFile(pngPath, png);
            const passes = await Promise.all(
                OCR_SCALES.flatMap((scale) => [
                    this.ocrPass(dir, pngPath, `negated-${String(scale)}`, true, scale),
                    this.ocrPass(dir, pngPath, `direct-${String(scale)}`, false, scale),
                ]),
            );
            return mergeByPosition(passes.flat());
        } finally {
            await rm(dir, { recursive: true, force: true });
        }
    }

    private async ocrPass(
        dir: string,
        pngPath: string,
        tag: string,
        negate: boolean,
        scale: number,
    ): Promise<OcrLine[]> {
        const processedPath = join(dir, `${tag}.png`);
        await execFileAsync("convert", [
            pngPath,
            "-resize",
            `${String(scale)}%`,
            ...(negate ? ["-negate"] : []),
            "-threshold",
            "50%",
            processedPath,
        ]);
        // psm 6 ("a single uniform block of text") beat the sparse-text
        // modes here - the watch screen is a small set of centered lines,
        // not scattered labels.
        const { stdout } = await execFileAsync("tesseract", [processedPath, "-", "--psm", "6", "tsv"]);
        return parseTsvLines(stdout, scale);
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
