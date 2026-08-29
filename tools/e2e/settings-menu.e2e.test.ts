// e2e test for the on-watch Settings menu (MENU held from idle - see
// MaceClubsDelegate.mc's onMenu(), which routes MENU to Settings only
// before a workout starts). Sideloaded builds don't get Garmin Connect's
// settings gear, so this on-watch menu is the only way to reach most
// settings - worth a direct regression check that it still opens at all.
//
// Skipped: Simulator.hold() doesn't actually hold anything yet - see
// docs/e2e-testing.md's "Known issue: Simulator.hold() doesn't actually
// hold" section for everything tried so far.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { Simulator } from "./simulator.ts";

void describe.skip("Settings menu", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("opens from idle with History as the first item", async () => {
        await sim.hold("menu");

        const joined = (await sim.readText()).join(" ");
        assert.match(joined, /Settings/);
        assert.match(joined, /History/);
    });
});
