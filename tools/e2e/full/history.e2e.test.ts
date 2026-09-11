// e2e test for the saved-session browser: Settings > History > one session.
//
// The last of the three screens the coverage split turned up, and the one
// that needed data before it could be opened at all. Ten function bodies
// nothing reached: HistoryMenuDelegate's two, HistoryDetailDelegate's four,
// and the detail view's onUpdate, drawOverview, drawSet and formatSecs.
//
// The data is recorded rather than injected. A test process on the host
// cannot call Application.Storage - it is a Node process outside the watch -
// and the simulator's own store is a Garmin binary format (APPS/DATA/*.DAT
// and .IDX) with no documented writer. What it can do is what a user does:
// run a workout, save it, and browse it afterwards. WorkoutSession.save()
// calls appendHistoryLog(), which needs only one completed block, and the
// simulator keeps Storage across launches - so recording a session, exiting
// and relaunching leaves exactly the state this screen exists to show.
//
// That is also why this is the file that tests the save path end to end: the
// record it browses is one the app wrote, in the shape the app writes, rather
// than a fixture that agrees with the reader by construction.
//
// The unit suite takes the other route, and should: HistoryDetailView is
// constructed with the record passed in, so HistoryDetailViewTest hands it a
// fabricated one (see HistoryDetailFixtures) and never touches Storage. What
// that cannot reach is the drawing and the delegates, which is what this
// covers.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { assertScreenLacks, assertScreenShows } from "../ocr-match.ts";
import { openSettingsMenu } from "../open-menu.ts";
import { Simulator } from "../simulator.ts";

/** How long the start countdown runs, plus a second. The countdown ticks once
 * a second, so waiting for visual stability can land twice inside one tick -
 * a fixed wait for a known duration is the honest thing here, as it is in
 * rest-screen.e2e.test.ts. */
const COUNTDOWN_MS = 6500;

/** Runs a workout far enough to save one, and exits the app.
 *
 * The same sequence workout-summary.e2e.test.ts asserts on, carried one press
 * further: SELECT on the summary is System.exit, and the exit is the point -
 * Storage is what survives it. */
async function recordASession(sim: Simulator): Promise<void> {
    // Home -> Choose equipment (accept the default: Mace).
    await sim.pressUntilChanged("select");
    // Choose equipment -> Choose movement (accept the default: 360).
    await sim.press("select");
    // Choose movement -> "GET READY".
    await sim.press("select");
    await new Promise((resolve) => setTimeout(resolve, COUNTDOWN_MS));

    // One completed set, which is what makes this session worth saving.
    // appendHistoryLog() returns early when no block was closed, and
    // finishWorkout() does not close an open one - it calls save() straight
    // out. Without this press the workout saves, the summary draws, and the
    // history log stays empty: the first run of this test got as far as
    // "History" and found nothing to select.
    await sim.press("select");

    // WORK -> paused -> saved, which is where appendHistoryLog() runs.
    await sim.press("back");
    await sim.press("select");
    assertScreenShows(await sim.readText(), "SUMMARY", "the workout should have saved and shown its summary");

    // WorkoutSummaryDelegate.onSelect is System.exit().
    await sim.press("select");
}

void describe("Saved session history", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("browses a session recorded in an earlier run of the app", async () => {
        await recordASession(sim);

        // A second launch against the same simulator data, which is the whole
        // mechanism: the history browser can only show what outlived the app.
        sim.close();
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });

        // History is the first row of Settings and therefore already
        // highlighted, so this needs no counted presses and works the same on
        // a watch that scrolls by swiping. pressUntilChanged absorbs the press
        // a freshly opened menu swallows.
        await openSettingsMenu(sim);
        await sim.pressUntilChanged("select");
        // No assertion on the browser's own title. A vivoactive 4S reads it as
        // "Histo" - the list is right there behind it, "11 Sep 1:15 --", but
        // the Menu2 title is clipped the same way the weight editor's is. What
        // proves this screen is the history browser is that selecting a row
        // opens a session detail, which is asserted below and cannot happen
        // from anywhere else.

        // HistoryMenuDelegate.onSelect on the newest session, which is the
        // first row. The load-trend row that can sit above it needs motion
        // exposure inside the chronic window, and a simulated workout records
        // none - if that ever changes, this lands on the trend row instead,
        // which selects nothing, and the assertion below says so.
        await sim.pressUntilChanged("select");

        // HistoryDetailView.onUpdate -> drawOverview.
        const overview = await sim.readText();
        assertScreenShows(overview, "rhythm", "the session overview should show its rhythm score");

        // HistoryDetailDelegate.onNextPage -> drawSet, which is where
        // formatSecs runs.
        await sim.press("down");
        assertScreenShows(await sim.readText(), "SET", "DOWN should open the per-set page");

        // HistoryDetailDelegate.onPreviousPage, back to the overview.
        await sim.press("up");
        assertScreenShows(await sim.readText(), "rhythm", "UP should return to the session overview");

        // HistoryDetailDelegate.onBack, back to the list. Asserted as the
        // absence of the detail screen rather than the presence of the title,
        // for the same reason: "rhythm" is on every page of the detail view
        // and on no part of the list.
        await sim.press("back");
        const list = await sim.readText();
        assertScreenLacks(list, "rhythm", "BACK should leave the session detail");
        assert.ok(list.join(" ").length > 0, "the session list should still be readable");
    });
});
