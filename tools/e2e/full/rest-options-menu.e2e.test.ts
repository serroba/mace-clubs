// e2e test for the free-training rest options menu (MENU held while
// free-resting - see MaceClubsDelegate.mc's onMenu(): free-resting and not
// paused routes to RestOptionsMenu rather than the discard confirmation,
// so the next set's movement/side can change without abandoning the
// session). Builds on the same navigation as rest-screen.e2e.test.ts.

import { after, before, describe, it } from "node:test";

import { assertScreenShows } from "../ocr-match.ts";

import { openRestOptions } from "../open-menu.ts";
import { Simulator } from "../simulator.ts";

void describe("Rest options menu", () => {
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

        // Free-resting, not paused: the menu is Rest options, not discard.
        await openRestOptions(sim);

        const joined = (await sim.readText()).join(" ");
        // The first row only. Not the "Rest options" title, which Menu2 wraps
        // on a 208px Forerunner 55 and gives back as "Rest"; and not the side
        // row, which on that screen is below the fold.
        assertScreenShows(joined, "Move");

        // The rows below the first, scrolled to rather than asserted where
        // they may not be. A button steps one row, but a swipe flings a touch
        // list by a variable amount and overscrolls a three-item menu, so
        // this presses until each is actually visible rather than a fixed
        // number of times.
        await sim.pressUntilVisible("down", "Side");
        await sim.pressUntilVisible("down", "Discard");
    });
});
