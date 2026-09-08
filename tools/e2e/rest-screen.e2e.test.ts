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
        // Established by watching it rather than by reading it. Two earlier
        // versions of this test tried to read: one compared row 2 against
        // the countdown, which meant finding the countdown - the largest
        // text on the screen, and the first thing the OCR drops on several
        // watches - and locating it by its position relative to the
        // "SELECT: work" label, which the Instinct Crossover reads as
        // "= ork". The other matched the clock's shape, since
        // MaceClubsView.clockTimeLabel always emits an am/pm suffix that
        // formatSecs never does; the Instinct 2 read that suffix as
        // "REST 11:25\m".
        //
        // What cannot be garbled is behaviour. A countdown advances every
        // second; a wall clock changes at most once a minute. Sampling row 2
        // three times a few seconds apart tells the two apart without
        // needing to read either one correctly - only consistently.
        const samples = [
            await readRestRowTime(sim),
            await readRestRowTime(sim, 3000),
            await readRestRowTime(sim, 3000),
        ];
        assert.ok(
            samples.every((sample) => sample !== undefined),
            `expected a time on the "REST" row in all three samples: ${JSON.stringify(samples)}`,
        );
        const ticks = (samples[0] === samples[1] ? 0 : 1) + (samples[1] === samples[2] ? 0 : 1);
        assert.ok(
            ticks < 2,
            `row 2 advances like the countdown rather than a clock: ${samples.join(" -> ")} - ` +
                "the wall clock fix has regressed",
        );
    });
});

/**
 * The time-shaped value on the "REST" row, after an optional wait.
 *
 * Retried, because OCR is probabilistic and this is small text: a single
 * read returned "REST distin" on an Instinct 2 whose screen was fine, and a
 * test that reports a shipped bug has returned on the strength of one bad
 * read is worse than one that takes another look. Only the digits are
 * returned, so a garbled suffix ("11:25\m") does not count as a change.
 */
async function readRestRowTime(sim: Simulator, waitMs = 0): Promise<string | undefined> {
    if (waitMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, waitMs));
    }
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
