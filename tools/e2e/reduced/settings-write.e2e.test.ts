// Changing a setting on a reduced build, which used to kill the app.
//
// Every row of the settings menu crashed these five watches:
//
//     Error: Out Of Memory Error
//     Stack: onSelect() at source/ui/SettingsMenuDelegate.mc:48
//
// Measured against main on instinct2 and descentg1, at three separate rows
// and three separate lines - so it was never one row misbehaving, it was
// anything that wrote.
//
// The write looked like the culprit and was not. Deferring it past the menu
// only moved the crash into whatever allocated next: Layout.fitCentredLine
// once, then patternLabel three times running, in code that has nothing to do
// with settings. What did not fit was the menu. Twenty Menu2 rows cost about
// 5.2KB of the 9KB these devices have, leaving 3,968 bytes for the app to
// keep running in. Carrying seven leaves 8,696 - see SettingsMenu.addExtraItems
// and tools/memory-baselines.json.
//
// Nothing caught it because ./settings-menu.e2e.test.ts opens the menu and
// reads it without pressing a row - its own comment says it asserts "nothing
// about the rows that remain". The full suite presses these rows constantly,
// on watches with 128KB, where it has always worked.
//
// So this presses one and then leaves, because the leaving is where the app
// used to die, and asserts on the idle screen rather than on the row.

import { isGestureDriven } from "../device-profile.ts";
import { after, before, describe, it } from "node:test";

import { assertScreenShows } from "../ocr-match.ts";
import { openSettingsMenu } from "../open-menu.ts";
import { deviceProfile, Simulator } from "../simulator.ts";

void describe("Changing a setting (reduced build)", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("survives the write, and the write that follows it out", async (t) => {
        if (isGestureDriven(deviceProfile())) {
            t.skip("menu rows cannot be selected by counted presses on a gesture-driven device");
            return;
        }

        // Mode is the first row here: these devices ship without the history
        // browser. A just-opened Menu2 swallows the first press, so the select
        // itself is the press that waits for a change.
        await openSettingsMenu(sim);
        await sim.pressUntilChanged("select");
        await sim.waitForStable();

        // Out of the menu, and assert on the idle screen rather than on the
        // row that was changed.
        //
        // Not squeamishness about OCR for its own sake: an Instinct 2S is
        // 163x156 where the rest of the family is 176x176, and its menu rows
        // come back from OCR as nothing at all - a run that had "Mode: reps"
        // plainly on screen read it as ["Settings \u00bb"]. The idle screen
        // draws in far larger type, and it is the better assertion anyway:
        // "target 50 swings" there means the value was written, read back and
        // applied, where the menu label only means a label changed.
        //
        // A crash at either step reads as the watch face, which has neither.
        await sim.press("back");
        await sim.waitForStable();
        const idle = (await sim.readText()).join(" ");
        console.log(`idle after write: ${idle}`);
        // "target 50 swings" is the setting having been written, read back and
        // applied. On a hybrid the hands can be lying across that very line -
        // the Crossover drew it correctly and OCR saw nothing but the rows
        // above and below - so there the weaker claim is the honest one: the
        // app is alive and on its own idle screen rather than the watch face,
        // which is what a crash looks like. The screenshot that settled it is
        // in the commit message.
        assertScreenShows(idle, deviceProfile().analogHands ? "MENU opens settings" : "target");
    });
});
