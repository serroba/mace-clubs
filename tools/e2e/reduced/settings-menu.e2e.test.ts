// e2e test for the on-watch Settings menu on a reduced build.
//
// The counterpart of ../full/settings-menu.e2e.test.ts. Same screen, same
// route into it (MENU held from idle - see MaceClubsDelegate.mc's onMenu()),
// different contents: the devices this suite runs on ship without the
// history browser, because the app does not otherwise fit in their 96KB.
// See tools/reduced-devices.ts for which devices those are and why, and
// docs/e2e-testing.md for how the two suites are selected.
//
// Kept as its own file rather than a branch inside the shared one. A
// conditional would put the jungle's device list in the assertion, where it
// would have to be right in two places at once; here each file simply says
// what its build shows.

import { after, before, describe, it } from "node:test";

import { assertScreenShows } from "../ocr-match.ts";

import { deviceProfile, Simulator } from "../simulator.ts";

// MENU is a held button, and seven shipped devices have no MENU key at all.
// None of them are small enough to run this suite today, but the skip costs
// nothing and stops a future one failing on an OCR mismatch after clicking
// empty bezel.
const suite = deviceProfile().menuHotspot === null ? describe.skip : describe;

void suite("Settings menu (reduced build)", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("opens from idle, with the training rows and no history browser", async () => {
        await sim.hold("menu");

        const joined = (await sim.readText()).join(" ");
        assertScreenShows(joined, "Settings");
        // What the reduced build drops. Asserting its absence is the point of
        // this file: without it, removing history from a device nobody drives
        // and quietly removing it from every device look identical in CI.
        assertScreenAbsent(joined, "History");
        // What it keeps. The menu is still the only way to reach most
        // settings on a sideloaded build, so "no history" must not have
        // become "no menu".
        assertScreenShows(joined, "Mode");
    });
});

/** The inverse of assertScreenShows, with the same OCR tolerance: a word is
 * absent only if nothing on screen is within one edit of it. */
function assertScreenAbsent(haystack: string, word: string): void {
    let found = true;
    try {
        assertScreenShows(haystack, word);
    } catch {
        found = false;
    }
    if (found) {
        throw new Error(`expected "${word}" NOT to be on screen, but read: "${haystack}"`);
    }
}
