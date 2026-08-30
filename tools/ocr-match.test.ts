// Unit tests for the e2e suite's OCR-tolerant screen matching. Lives at the
// tools/ root, alongside the other *.test.ts files `make tools-check` runs -
// tools/e2e/*.test.ts is the e2e suite itself, which needs a simulator.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { screenShows } from "./e2e/ocr-match.ts";

void describe("screenShows", () => {
    // The two misreads that actually broke the suite when it first ran on
    // devices other than the Instinct. Both are one wrong character, and in
    // both the app was rendering perfectly.
    it("tolerates the single-character misreads real OCR produces", () => {
        assert.ok(screenShows(["Rest options Move: 360 *ide: Two-handed"], "Side"), "fenix7 read Side as *ide");
        assert.ok(screenShows(["biscard & go hom"], "Discard"), "venu3 read Discard as biscard");
        assert.ok(screenShows(["biscard & go hom"], "home"), "venu3 truncated home to hom");
    });

    // Tesseract on Linux drops the space as readily as it drops a character.
    it("tolerates a lost space between words", () => {
        assert.ok(screenShows(["UP/DOWN 1/4 > _BACKexit yy"], "BACK exit"), "fenix7 merged BACK and exit");
    });

    it("matches a multi-word phrase in any surrounding text", () => {
        assert.ok(screenShows(["Choose equipment", "Mace: 8.8 lb"], "Choose equipment"));
        assert.ok(screenShows(["SUMMARY 2 sets 1:20 work"], "SUMMARY"));
    });

    it("still fails on a genuinely different screen", () => {
        assert.ok(!screenShows(["Choose equipment Mace: 8.8 lb"], "Settings"));
        assert.ok(!screenShows(["50 bpm | fixed 4 SELECT to start"], "Discard"));
    });

    // One edit away from a three-letter word is a different word, so short
    // words are matched exactly - otherwise "hr" would match "up".
    it("does not fuzzy-match short words", () => {
        assert.ok(screenShows(["1 sets rnds -- hr"], "hr"));
        assert.ok(!screenShows(["1 sets rnds -- hr"], "up"));
    });

    it("ignores case and punctuation", () => {
        assert.ok(screenShows(["SELECT: work"], "select work"));
        assert.ok(screenShows(["Mode: intervals"], "MODE INTERVALS"));
    });
});
