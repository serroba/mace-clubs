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

        const lines = await sim.readText();
        const timePattern = /\d{1,2}:\d{2}/;

        // OCR's exact grouping of "REST" and its time varies run to run
        // (sometimes one string, sometimes split across array entries), so
        // this locates values by stable landmarks and reading order instead
        // of assuming a fixed string shape.
        const restIndex = lines.findIndex((line) => line.includes("REST"));
        assert.ok(restIndex !== -1, `expected "REST" on screen: ${JSON.stringify(lines)}`);

        const selectWorkIndex = lines.findIndex((line) => line.includes("SELECT: work"));
        assert.ok(selectWorkIndex !== -1, `expected the "SELECT: work" label: ${JSON.stringify(lines)}`);

        // The big centered countdown is whatever time-shaped value sits
        // directly before the "SELECT: work" label.
        const countdownTime = timePattern.exec(lines[selectWorkIndex - 1] ?? "")?.[0];
        assert.ok(countdownTime !== undefined, `expected a countdown value before "SELECT: work": ${JSON.stringify(lines)}`);

        // Row 2's wall clock is the first time-shaped value at or after the
        // "REST" label (and before the countdown).
        let restTime: string | undefined;
        for (let i = restIndex; i < selectWorkIndex; i += 1) {
            const match = timePattern.exec(lines[i] ?? "");
            if (match !== null) {
                restTime = match[0];
                break;
            }
        }
        assert.ok(restTime !== undefined, `expected a time value at/after "REST": ${JSON.stringify(lines)}`);

        // The regression this guards against: row 2 and the big centered
        // value both showing the identical countdown (the bug PR #125
        // fixed). They must now differ - row 2 is the wall clock.
        assert.notEqual(
            restTime,
            countdownTime,
            `row 2 and the countdown show the same value (${countdownTime}) - ` +
                `the wall clock fix has regressed: ${JSON.stringify(lines)}`,
        );
    });
});
