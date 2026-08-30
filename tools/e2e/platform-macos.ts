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
//   simulator.json's `display.location` gives {x:101, y:158, 176x176} within
//   the device image, which itself starts 28pt below the window's top-left
//   (a standard macOS title bar).

import { execFile, execFileSync, spawn, spawnSync } from "node:child_process";
import { readFile, rm, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { resolve as resolveTool } from "../resolve-tool.ts";
import { type Button, type Platform, SCREEN_SIZE } from "./platform.ts";

const execFileAsync = promisify(execFile);

const OCR_SCRIPT = fileURLToPath(new URL("ocr.swift", import.meta.url));
const MOUSE_HOLD_SCRIPT = fileURLToPath(new URL("mouse-hold.swift", import.meta.url));

const SIMULATOR_PROCESS_PATTERN = "ConnectIQ.app/Contents/MacOS/simulator";
const TITLE_BAR_POINTS = 28;
const SCREEN_OFFSET = { x: 101, y: 158 } as const;
// Center of the UP/MENU button's clickable hotspot on the device skin, from
// simulator.json's `keys` array ({x:2, y:212, w:33, h:68} - the "up" and
// "menu" entries share it, menu being the isHold variant).
const MENU_BUTTON_CENTER = { x: 2 + 33 / 2, y: 212 + 68 / 2 } as const;
// The device.png skin's native size (381x496) plus the app's own status
// bar - the window can briefly report a different (e.g. zero/tiny) size
// while macOS is still animating it open, which would make an early
// screenshot capture garbage (window chrome instead of the watch screen).
const EXPECTED_WINDOW_SIZE = { width: 381, height: 552 } as const;

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
     * (or the user dragging it) can leave it at any size, which would break
     * the fixed SCREEN_OFFSET math. Force it back to the size that math
     * assumes rather than hoping for it. */
    async prepareWindow(): Promise<void> {
        runAppleScript(`
            tell application "System Events"
                tell process "simulator"
                    set size of window 1 to {${String(EXPECTED_WINDOW_SIZE.width)}, ${String(EXPECTED_WINDOW_SIZE.height)}}
                end tell
            end tell
        `);
        const deadline = Date.now() + 5000;
        while (Date.now() < deadline) {
            const bounds = this.windowBounds();
            if (bounds.width === EXPECTED_WINDOW_SIZE.width && bounds.height === EXPECTED_WINDOW_SIZE.height) {
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
        runAppleScript(`tell application "System Events" to key code ${String(KEY_CODES[button])}`);
        return Promise.resolve();
    }

    async holdMenu(holdMs: number): Promise<void> {
        const bounds = this.windowBounds();
        const x = bounds.x + MENU_BUTTON_CENTER.x;
        const y = bounds.y + TITLE_BAR_POINTS + MENU_BUTTON_CENTER.y;
        await execFileAsync("swift", [MOUSE_HOLD_SCRIPT, String(x), String(y), String(holdMs)]);
    }

    async captureScreen(): Promise<Buffer> {
        const bounds = this.windowBounds();
        const screenX = bounds.x + SCREEN_OFFSET.x;
        const screenY = bounds.y + TITLE_BAR_POINTS + SCREEN_OFFSET.y;
        const tmpPath = tempPngPath("shot");
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
