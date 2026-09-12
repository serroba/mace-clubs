// e2e test for the free-training rest screen (PR #125): row 2 should show
// "REST <wall clock>", not a duplicate of the big countdown already shown
// below it. See docs/e2e-testing.md for how this framework works and how
// to add another test like this one.
//
// This screen is asserted with OCR (readText()), not a screenshot baseline
// (expectScreenshotMatches()) - it has genuinely dynamic content (the wall
// clock, the countdown, the elapsed timer), so a pixel-exact baseline would
// fail on every run for reasons that have nothing to do with a regression.
// Save screenshot baselines for screens whose content is actually static
// (e.g. the equipment picker's fixed menu text).
//
// Run with: npm run test:e2e --prefix tools (macOS only - see the doc).

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { Simulator } from "./simulator.ts";

void describe("Free training rest screen", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("shows the wall clock on row 2, not a duplicate of the countdown", async () => {
        // Home -> Choose equipment (accept default: Mace).
        await sim.pressUntilChanged("select");
        // Choose equipment -> Choose movement (accept default: 360).
        await sim.press("select");
        // Choose movement -> "GET READY" 5s countdown.
        await sim.press("select");
        // The countdown ticks once a second; waiting for visual stability
        // isn't reliable here since a poll can land twice within the same
        // tick, so a fixed sleep for this *known* duration is more honest
        // than waitForStable() would be.
        await new Promise((resolve) => setTimeout(resolve, 6500));

        // Now in WORK phase; SELECT moves free training into REST.
        await sim.press("select");

        // Row 2 is "REST <wall clock>", and the regression this guards is
        // row 2 showing a duplicate of the big countdown instead - the bug
        // PR #125 fixed.
        //
        // Told apart by the hour, which needs one reading of one row and no
        // assumption about anything else on the screen. clockTimeLabel emits
        // a 12-hour time whose hour is 1 to 12 - never 0, since it maps 0 to
        // 12 - while the rest countdown is formatSecs, minutes and seconds,
        // and has just started: it reads 0:00 and stays there for a minute.
        // So a row 2 beginning "0:" is the countdown and nothing else.
        //
        // Three earlier versions of this reached for something harder.
        // Comparing row 2 against the countdown meant finding the countdown,
        // the largest text on the screen and the first thing the OCR drops,
        // located by its position beside the "SELECT: work" label, which the
        // Instinct Crossover reads as "= ork". Matching the am/pm suffix
        // failed on an Instinct 2 reading "REST 11:25\m". Sampling the row
        // to watch it tick assumed the samples were seconds apart, and
        // readText runs four OCR passes: on a Forerunner 945 they were two
        // minutes apart and the clock had genuinely advanced, 12:19 to 12:20
        // to 12:21, which the test duly reported as a countdown.
        const restTime = await readRestRowTime(sim);
        assert.ok(
            restTime !== undefined,
            `expected a time on the "REST" row: ${JSON.stringify(await sim.readText())}`,
        );
        assert.notEqual(
            restTime.split(":")[0],
            "0",
            `row 2 reads "${restTime}", which is the countdown rather than the wall clock - ` +
                "the fix from PR #125 has regressed",
        );
    });
});

/**
 * The time-shaped value on the "REST" row.
 *
 * Retried, because OCR is probabilistic and this is small text: a single
 * read returned "REST distin" on an Instinct 2 whose screen was fine, and a
 * test that reports a shipped bug has returned on the strength of one bad
 * read is worse than one that takes another look. Only the digits are
 * matched, so a mangled suffix ("11:25\m") still reads.
 */
async function readRestRowTime(sim: Simulator): Promise<string | undefined> {
    for (let attempt = 0; attempt < 4; attempt += 1) {
        const restRow = (await sim.readText()).find((line) => line.includes("REST"));
        const match = restRow === undefined ? null : /\d{1,2}:\d{2}/.exec(restRow);
        if (match !== null) {
            return match[0];
        }
        await new Promise((resolve) => setTimeout(resolve, 800));
    }
    return undefined;
}
