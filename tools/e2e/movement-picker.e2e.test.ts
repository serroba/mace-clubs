// e2e test for the "Choose movement" screen, reached after accepting the
// default equipment. Static content (mace's movement list doesn't depend
// on wall-clock time or elapsed counters), same pattern as
// equipment-picker.e2e.test.ts - see docs/e2e-testing.md.

import { after, before, describe, it } from "node:test";

import { assertScreenShows } from "./ocr-match.ts";

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
        assertScreenShows(joined, "Choose");
        assertScreenShows(joined, "movement");
        assertScreenShows(joined, "360");

        await expectScreenshotMatches(await sim.screenshot(), "movement-picker");
    });
});
