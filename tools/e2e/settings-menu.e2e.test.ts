// e2e test for the on-watch Settings menu (MENU held from idle - see
// MaceClubsDelegate.mc's onMenu(), which routes MENU to Settings only
// before a workout starts). Sideloaded builds don't get Garmin Connect's
// settings gear, so this on-watch menu is the only way to reach most
// settings - worth a direct regression check that it still opens at all.

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

void suite("Settings menu", () => {
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
        assertScreenShows(joined, "Settings");
        assertScreenShows(joined, "History");
    });
});
