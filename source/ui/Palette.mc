import Toybox.Graphics;

// One accent colour, chosen so that it survives a two-colour display.
//
// Connect IQ gives no way to ask whether a display has colour. `colorDepth`
// exists only as an option when creating a BufferedBitmap, never as a device
// property, so the app cannot branch on it at runtime - and eight of the 120
// devices in the manifest are two-colour (the Instinct 2, Instinct 3 Solar and
// Instinct E families, instinctcrossover, descentg1), including the watch this
// app is actually validated on.
//
// The way around that is to choose an accent the hardware resolves towards
// white rather than black. A monochrome device then draws exactly what it draws
// today, and the other 112 get the colour for free - no per-device resources,
// no detection, no fallback path to keep working. ACCENT is deliberately light
// for that reason: a dim accent would resolve to black and disappear on the
// very watch the app is built around.
module Palette {
    // A warm brass, matching the project's own accent, and light enough that
    // both plausible mappings a two-colour panel could use - nearest colour by
    // RGB distance, or a luminance threshold - land on white rather than
    // black. PaletteTest asserts the first of those; the second follows from
    // the same brightness. What no test can settle is which rule the hardware
    // actually applies, so this wants one look on a real Instinct.
    const ACCENT = 0xE8B45F;
    const TEXT = Graphics.COLOR_WHITE;
    const BACKGROUND = Graphics.COLOR_BLACK;
}
