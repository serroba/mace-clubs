// e2e test for the "Choose movement" screen, reached after accepting the
// default equipment. Static content (mace's movement list doesn't depend
// on wall-clock time or elapsed counters), same pattern as
// equipment-picker.e2e.test.ts - see docs/e2e-testing.md.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { screenShows } from "./ocr-match.ts";

import { expectScreenshotMatches } from "./screen-matcher.ts";
import { Simulator } from "./simulator.ts";

void describe("Choose movement screen", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("lists mace's movement options, defaulting to 360", async () => {
        // Home -> Choose equipment (accept default: Mace).
        await sim.pressUntilChanged("select");
        // Choose equipment -> Choose movement (accept default equipment).
        await sim.pressUntilChanged("select");

        const lines = await sim.readText();
        const joined = lines.join(" ");
        // Either the title or the default movement, because no single one of
        // them is legible on every watch and both are unique to this screen.
        //
        // Menu2 draws the title, and the Instinct Crossover draws none at
        // all, listing straight from the first row. The Forerunners 55 and
        // 945 draw it and then defeat the OCR on the row instead: "360" is
        // the largest thing on those screens, and Tesseract drops glyphs
        // that big rather than misreading them - no upscale or segmentation
        // mode reads it on a 945, and on a 55 only sparse-text mode does.
        //
        // "Choose" rather than the whole title, because a 208px Forerunner
        // 55 wraps it and reads back only "Choose m".
        //
        // Chasing any of this through the OCR is what PR #173 was, and it
        // cost three green devices and 150 lines before being closed. A
        // second attempt with an extra pass per screen doubled the suite's
        // runtime and timed out four jobs. The pixel-exact baseline below is
        // the real regression check for a screen this static; this assertion
        // only has to establish which screen we are on.
        assert.ok(
            screenShows(joined, "Choose") || screenShows(joined, "360"),
            `expected the movement picker's title or its default row: ${JSON.stringify(lines)}`,
        );

        // Before scrolling, so the baseline is the screen as it first
        // appears.
        await expectScreenshotMatches(await sim.screenshot(), "movement-picker");
    });
});
