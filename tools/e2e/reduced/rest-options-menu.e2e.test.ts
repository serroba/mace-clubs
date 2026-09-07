// e2e test for the free-training rest options menu on a reduced build.
//
// The counterpart of ../full/rest-options-menu.e2e.test.ts: same screen,
// same route into it (MENU held while free-resting), terser rows. Menu2 is
// drawn by the system, and on these watches its font is wide enough that a
// 176px screen clips the full labels off the left edge - "Side: Two-handed"
// renders as "de: Two-handed". Shortening the strings is the only lever we
// have over a system menu, so RestOptionsMenu gives these three devices
// "Options" over "Rest options", the bare side over "Side: <side>", and
// "Discard" over "Discard & go home".
//
// Kept as its own file rather than a branch inside the shared one, for the
// same reason as settings-menu: a conditional would put the jungle's device
// list inside the assertion.

import { after, before, describe, it } from "node:test";

import { assertScreenShows } from "../ocr-match.ts";

import { deviceProfile, Simulator } from "../simulator.ts";

// MENU is a held button; a device without one skips rather than clicking
// empty bezel. None of today's reduced devices are in that group.
const suite = deviceProfile().menuHotspot === null ? describe.skip : describe;

void suite("Rest options menu (reduced build)", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("offers movement, side, and discard during free-training rest", async () => {
        // Home -> Choose equipment (accept default: Mace).
        await sim.pressUntilChanged("select");
        // Choose equipment -> Choose movement (accept default: 360).
        await sim.press("select");
        // Choose movement -> "GET READY" 5s countdown.
        await sim.press("select");
        await new Promise((resolve) => setTimeout(resolve, 6500));

        // WORK -> free-training REST.
        await sim.press("select");

        // Free-resting, not paused: MENU opens Rest options, not discard.
        await sim.hold("menu");

        const joined = (await sim.readText()).join(" ");
        assertScreenShows(joined, "Options");
        assertScreenShows(joined, "Move");

        // Only two rows fit above the fold on a 163x156 Instinct 2S, so the
        // side row has to be scrolled to like the discard row below it.
        // Asserting it without scrolling read it as "eet he" and looked like
        // clipped text; it is simply half of a row at the bottom edge.
        await sim.pressUntilVisible("down", "handed");

        // The discard row is the last item and below the fold on every
        // screen here. Scroll until it is actually visible rather than
        // pressing a fixed number of times: a button steps one row, but a
        // swipe flings a touch list by a variable amount and overscrolls a
        // three-item menu.
        await sim.pressUntilVisible("down", "Discard");
    });
});
