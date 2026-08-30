// macOS implementation of the e2e Platform seam. Everything here is
// AppleScript (osascript) + screencapture + Vision OCR, with the mechanics
// discovered empirically:
//
// - `click window 1` (the title bar) is required before sending key events,
//   or the simulator silently swallows them - `set frontmost to true` alone
//   is not enough to get real OS-level key focus for this app.
// - Buttons map to standard macOS virtual key codes: SELECT=Return(36),
//   BACK=Escape(53), UP=126, DOWN=125.
// - MENU (a long-press of UP per simulator.json's `keys` array) can only be
//   done as a mouse press-and-hold on the skin's button - see
//   mouse-hold.swift's header for the eight keyboard approaches ruled out.
// - The watch's actual screen sits at a fixed offset within the window:
//   simulator.json's `display.location` gives the rect within the device
//   image, which itself starts 28pt below the window's top-left (a standard
//   macOS title bar). Those numbers come from DeviceProfile now rather than
//   being hardcoded for the Instinct, so any device with an SDK skin works.

import { execFile, execFileSync, spawn, spawnSync } from "node:child_process";
import { readFile, rm, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import type { DeviceProfile, Point } from "./device-profile.ts";
import { resolve as resolveTool } from "../resolve-tool.ts";
import type { Button, Platform } from "./platform.ts";

const execFileAsync = promisify(execFile);

const OCR_SCRIPT = fileURLToPath(new URL("ocr.swift", import.meta.url));
const MOUSE_HOLD_SCRIPT = fileURLToPath(new URL("mouse-hold.swift", import.meta.url));
const MOUSE_SWIPE_SCRIPT = fileURLToPath(new URL("mouse-swipe.swift", import.meta.url));

const SIMULATOR_PROCESS_PATTERN = "ConnectIQ.app/Contents/MacOS/simulator";
const TITLE_BAR_POINTS = 28;
// Chrome the simulator adds around the skin image: the macOS title bar plus
// the app's own status strip underneath the watch. Measured as the difference
// between the window height and the skin PNG's height, and the same on every
// device skin checked (instinct3solar45mm 552-496, venu3 938-882).
const WINDOW_CHROME_POINTS = 56;
// Where Menu2 draws its first item, as a fraction of screen height - measured
// on venu3 and vivoactive6. Used only for the touch SELECT below.
const FIRST_MENU_ROW_FRACTION = 0.37;

const KEY_CODES: Record<Button, number> = {
    select: 36,
    back: 53,
    up: 126,
    down: 125,
};

interface Bounds {
    x: number;
    y: number;
    width: number;
    height: number;
}

function runAppleScript(script: string): string {
    return execFileSync("osascript", [], { input: script, encoding: "utf8" });
}

async function sleep(ms: number): Promise<void> {
    await new Promise<void>((res) => setTimeout(res, ms));
}

function tempPngPath(tag: string): string {
    return join(tmpdir(), `mace-clubs-e2e-${tag}-${String(Date.now())}-${String(Math.random()).slice(2)}.png`);
}

export class MacosPlatform implements Platform {
    readonly name = "macos";
    readonly device: DeviceProfile;

    constructor(device: DeviceProfile) {
        this.device = device;
    }

    /** The skin's native size plus the simulator's chrome. The window can
     * briefly report something else (zero/tiny) while macOS is still
     * animating it open, which would make an early screenshot capture window
     * chrome instead of the watch screen - prepareWindow() forces it here. */
    private expectedWindowSize(): { width: number; height: number } {
        return {
            width: this.device.skinSize.width,
            height: this.device.skinSize.height + WINDOW_CHROME_POINTS,
        };
    }

    startSimulator(): void {
        const connectiqBin = resolveTool("connectiq", homedir(), process.env["PATH"] ?? "");
        spawn(connectiqBin, [], { detached: true, stdio: "ignore" }).unref();
    }

    isSimulatorRunning(): boolean {
        return spawnSync("pgrep", ["-f", SIMULATOR_PROCESS_PATTERN]).status === 0;
    }

    killSimulator(): void {
        spawnSync("pkill", ["-9", "-f", SIMULATOR_PROCESS_PATTERN]);
    }

    windowExists(): boolean {
        try {
            const out = runAppleScript(
                'tell application "System Events" to tell process "simulator" to return count of windows',
            ).trim();
            return Number(out) > 0;
        } catch {
            return false;
        }
    }

    /** The window is a normal resizable macOS window - a previous session
     * (or the user dragging it) can leave it at any size or position, both of
     * which break the crop and click maths. Force it back rather than hoping.
     *
     * The move to the origin is not cosmetic. A big skin is a big window
     * (venu3's is 636x938pt against roughly 1512x982pt of usable display), so
     * wherever the simulator happens to open it, part of it can hang off the
     * screen - and a click at a coordinate with no display under it is
     * silently dropped. That is exactly how it failed: screenshots still
     * looked right because the watch face was on-screen, while every
     * hold("menu") landed on the button hanging past the right edge and did
     * nothing. `screencapture` names the condition outright if you ever crop
     * there: "does not intersect any displays". */
    async prepareWindow(): Promise<void> {
        const expected = this.expectedWindowSize();
        runAppleScript(`
            tell application "System Events"
                tell process "simulator"
                    set position of window 1 to {0, 0}
                    set size of window 1 to {${String(expected.width)}, ${String(expected.height)}}
                end tell
            end tell
        `);
        const deadline = Date.now() + 5000;
        while (Date.now() < deadline) {
            const bounds = this.windowBounds();
            if (bounds.width === expected.width && bounds.height === expected.height) {
                return;
            }
            await sleep(250);
        }
        throw new Error("timed out after 5000ms waiting for the simulator window to resize");
    }

    /** Real OS-level key focus needs an actual click on the window - being
     * "frontmost" per System Events is not sufficient for this app. */
    focus(): void {
        runAppleScript(`
            tell application "System Events"
                tell process "simulator"
                    set frontmost to true
                    click window 1
                end tell
            end tell
        `);
    }

    async pressKey(button: Button): Promise<void> {
        // 30 manifest devices have no UP/DOWN keys and drop the arrow-key
        // event entirely; a swipe raises the same next/previous-page
        // behaviour there. Verified on vivoactive6, where a swipe up cycles
        // the preset exactly as DOWN does on the Instinct.
        if (!this.device.hasUpDownKeys && this.device.isTouch) {
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
                await this.clickHotspot(esc);
                return;
            }
        }
        runAppleScript(`tell application "System Events" to key code ${String(KEY_CODES[button])}`);
    }

    /**
     * SELECT as a screen tap, for touch devices with no UP/DOWN keys.
     *
     * Two things make this necessary rather than cosmetic. A Menu2 on those
     * watches is touch-first: nothing is highlighted until you scroll, so
     * ENTER confirms nothing and every test wedged on the equipment picker.
     * And a tap anywhere on the watch face raises SELECT anyway, so one
     * gesture covers both cases - on an ordinary screen it is a plain
     * SELECT, on a menu it picks the row underneath.
     *
     * The row fraction is where Menu2 puts its first item (measured on venu3
     * and vivoactive6), so "press select to accept the default" keeps meaning
     * the first entry, as it does with a button.
     */
    /** A short click on one of the skin's physical buttons. Touch devices
     * need this for BACK: their system dialogs are touch-first and a
     * synthetic Escape leaves a Confirmation on screen, while clicking the
     * real button dismisses it. */
    private async clickHotspot(hotspot: Point): Promise<void> {
        const bounds = this.windowBounds();
        await execFileAsync("swift", [
            MOUSE_HOLD_SCRIPT,
            String(bounds.x + hotspot.x),
            String(bounds.y + TITLE_BAR_POINTS + hotspot.y),
            "60",
        ]);
    }

    private async tapSelect(): Promise<void> {
        const bounds = this.windowBounds();
        const screen = this.device.screen;
        const x = bounds.x + screen.x + screen.width / 2;
        const y = bounds.y + TITLE_BAR_POINTS + screen.y + screen.height * FIRST_MENU_ROW_FRACTION;
        await execFileAsync("swift", [MOUSE_HOLD_SCRIPT, String(x), String(y), "60"]);
    }

    /** DOWN (next page) is a swipe *up* the screen, and vice versa. */
    private async swipe(button: "up" | "down"): Promise<void> {
        const bounds = this.windowBounds();
        const screen = this.device.screen;
        const centreX = bounds.x + screen.x + screen.width / 2;
        const top = bounds.y + TITLE_BAR_POINTS + screen.y + screen.height * 0.3;
        const bottom = bounds.y + TITLE_BAR_POINTS + screen.y + screen.height * 0.7;
        const [from, to] = button === "down" ? [bottom, top] : [top, bottom];
        await execFileAsync("swift", [
            MOUSE_SWIPE_SCRIPT,
            String(centreX),
            String(from),
            String(centreX),
            String(to),
        ]);
    }

    async holdMenu(holdMs: number): Promise<void> {
        const hotspot = this.device.menuHotspot;
        if (hotspot === null) {
            throw new Error(`device "${this.device.id}" has no MENU key - a test needing hold("menu") must skip it`);
        }
        const bounds = this.windowBounds();
        const x = bounds.x + hotspot.x;
        const y = bounds.y + TITLE_BAR_POINTS + hotspot.y;
        await execFileAsync("swift", [MOUSE_HOLD_SCRIPT, String(x), String(y), String(holdMs)]);
    }

    async captureScreen(): Promise<Buffer> {
        const bounds = this.windowBounds();
        const screen = this.device.screen;
        const screenX = bounds.x + screen.x;
        const screenY = bounds.y + TITLE_BAR_POINTS + screen.y;
        const tmpPath = tempPngPath("shot");
        await execFileAsync("screencapture", [
            "-x",
            `-R${String(screenX)},${String(screenY)},${String(screen.width)},${String(screen.height)}`,
            tmpPath,
        ]);
        try {
            return await readFile(tmpPath);
        } finally {
            await rm(tmpPath, { force: true });
        }
    }

    async ocr(png: Buffer): Promise<string[]> {
        const tmpPath = tempPngPath("ocr");
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
}
