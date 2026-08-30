// e2e test for the free-training rest options menu (MENU held while
// free-resting - see MaceClubsDelegate.mc's onMenu(): free-resting and not
// paused routes to RestOptionsMenu rather than the discard confirmation,
// so the next set's movement/side can change without abandoning the
// session). Builds on the same navigation as rest-screen.e2e.test.ts.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { Simulator } from "./simulator.ts";

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

        // Free-resting, not paused: MENU opens Rest options, not discard.
        await sim.hold("menu");

        const joined = (await sim.readText()).join(" ");
        assert.match(joined, /Rest options/i);
        assert.match(joined, /Move/i);
        assert.match(joined, /Side/i);

        // "Discard & go home" is the third item - below the fold on this
        // screen, so scroll down until it's visible before asserting it.
        await sim.press("down");
        await sim.press("down");
        const scrolled = (await sim.readText()).join(" ");
        assert.match(scrolled, /Discard/i);
    });
});
