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

export type Button = "select" | "back" | "up" | "down";

/** The watch's own screen within the simulator window, excluding the device
 * bezel art around it - so screenshots and baselines contain only app
 * pixels. Both platforms crop to the same 176x176 region of the same skin;
 * only the offset differs (Linux's window-manager decoration shifts it). */
export const SCREEN_SIZE = { width: 176, height: 176 } as const;

export interface Platform {
    /** For error messages and skip conditions. */
    readonly name: string;

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

    /** PNG of just the watch screen (SCREEN_SIZE), not the surrounding
     * device bezel or window chrome. */
    captureScreen(): Promise<Buffer>;

    /** One string per recognized line of on-screen text. */
    ocr(png: Buffer): Promise<string[]>;
}
