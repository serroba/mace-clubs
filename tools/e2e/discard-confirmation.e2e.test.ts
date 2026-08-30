// e2e test for the "Discard & go home?" confirmation that guards against a
// stray MENU press binning a real session (see MaceClubsDelegate.mc's
// onMenu(): held once a workout has started and isn't free-resting, it
// goes straight to this confirmation rather than the settings menu).
//
// Only asserts the confirmation appears and can be dismissed without
// discarding (BACK backs out of a Confirmation on this device; UP/DOWN
// only move focus between Cancel/Confirm) - the destructive Confirm path
// isn't exercised here, since confirming it ends the workout and this
// test's job is to verify the safety gate exists and works, not to
// discard one.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { Simulator } from "./simulator.ts";

void describe("Discard confirmation", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("guards MENU during a workout and can be dismissed", async () => {
        // Home -> Choose equipment (accept default: Mace).
        await sim.pressUntilChanged("select");
        // Choose equipment -> Choose movement (accept default: 360).
        await sim.press("select");
        // Choose movement -> "GET READY" 5s countdown.
        await sim.press("select");
        // Known fixed-duration countdown - see docs/e2e-testing.md on why
        // this is a plain sleep rather than waitForStable().
        await new Promise((resolve) => setTimeout(resolve, 6500));

        // Now in WORK phase. MENU here (not free-resting) goes straight to
        // the discard confirmation rather than the settings menu.
        await sim.hold("menu");

        const confirmLines = (await sim.readText()).join(" ");
        assert.match(confirmLines, /Discard/);
        assert.match(confirmLines, /home/);

        // BACK backs out of the confirmation without discarding - the
        // workout must still be running afterward.
        await sim.press("back");
        const afterLines = (await sim.readText()).join(" ");
        assert.doesNotMatch(afterLines, /Discard/, "confirmation should be dismissed");
    });
});
