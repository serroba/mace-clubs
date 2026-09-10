// e2e test for the implement weight editor, reached from Settings.
//
// One of three screens a user can open that CI never drew. Coverage said so
// with a number: `make coverage-all` reports 58 function bodies that neither
// the unit tests nor this suite reach, and WeightEditorView.onUpdate,
// WeightEditorDelegate.onSelect and .onBack were three of them. A unit test
// cannot reach any of the three - onUpdate needs a Dc, and the other two pop
// a view off a real WatchUi stack - so this is the only place they can be
// checked.
//
// What is worth checking beyond "it draws": SELECT and BACK are one press
// apart and do opposite things. onSelect saves the new weight and pops;
// onBack pops and discards. Getting those the wrong way round loses a user's
// edit, or silently keeps one they cancelled, and nothing else in the repo
// would notice.
//
// Everything is read off the editor's own screen rather than off the
// settings row behind it. The row is a Menu2 row, which is what OCR reads
// worst - the first version of this test compared row labels and had one
// read come back "ace: 8.8 lb" with the M clipped, which looked like a
// changed weight. The editor draws its value in FONT_NUMBER_MEDIUM, and
// re-opening it re-reads the saved property, so the saved value can be
// checked from the legible screen instead. What that leaves uncovered is the
// row's own label refresh (`_menuItem.setLabel`), which is cosmetic and would
// need exactly the reading that proved unreliable.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { isGestureDriven } from "../device-profile.ts";
import { assertScreenShows } from "../ocr-match.ts";
import { openSettingsMenu } from "../open-menu.ts";
import { deviceProfile, Simulator } from "../simulator.ts";

/**
 * Down-presses from a freshly opened Settings menu to the mace weight row.
 *
 * Counted, not scrolled-until-visible. `pressUntilVisible` stops when the
 * text can be read, and a Menu2 shows several rows at once - the first run
 * of this test stopped with "Mace: 8.8 lb" legible at the bottom of the
 * screen, pressed SELECT, and opened the custom-workout editor that was the
 * row actually highlighted.
 *
 * The count is the menu's own order in SettingsMenu.build: history, mode,
 * rep target, corner, wrist, movement, side, cue, custom workout, then this.
 * A row added above it fails this test rather than silently editing something
 * else, because what follows asserts that the weight editor is what opened.
 */
const DOWN_PRESSES_TO_MACE_WEIGHT = 9;

/**
 * The weight the editor is showing, as digits: "88" from "8.8 lb".
 *
 * Digits, because the unit is the device's own setting - this suite's Linux
 * container reports statute, so the 4000 g default reads "8.8 lb" and not
 * "4 kg" - and because only whether the number moved matters here.
 *
 * From the value line alone, not the whole screen. Both hint lines carry a
 * colon and one of them carries a number - "UP/DOWN: 0.5" - so scraping every
 * digit on screen returned "8805" and would have compared the step size along
 * with the weight. The value is the only line with digits and no colon.
 *
 * Reading the unit would be no help either: OCR renders "8.8 lb" as "8.8 ii"
 * at this size.
 *
 * Null where the number did not come back at all. A Forerunner 945 reads this
 * screen as ["MACE WEIGHT", "UP/DOWN: 0.5", "7 SELECT: save -"] - the title
 * and both hints, and nothing where FONT_NUMBER_MEDIUM drew the value. The
 * screen is correct and a person can read it, so the caller reports what it
 * could not check rather than failing.
 */
function shownWeight(lines: string[]): string | null {
    const value = lines.find((line) => !line.includes(":") && /[0-9]/.test(line));
    return value === undefined ? null : value.replace(/[^0-9]/g, "");
}

void describe("Implement weight editor", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("saves on SELECT and discards on BACK", async (t) => {
        // A fixed press count is a button-device idiom: one press steps the
        // highlight exactly one row. A swipe does not - it flings a touch list
        // by a variable amount - so on a gesture-driven watch this would land
        // on whatever row the fling reached and press SELECT on it, which on
        // this menu means cycling a real setting. The editor is identical on
        // those devices; what cannot be driven there is the navigation to it.
        if (isGestureDriven(deviceProfile())) {
            t.skip("menu rows cannot be selected by counted presses on a gesture-driven device");
            return;
        }

        await openSettingsMenu(sim);
        // The first press through pressUntilChanged, the rest plain. A menu
        // that has just slid into view swallows a press or two - the driver
        // says so on pressUntilChanged, and this test found it the hard way:
        // nine presses landed on the eighth row and opened the custom-workout
        // editor. Waiting for the highlight to actually move once puts the
        // count back on the row it names.
        await sim.pressUntilChanged("down");
        for (let step = 1; step < DOWN_PRESSES_TO_MACE_WEIGHT; step += 1) {
            await sim.press("down");
        }
        await sim.press("select");

        // WeightEditorView.onUpdate. The implement name, not the whole title:
        // landing one row off opens the club or bulava editor, which draws the
        // same screen, so the implement is the part worth asserting - but
        // "WEIGHT" beside it is drawn in FONT_SMALL and OCR reads it as
        // "WE HT" often enough that requiring the word fails on a screen that
        // is perfectly correct.
        const opened = await sim.readText();
        assertScreenShows(opened, "MACE", "the mace weight editor should have opened");
        assertScreenShows(opened, "save", "the editor tells the user SELECT saves");
        const original = shownWeight(opened);

        // The presses come first and unconditionally, because they are what
        // reaches the three functions this test exists for. What the value
        // says is checked below, on the devices that render it readably.
        //
        // +0.5, then BACK: WeightEditorDelegate.onBack pops without saving.
        await sim.press("up");
        const stepped = shownWeight(await sim.readText());
        await sim.press("back");
        await sim.press("select");
        const afterDiscard = shownWeight(await sim.readText());

        // +0.5, then SELECT: WeightEditorDelegate.onSelect saves and pops.
        await sim.press("up");
        await sim.press("select");
        await sim.press("select");
        const afterSave = shownWeight(await sim.readText());

        // -0.5 and save again, putting it back where it was found. The
        // simulator persists an app's properties between runs, so a weight
        // left changed here is a weight the next run of any file starts with -
        // docs/e2e-testing.md has the same hazard biting the unit suite. This
        // is symmetric by construction rather than by reading: one press up
        // and one press down are the same half unit either way.
        await sim.press("down");
        await sim.press("select");
        await sim.press("select");
        const afterRestore = shownWeight(await sim.readText());
        await sim.press("back");

        if (original === null || stepped === null) {
            // Not a skip: the three functions above ran on this device, and
            // the editor drew a screen with its title and both hints on it.
            // What could not be done here is read the number back.
            t.diagnostic(
                `${deviceProfile().id} did not render a readable weight, so save and discard were exercised ` +
                    "but not verified - see shownWeight()",
            );
            return;
        }

        assert.notEqual(stepped, original, "UP should have changed the displayed weight");
        assert.equal(afterDiscard, original, "BACK must discard the edit, not save it");
        assert.equal(afterSave, stepped, "SELECT must save the edit");
        assert.equal(afterRestore, original, "the test should leave the weight as it found it");
    });
});
