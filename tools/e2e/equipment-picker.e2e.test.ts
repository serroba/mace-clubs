// e2e test for the "Choose equipment" screen. Unlike the rest screen (see
// rest-screen.e2e.test.ts), this screen's content is static - it doesn't
// depend on wall-clock time or elapsed counters - so it's a good fit for a
// screenshot baseline (expectScreenshotMatches()) rather than only an OCR
// content check. Both approaches are demonstrated across these two files;
// see docs/e2e-testing.md for when to reach for which.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { expectScreenshotMatches } from "./screen-matcher.ts";
import { Simulator } from "./simulator.ts";

void describe("Choose equipment screen", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("lists every equipment option, defaulting to Mace", async () => {
        await sim.pressUntilChanged("select");

        const lines = await sim.readText();
        const joined = lines.join(" ");
        assert.match(joined, /Choose/i);
        assert.match(joined, /equipment/i);
        assert.match(joined, /Mace/i);

        await expectScreenshotMatches(await sim.screenshot(), "equipment-picker");
    });
});
