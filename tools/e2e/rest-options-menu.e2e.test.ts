// e2e test for the free-training rest options menu (MENU held while
// free-resting - see MaceClubsDelegate.mc's onMenu(): free-resting and not
// paused routes to RestOptionsMenu rather than the discard confirmation,
// so the next set's movement/side can change without abandoning the
// session). Builds on the same navigation as rest-screen.e2e.test.ts.

import { after, before, describe, it } from "node:test";

import { assertScreenShows } from "./ocr-match.ts";

import { deviceProfile, Simulator } from "./simulator.ts";

// MENU is a held button, and seven shipped devices have no MENU key at all
// (the venu 4 family, venux1, vivoactive6, the vivoactive3 variants). On
// those there is no hotspot to press and hold, so this file skips rather
// than clicking empty bezel and failing on an OCR mismatch. DeviceInput's
// on-screen tap target is what covers the same route there; it needs a
// coordinate tap the driver does not model yet.
const suite = deviceProfile().menuHotspot === null ? describe.skip : describe;

void suite("Rest options menu", () => {
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
        assertScreenShows(joined, "Rest options");
        assertScreenShows(joined, "Move");
        assertScreenShows(joined, "Side");

        // "Discard & go home" is the last item and below the fold on this
        // screen. Scroll until it is actually visible rather than pressing a
        // fixed number of times: a button steps one row, but a swipe flings a
        // touch list by a variable amount and overscrolls a three-item menu.
        await sim.pressUntilVisible("down", "Discard");
    });
});
