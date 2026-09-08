// e2e test for the on-watch Settings menu (MENU held from idle - see
// MaceClubsDelegate.mc's onMenu(), which routes MENU to Settings only
// before a workout starts). Sideloaded builds don't get Garmin Connect's
// settings gear, so this on-watch menu is the only way to reach most
// settings - worth a direct regression check that it still opens at all.

import { after, before, describe, it } from "node:test";

import { assertScreenShows } from "../ocr-match.ts";

import { openSettingsMenu } from "../open-menu.ts";
import { Simulator } from "../simulator.ts";

void describe("Settings menu", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("opens from idle with History as the first item", async () => {
        await openSettingsMenu(sim);

        const joined = (await sim.readText()).join(" ");
        assertScreenShows(joined, "Settings");

        // History is the first row and therefore the highlighted one, which
        // Menu2 draws already inverted - the case the OCR's two polarities
        // exist for, and one a Forerunner 945 defeats anyway, reading the
        // menu as "Settings Mode: intervals" with the top row missing
        // entirely. pressUntilVisible steps off it, which un-inverts it, and
        // returns as soon as it can be read; it checks before pressing, so a
        // device that reads the row where it stands does not move at all.
        await sim.pressUntilVisible("down", "History");
    });
});
