// e2e test for the on-watch Custom preset editor: sets, then work, then rest.
//
// The last screen on the list in docs/e2e-testing.md that neither suite
// reached - nine function bodies, four in the view and five in the delegate.
// A unit test can construct the view and call advance()/retreat() (see
// CustomWorkoutEditorTest) but cannot draw it or press anything, and the
// interesting part of this screen is that SELECT and BACK mean "next field"
// and "previous field" until the ends, where they mean "save and close" and
// "close without saving".
//
// Going there found a real defect, fixed alongside: the step hint read
// "UP/DOWN: 1" on every watch, including the 30 in the manifest that have no
// UP/DOWN keys. Every other hint in the app asks DeviceInput which affordance
// the device actually has; this screen and the workout summary did not.
//
// The values here are asserted in pixels rather than in text, because OCR
// does not return this screen's number at all - see the work-duration step
// below for what it does return and why a capture says the screen is fine.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { isGestureDriven } from "../device-profile.ts";
import { assertScreenLacks, assertScreenShows } from "../ocr-match.ts";
import { openSettingsMenu } from "../open-menu.ts";
import { screensDiffer } from "../pixel-diff.ts";
import { deviceProfile, Simulator } from "../simulator.ts";

/**
 * Down-presses from a freshly opened Settings menu to the custom-workout row.
 *
 * One above the mace weight, and counted for the same reason: a Menu2 shows
 * several rows at once, so scrolling until the text is readable stops on a
 * visible row rather than the highlighted one. SettingsMenu.build's order is
 * history, mode, rep target, corner, wrist, movement, side, cue, then this.
 */
const DOWN_PRESSES_TO_CUSTOM_WORKOUT = 8;

void describe("Custom workout editor", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("walks the three fields, and BACK steps back through them", async (t) => {
        // Counted presses select a row only on a watch whose DOWN steps the
        // highlight one row. A swipe flings a touch list by a variable amount,
        // and SELECT on the wrong row of this menu cycles a real setting.
        if (isGestureDriven(deviceProfile())) {
            t.skip("menu rows cannot be selected by counted presses on a gesture-driven device");
            return;
        }

        await openSettingsMenu(sim);
        // First press through pressUntilChanged: a menu that has just slid
        // into view swallows one.
        await sim.pressUntilChanged("down");
        for (let step = 1; step < DOWN_PRESSES_TO_CUSTOM_WORKOUT; step += 1) {
            await sim.press("down");
        }
        await sim.press("select");

        // CustomWorkoutEditorView.onUpdate, on the first field. "SETS" rather
        // than "NUMBER OF SETS": the title is FONT_SMALL, which is the size
        // OCR drops letters from - the weight editor's "WEIGHT" comes back as
        // "WE HT" on some watches.
        const sets = await sim.readText();
        assertScreenShows(sets, "SETS", "the custom workout editor should open on the set count");
        assertScreenShows(sets, "next", "SELECT moves to the next field, and says so");

        // adjust() on the set count, through onPreviousPage and then
        // onNextPage. Stepped rather than asserted - see shownDuration - and
        // balanced, so the preset this test eventually saves is the one it
        // found.
        await sim.press("up");
        await sim.press("down");

        // advance() to the work duration, then retreat() back to the sets.
        // This is the pair worth an e2e test: they are one press apart and
        // neither closes the editor here.
        await sim.press("select");
        assertScreenShows(await sim.readText(), "WORK", "SELECT should move on to the work duration");
        await sim.press("back");
        assertScreenShows(await sim.readText(), "SETS", "BACK should step back to the set count");

        // Back to the work duration, and assert the adjustment in pixels
        // rather than in text.
        //
        // OCR does not return this screen's value at all. The work field reads
        // back as ["WORK DUR. TION", "UP/DOWN: 0:30", "SELECT: next"] with
        // nothing where the number is, and the set count is worse - one glyph
        // in FONT_NUMBER_MEDIUM. A capture of the screen shows "2:00" drawn
        // perfectly well; Tesseract simply does not hand back that line. So
        // the assertion is that the screen changed and then changed back,
        // which is what a value going up and down looks like, and needs no
        // character to be recognised.
        await sim.press("select");
        const work = await sim.screenshot();
        await sim.press("up");
        assert.ok(screensDiffer(await sim.screenshot(), work), "UP should change the work duration");
        await sim.press("down");
        assert.ok(!screensDiffer(await sim.screenshot(), work), "DOWN should put it back");

        // The last field. Its SELECT is the branch where advance() returns
        // true: it saves and pops.
        await sim.press("select");
        const rest = await sim.readText();
        assertScreenShows(rest, "REST", "the third field is the rest duration");
        assertScreenShows(rest, "save", "the last field's SELECT saves rather than advancing");

        // Back on the settings list, asserted as the absence of the editor.
        // The menu is scrolled to its ninth row, so its "Settings" title is
        // off the top of the screen - the first version of this asserted the
        // title and read back the rows it had returned to: "Custom: 5x
        // 2:00/2:00 ... Cues: every ... ace: 8.8 lb". Every field of the
        // editor offers a SELECT that says "next" or "save", and no settings
        // row does.
        await sim.press("select");
        assertScreenLacks(await sim.readText(), "save", "saving should leave the editor");

        // Reopened, the editor reads the stored preset back. Stepping to the
        // work duration and finding the same pixels proves the save landed and
        // that every adjustment above was undone before it did.
        await sim.press("select");
        await sim.press("select");
        assert.ok(
            !screensDiffer(await sim.screenshot(), work),
            "the saved preset should be the one this test started with",
        );

        // retreat() twice: out of a middle field, then out of the first, which
        // is the branch that closes the editor.
        await sim.press("back");
        await sim.press("back");
        const closed = await sim.readText();
        assertScreenLacks(closed, "next", "BACK from the first field should close the editor");
        assert.ok(closed.join(" ").length > 0, "the settings list should still be readable");
    });
});
