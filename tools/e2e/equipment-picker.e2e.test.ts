// e2e test for the "Choose equipment" screen. Unlike the rest screen (see
// rest-screen.e2e.test.ts), this screen's content is static - it doesn't
// depend on wall-clock time or elapsed counters - so it's a good fit for a
// screenshot baseline (expectScreenshotMatches()) rather than only an OCR
// content check. Both approaches are demonstrated across these two files;
// see docs/e2e-testing.md for when to reach for which.

import { after, before, describe, it } from "node:test";

import { assertScreenShows } from "./ocr-match.ts";

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
        // The first row, not the "Choose equipment" title: Menu2 draws its
        // own title and does not always draw one - the Instinct Crossover
        // shows this menu with no title band at all, listing straight from
        // the first row. That is the system's layout decision, not something
        // the app asks for or can change.
        assertScreenShows(joined, "Mace");

        // Before scrolling, so the baseline is always the screen as it first
        // appears.
        await expectScreenshotMatches(await sim.screenshot(), "equipment-picker");

        // "lists every equipment option" is the claim, so check the list
        // rather than the first screenful of it. Only two rows fit above the
        // fold on a 163x156 Instinct 2S - asserting "Clubs" outright failed
        // on six of the seven devices in CI, all of them drawing the menu
        // perfectly well.
        await sim.pressUntilVisible("down", "Clubs");
    });
});
