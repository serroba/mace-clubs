// Saving an implement weight on a reduced build.
//
// The counterpart of ../full/weight-editor.e2e.test.ts, and here for a
// narrower reason than that one: the editor is pushed on top of the settings
// menu, so it is the most memory the app ever has in play at once on a 96KB
// watch. Its save used to die the same way every other settings write did -
// see ./settings-write.e2e.test.ts for the crash and what actually caused it.
//
// "Mace weight" is one of the seven rows those devices keep, so this path is
// reachable there and has to be known to work rather than assumed to. It is
// five presses down, not nine: the rows above it that a full build shows -
// corner, cue, the history browser and the custom-workout editor - are all
// compiled out here.
//
// Asserts the app is still alive and back on its own idle screen afterwards.
// Not the saved figure: WeightEditorView draws it in FONT_NUMBER_MEDIUM, and
// on a 163x156 Instinct 2S the menu rows behind it come back from OCR as
// nothing at all. The full suite checks the arithmetic on a screen that can
// be read; what matters here is that the save does not take the app down.

import { isGestureDriven } from "../device-profile.ts";
import { after, before, describe, it } from "node:test";

import { assertScreenShows } from "../ocr-match.ts";
import { openSettingsMenu } from "../open-menu.ts";
import { deviceProfile, Simulator } from "../simulator.ts";

/** Mode, Rep target, Wrist, Movement, Side, then Mace weight. */
const DOWN_PRESSES_TO_MACE_WEIGHT = 5;

void describe("Weight editor (reduced build)", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("saves without taking the app down", async (t) => {
        if (isGestureDriven(deviceProfile())) {
            t.skip("menu rows cannot be selected by counted presses on a gesture-driven device");
            return;
        }

        await openSettingsMenu(sim);
        // First press through pressUntilChanged: a just-opened Menu2 swallows
        // one, and a swallowed press here lands the count on the wrong row.
        await sim.pressUntilChanged("down");
        for (let step = 1; step < DOWN_PRESSES_TO_MACE_WEIGHT; step += 1) {
            await sim.press("down");
        }
        await sim.press("select");
        await sim.waitForStable();

        // +0.5 and save, which is the write that used to crash.
        await sim.press("up");
        await sim.press("select");
        await sim.waitForStable();

        // Put it back, so the run leaves no state behind for the next one.
        await sim.pressUntilChanged("down");
        for (let step = 1; step < DOWN_PRESSES_TO_MACE_WEIGHT; step += 1) {
            await sim.press("down");
        }
        await sim.press("select");
        await sim.waitForStable();
        await sim.press("down");
        await sim.press("select");
        await sim.waitForStable();

        await sim.press("back");
        await sim.waitForStable();
        const idle = (await sim.readText()).join(" ");
        console.log(`idle after save: ${idle}`);
        assertScreenShows(idle, "MENU opens settings");
    });
});
