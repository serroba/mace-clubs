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

import { after, before, describe, it } from "node:test";

import { assertScreenLacks, assertScreenShows } from "./ocr-match.ts";

import { deviceProfile, Simulator } from "./simulator.ts";

// MENU is a held button, and seven shipped devices have no MENU key at all
// (the venu 4 family, venux1, vivoactive6, the vivoactive3 variants). On
// those there is no hotspot to press and hold, so this file skips rather
// than clicking empty bezel and failing on an OCR mismatch. DeviceInput's
// on-screen tap target is what covers the same route there; it needs a
// coordinate tap the driver does not model yet.
const suite = deviceProfile().menuHotspot === null ? describe.skip : describe;

void suite("Discard confirmation", () => {
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
        assertScreenShows(confirmLines, "Discard");
        assertScreenShows(confirmLines, "home");

        // BACK backs out of the confirmation without discarding - the
        // workout must still be running afterward.
        await sim.press("back");
        const afterLines = (await sim.readText()).join(" ");
        assertScreenLacks(afterLines, "Discard", "confirmation should be dismissed");
    });
});
