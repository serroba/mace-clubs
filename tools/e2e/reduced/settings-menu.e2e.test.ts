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
//
// It asserts the title and the absence of the history row, and nothing about
// the rows that remain. An earlier version also checked for "Mode", on the
// reasoning that "no history" must not quietly become "no menu" - but the
// row is there and unreadable on a Descent G1, whose Menu2 rows OCR as
// "er aM ALG) Re Cel". A test that fails on legible-to-a-human text is worse
// than the gap it was covering.

import { after, before, describe, it } from "node:test";

import { assertScreenLacks, assertScreenShows } from "../ocr-match.ts";

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

    it("opens from idle, without the history browser", async () => {
        await sim.hold("menu");

        const joined = (await sim.readText()).join(" ");
        assertScreenShows(joined, "Settings");
        // What the reduced build drops. Asserting its absence is the point of
        // this file: without it, removing history from a device nobody drives
        // and quietly removing it from every device look identical in CI.
        assertScreenLacks(joined, "History", "the reduced build has no history browser");
    });
});
