// The platform seam for the e2e driver: everything about controlling the
// Connect IQ simulator that differs between macOS (AppleScript +
// screencapture + Vision OCR) and Linux (Xvfb + xdotool + ImageMagick +
// Tesseract). `simulator.ts` holds all the orchestration - launch/retry
// sequencing, settle-waiting, press-until-changed - and calls through this
// interface for the handful of genuinely OS-specific primitives.
//
// There is no official automation API for this app on either platform;
// every mechanic behind these implementations was found empirically and is
// documented at the top of the file that implements it.
//
// Neither backend hardcodes a device any more: the screen crop, the MENU
// button hotspot and the expected window size all come from the SDK's own
// simulator.json via DeviceProfile, so the same suite runs on any device the
// SDK has a skin for.

import type { DeviceProfile } from "./device-profile.ts";

export type Button = "select" | "back" | "up" | "down";

export interface Platform {
    /** For error messages and skip conditions. */
    readonly name: string;

    /** The device this backend was built for. Screenshot geometry, the MENU
     * hotspot and the window size all come from its profile, so a test can
     * ask what it is running on - `menuHotspot === null` means the device has
     * no MENU key and anything needing hold("menu") should skip. */
    readonly device: DeviceProfile;

    /** Start the simulator GUI, detached, plus any display server it needs.
     * Does not wait for it to finish booting. */
    startSimulator(): void;
    isSimulatorRunning(): boolean;
    killSimulator(): void;

    /** Has the simulator drawn a window yet? Polled after startSimulator(). */
    windowExists(): boolean;

    /** Called once after the window appears, before any interaction - the
     * place for platform-specific window setup (macOS resizes it back to the
     * size its crop geometry assumes). */
    prepareWindow(): Promise<void>;

    /** Give the simulator real input focus. Needed before every press: both
     * platforms silently drop key events sent to an unfocused window. */
    focus(): void;

    /** One tap of a button. */
    pressKey(button: Button): Promise<void>;

    /** Press and hold MENU for holdMs. Both platforms do this as a mouse
     * press-and-hold on the skin's UP-button hotspot rather than a key
     * event: the simulator maps keyboard input to taps only, so no
     * synthesized key event of any kind produces a hold. */
    holdMenu(holdMs: number): Promise<void>;

    /** PNG of just the watch screen (this device's `screen` rect), not the
     * surrounding device bezel or window chrome. */
    captureScreen(): Promise<Buffer>;

    /** One string per recognized line of on-screen text. */
    ocr(png: Buffer): Promise<string[]>;
}
