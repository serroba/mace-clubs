// e2e test for the one thing the paused screen must never stop saying: that
// you can leave without saving.
//
// The screen offers three ways out - save, resume, and discard - and discard
// is the only one a wearer cannot guess, because it is a held MENU or a tap
// on a hint rather than a labelled button. It used to lose its line to the
// paging hint whenever the session had more than one set, which is exactly
// when there is most to lose and most reason to want out. This is here so
// that trade cannot be made again by accident.
//
// Asserted by OCR rather than a screenshot baseline: the paused screen
// carries the elapsed totals of a real session, so a pixel-exact baseline
// would fail on every run for reasons that have nothing to do with the hint.

import { after, before, describe, it } from "node:test";

import { screenShows } from "./ocr-match.ts";
import { Simulator } from "./simulator.ts";

/** How long the start countdown runs, plus a second - see
 * rest-screen.e2e.test.ts on why a known duration is a plain sleep. */
const COUNTDOWN_MS = 6500;

/** Captures allowed per assertion. These hints are FONT_XTINY on a 176px
 * screen, which is the size Tesseract reads worst; docs/e2e-testing.md's
 * flakiness section has the evidence. A word that is genuinely absent never
 * appears however many times the screen is read, while a mangled capture is
 * gone by the next one. */
const READ_ATTEMPTS = 4;

async function readUntil(sim: Simulator, phrase: string, context: string): Promise<void> {
    let last: string[] = [];
    for (let attempt = 0; attempt < READ_ATTEMPTS; attempt++) {
        last = await sim.readText();
        if (screenShows(last, phrase)) {
            return;
        }
    }
    throw new Error(
        `expected "${phrase}" on the paused screen after ${String(READ_ATTEMPTS)} reads ` +
            `(${context}), last read: ${JSON.stringify(last.join(" "))}`,
    );
}

void describe("Paused screen", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
        // Home -> equipment -> movement, accepting both defaults, then the
        // countdown into WORK.
        await sim.pressUntilChanged("select");
        await sim.press("select");
        await sim.press("select");
        await new Promise((resolve) => setTimeout(resolve, COUNTDOWN_MS));
        // WORK -> PAUSED.
        await sim.press("back");
    });

    after(() => {
        sim.close();
    });

    it("offers leaving without saving, alongside save and resume", async () => {
        // The word, not the gesture in front of it: that gesture is "MENU" on
        // a watch with a MENU key, "TAP" on a touch watch without one and
        // "HOLD UP" on the rest, and which one appears is DeviceInput's
        // business rather than this test's.
        await readUntil(sim, "discard", "the paused screen must always name the way out");
        await readUntil(sim, "save", "and it still offers to save");
        await readUntil(sim, "resume", "and to resume - a paused workout is not finished");
    });
});
