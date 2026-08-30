// e2e test for the post-workout summary screen (see MaceClubsView.mc's
// finishWorkout(): BACK pauses a running workout, then SELECT while paused
// saves it and pushes WorkoutSummaryView in place of exiting immediately).
// Only the first ("SUMMARY") page is asserted - it's static per-workout
// content (set count, work time, equipment/movement), not time-of-day
// data, so this is a fair landmark check without needing every page.
//
// The summary auto-exits the whole app after 60s (MaceClubsView's
// SUMMARY_EXIT_DELAY_MS) as a backstop for a watch left face-up - this
// test finishes well within that window and never presses SELECT/BACK
// again itself, since either would trigger WorkoutSummaryDelegate's own
// immediate exitApp().

import { after, before, describe, it } from "node:test";

import { assertScreenShows } from "./ocr-match.ts";

import { Simulator } from "./simulator.ts";

void describe("Workout summary screen", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("shows sets, work time, and equipment/movement after finishing", async () => {
        // Home -> Choose equipment (accept default: Mace).
        await sim.pressUntilChanged("select");
        // Choose equipment -> Choose movement (accept default: 360).
        await sim.press("select");
        // Choose movement -> "GET READY" 5s countdown.
        await sim.press("select");
        await new Promise((resolve) => setTimeout(resolve, 6500));

        // WORK -> pause.
        await sim.press("back");
        // Paused -> save & show summary.
        await sim.press("select");

        const joined = (await sim.readText()).join(" ");
        assertScreenShows(joined, "SUMMARY");
        assertScreenShows(joined, "sets");
        assertScreenShows(joined, "work");
        assertScreenShows(joined, "BACK exit");
    });
});
