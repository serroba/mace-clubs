// e2e test for the tempo control: UP and DOWN move the metronome while a
// workout runs, and free-training rest takes those same buttons away from it.
//
// The seam this covers. MetronomeTest pins the arithmetic - default 50, steps
// of 5, clamped to 5 and 240 - and NavigationTest pins the routing decision,
// that a started workout returns PREVIOUS_TEMPO_UP. Between those two sits
// MaceClubsDelegate.onPreviousPage, and that is where the exceptions live: the
// isFreeResting() early return runs before Navigation is ever consulted, so
// neither end's unit tests can see it. Nothing proved a physical UP press
// reaches adjustBpm at all, or that the figure the work screen draws moves
// when it does.
//
// Asserted with OCR rather than a screenshot baseline, for the reason
// rest-screen.e2e.test.ts gives: the work screen carries a running clock, so a
// pixel-exact baseline would fail on every run for reasons that have nothing
// to do with a regression.
//
// Why every read here is retried, and why the raised tempo is never named.
// Tesseract does not read this screen reliably at 176px. Driving the sequence
// by hand and screenshotting every step, one run returned "30" for a screen
// plainly showing 55 and "90" for one showing 50 - with a trail of junk
// tokens alongside it, so the whole capture was poor - while a second run of
// the identical sequence read every step correctly. The app was right both
// times; the channel was not.
//
// So two defences, and neither of them loosens what is being asserted. Reads
// are retried, because a value that is genuinely wrong never appears however
// many times it is read, while a mangled capture is gone by the next one. And
// the raised tempo is asserted as "no longer the default" rather than as 55,
// because the default is the one value worth naming: press() has already
// settled, so if 50 is still on screen after UP, the press did not land.
//
// One consequence of naming 50: the elapsed clock must not read 0:50 while
// these run, or that token is on screen for a reason that has nothing to do
// with tempo. Every press here lands within half a minute of the countdown
// ending, well clear of it.

import { after, before, describe, it } from "node:test";

import { screenShows } from "./ocr-match.ts";
import { Simulator } from "./simulator.ts";

/** Metronome.DEFAULT_BPM, which a freshly launched simulator starts at. */
const DEFAULT_BPM = "50";

/** How long the start countdown runs, plus a second. The countdown ticks once
 * a second, so waiting for visual stability can land twice inside one tick - a
 * fixed wait for a known duration is the honest thing here, as it is in
 * rest-screen.e2e.test.ts. UP is ignored for the whole countdown
 * (Navigation.PREVIOUS_IGNORE), so the test has to be past it before a press
 * means anything. */
const COUNTDOWN_MS = 6500;

/** Home to a running WORK screen, accepting both pickers' defaults: Mace, and
 * the 360. The default preset is Free training (Presets.LIST[0]), which is
 * what makes the rest excursion below reachable with no preset cycling. */
async function startWorking(sim: Simulator): Promise<void> {
    await sim.pressUntilChanged("select");
    await sim.press("select");
    await sim.press("select");
    await new Promise((resolve) => setTimeout(resolve, COUNTDOWN_MS));
}

/** How many captures a single assertion is allowed. Four is comfortably more
 * than the one bad capture seen in practice, and still fails fast when the
 * app is genuinely showing something else. */
const READ_ATTEMPTS = 4;

async function readUntil(
    sim: Simulator,
    wanted: boolean,
    phrase: string,
    context: string,
): Promise<void> {
    let last: string[] = [];
    for (let attempt = 0; attempt < READ_ATTEMPTS; attempt++) {
        last = await sim.readText();
        if (screenShows(last, phrase) === wanted) {
            return;
        }
    }
    const expectation = wanted ? `expected "${phrase}"` : `expected no "${phrase}"`;
    throw new Error(
        `${expectation} on screen after ${String(READ_ATTEMPTS)} reads (${context}), ` +
            `last read: ${JSON.stringify(last.join(" "))}`,
    );
}

void describe("Tempo control", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
        await startWorking(sim);
    });

    after(() => {
        sim.close();
    });

    // Both cases share one running workout on purpose. A file costs a fresh
    // simulator - about thirty seconds before a single assertion runs - and
    // the second needs exactly the state the first leaves behind, which is the
    // tempo back at its default.
    it("moves the tempo off its default on UP and back on DOWN", async () => {
        await readUntil(sim, true, DEFAULT_BPM, "a fresh workout starts at the default tempo");

        await sim.press("up");
        await readUntil(sim, false, DEFAULT_BPM, "UP should have moved the tempo off 50");

        await sim.press("down");
        await readUntil(sim, true, DEFAULT_BPM, "DOWN should put it back");
    });

    it("leaves the tempo alone while free training is resting", async () => {
        // SELECT ends the set and enters REST, where MaceClubsView repurposes
        // UP and DOWN to page extra info - tempo is meaningless with the
        // metronome stopped.
        await sim.press("select");
        await sim.press("up");

        // Proof the press was delivered and went where it was supposed to,
        // rather than being swallowed: page 2 of the rest screen replaces the
        // phase line and main value with the last set's rhythm and load.
        // Without this the case below would pass just as well on a press that
        // never arrived.
        await readUntil(sim, true, "load", "UP should have paged the rest screen");

        await sim.press("up");
        await sim.press("select");
        await readUntil(sim, true, DEFAULT_BPM, "paging the rest screen must not have touched the tempo");
    });
});
