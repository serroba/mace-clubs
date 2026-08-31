// Drives the app to a running interval and reports what colour the work phase
// actually came out, per device.
//
// Connect IQ cannot tell an app whether its display has colour, so the accent
// in source/ui/Palette.mc relies on a two-colour panel resolving it towards
// white rather than black. That is an assumption about hardware behaviour, and
// the only way to settle it is to render on both kinds of device and look at
// the pixels.

import { writeFileSync } from "node:fs";
import { PNG } from "pngjs";

import { Simulator } from "../simulator.ts";

const device = process.env["MACE_E2E_DEVICE"] ?? "instinct3solar45mm";

/**
 * What the phase line was actually painted in. Restricted to the band the
 * "SET n/m WORK" text occupies and to the left of the subwindow, because the
 * Instinct paints its own orange ring around that cut-out and it would
 * otherwise drown out the answer.
 */
function phaseLineColours(png: PNG): string[] {
    // The phase line sits at 18% (full-width layouts) or 20% (subwindow
    // ones), so the band has to start above both. The right bound keeps the
    // Instinct's own orange subwindow ring out of the sample.
    const top = Math.round(png.height * 0.12);
    const bottom = Math.round(png.height * 0.30);
    const right = Math.round(png.width * 0.62);
    const seen = new Map<string, number>();
    for (let y = top; y < bottom; y += 1) {
        for (let x = 0; x < right; x += 1) {
            const i = (y * png.width + x) * 4;
            const r = png.data[i] ?? 0;
            const g = png.data[i + 1] ?? 0;
            const b = png.data[i + 2] ?? 0;
            if (r + g + b < 90) continue; // background
            const key = `#${[r, g, b].map((c) => c.toString(16).padStart(2, "0")).join("")}`;
            seen.set(key, (seen.get(key) ?? 0) + 1);
        }
    }
    return [...seen.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, 6)
        .map(([hex, n]) => `${hex} x${String(n)}`);
}

const sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
try {
    // Free training is preset 0 and draws its own phase line; the coloured one
    // lives in the interval branch, so step to the first interval preset.
    console.log(`idle before : ${(await sim.readText()).join(" | ").slice(0, 70)}`);
    await sim.press("down");
    console.log(`idle after  : ${(await sim.readText()).join(" | ").slice(0, 70)}`);
    await sim.pressUntilChanged("select");
    await sim.press("select");
    await sim.press("select");
    // The five-second start countdown has to elapse before the running screen
    // exists; a fixed wait for a known duration beats polling for stability.
    await new Promise((resolve) => setTimeout(resolve, 7000));

    const shot = await sim.screenshot();
    writeFileSync(`tmp/work-${device}.png`, shot);

    const png = PNG.sync.read(shot);
    const colours = phaseLineColours(png);
    console.log(`device      : ${device}`);
    console.log(`screen text : ${(await sim.readText()).join(" | ").slice(0, 80)}`);
    console.log(`phase line  : ${colours.length > 0 ? colours.join(", ") : "nothing lit in that band"}`);
} finally {
    sim.close();
}
