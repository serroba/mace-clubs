// Per-device geometry for the e2e driver, read from the SDK's own
// simulator.json rather than hardcoded.
//
// The driver used to carry the Instinct 3 Solar's numbers as constants
// (screen at {101,158} 176x176, MENU hotspot at {2,212,33x68}, window
// 381x552) and refuse to launch anything else, because cropping the wrong
// region silently produces a screenshot of bezel art rather than an obvious
// failure. Those numbers all come from one file the SDK already ships for
// every device, so reading them turns "one supported device" into "any device
// whose skin the SDK has" - which is what lets the same suite check a 454px
// Venu 3 and a 390px vivoactive6, where the layout defects this suite exists
// to catch actually appeared.
//
// Layout of the file we care about:
//   display.location  {x, y, width, height}  the watch screen within the skin
//   keys[]            {id, location}          button hotspots within the skin
//   image             the skin PNG's filename
//
// Coordinates are relative to the skin image's top-left. The simulator window
// adds chrome above it (a title bar, plus the app's own status strip); the
// caller adds that offset since it differs by host OS.

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface Point {
    x: number;
    y: number;
}

export interface Rect extends Point {
    width: number;
    height: number;
}

export interface DeviceProfile {
    readonly id: string;
    /** The watch screen within the skin image. */
    readonly screen: Rect;
    /** The skin image's own size - the window is this plus chrome. */
    readonly skinSize: { width: number; height: number };
    /**
     * Centre of the MENU button's hotspot within the skin image, or null on
     * the seven devices that have no MENU key at all (the venu 4 family,
     * venux1, vivoactive6, the vivoactive3 variants). Tests that need MENU
     * skip themselves there rather than clicking empty bezel.
     */
    readonly menuHotspot: Point | null;
    /**
     * Centre of the BACK/ESC button's hotspot, or null where there is none
     * (vivoactive3 has only an ENTER key). Touch devices need this: their
     * system dialogs are touch-first, and a synthetic Escape key does not
     * dismiss a Confirmation the way clicking the real button does.
     */
    readonly escHotspot: Point | null;
    /**
     * Whether the device has physical UP/DOWN keys. 30 of the 120 manifest
     * devices do not, and on those an arrow key press is simply dropped -
     * which is why menu navigation has to become a swipe (see isTouch).
     */
    readonly hasUpDownKeys: boolean;
    /** Touch screen, so swipes can stand in for the missing keys. */
    readonly isTouch: boolean;
}

interface SimulatorJson {
    display: { location: Rect; isTouch?: boolean };
    keys?: { id: string; location: Rect }[];
    image?: string;
}

/**
 * Where the SDK keeps its per-device files. The Windows/macOS SDK manager and
 * the Linux CLI disagree, and CI runs as root in a container, so all three
 * candidates are tried rather than branching on process.platform.
 */
function deviceDirectories(): string[] {
    const home = homedir();
    return [
        join(home, "Library", "Application Support", "Garmin", "ConnectIQ", "Devices"),
        join(home, ".Garmin", "ConnectIQ", "Devices"),
        "/root/.Garmin/ConnectIQ/Devices",
    ];
}

/** Device ids the SDK has files for, for an error message worth reading. */
function availableDevices(): string[] {
    for (const dir of deviceDirectories()) {
        if (!existsSync(dir)) {
            continue;
        }
        try {
            return execFileSync("ls", [dir], { encoding: "utf8" })
                .split("\n")
                .map((line) => line.trim())
                .filter((line) => line.length > 0);
        } catch {
            return [];
        }
    }
    return [];
}

export function loadDeviceProfile(id: string): DeviceProfile {
    let raw: string | null = null;
    for (const dir of deviceDirectories()) {
        const candidate = join(dir, id, "simulator.json");
        if (existsSync(candidate)) {
            raw = readFileSync(candidate, "utf8");
            break;
        }
    }
    if (raw === null) {
        const known = availableDevices();
        const hint = known.length > 0 ? ` Devices the SDK has: ${known.slice(0, 8).join(", ")}...` : "";
        throw new Error(
            `no simulator.json for device "${id}" - looked in ${deviceDirectories().join(", ")}.${hint}`,
        );
    }

    const parsed = JSON.parse(raw) as SimulatorJson;
    const location = parsed.display.location;
    // "menu" and "up" often share one hotspot (MENU being the long-press
    // variant); either entry gives the same centre, but only a real "menu"
    // entry means the behaviour is reachable at all.
    const keys = parsed.keys ?? [];
    const menuKey = keys.find((key) => key.id === "menu");
    const escKey = keys.find((key) => key.id === "esc");
    const centreOf = (key: { location: Rect } | undefined): Point | null =>
        key === undefined
            ? null
            : { x: key.location.x + key.location.width / 2, y: key.location.y + key.location.height / 2 };

    return {
        id,
        screen: { x: location.x, y: location.y, width: location.width, height: location.height },
        skinSize: skinSize(id, parsed),
        hasUpDownKeys: keys.some((key) => key.id === "up") && keys.some((key) => key.id === "down"),
        isTouch: parsed.display.isTouch === true,
        menuHotspot: centreOf(menuKey),
        escHotspot: centreOf(escKey),
    };
}

/**
 * The skin PNG's pixel dimensions. Read from the image itself rather than
 * assumed: it is what the simulator sizes its window to, and the window has
 * to be forced back to that size before any crop maths is trustworthy (a
 * previous session or a stray drag can leave it at anything).
 */
function skinSize(id: string, parsed: SimulatorJson): { width: number; height: number } {
    const imageName = parsed.image;
    if (imageName !== undefined) {
        for (const dir of deviceDirectories()) {
            const imagePath = join(dir, id, imageName);
            if (existsSync(imagePath)) {
                const size = readPngSize(imagePath);
                if (size !== null) {
                    return size;
                }
            }
        }
    }
    // Fall back to the display's own extent plus its offset - enough for the
    // window to contain the screen, which is all the crop needs.
    const location = parsed.display.location;
    return { width: location.x * 2 + location.width, height: location.y * 2 + location.height };
}

/** PNG header parse - width and height are big-endian u32s at bytes 16..24. */
function readPngSize(path: string): { width: number; height: number } | null {
    try {
        const header = readFileSync(path).subarray(0, 24);
        if (header.length < 24) {
            return null;
        }
        return { width: header.readUInt32BE(16), height: header.readUInt32BE(20) };
    } catch {
        return null;
    }
}
