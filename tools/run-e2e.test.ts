// The suite-splitting maths. Everything else in run-e2e.ts needs a
// simulator; this does not, and it decides which files a CI job runs, so a
// mistake here silently stops testing something rather than going red.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { shardOf } from "./e2e/run-e2e.ts";

const FILES = [
    "discard-confirmation.e2e.test.ts",
    "equipment-picker.e2e.test.ts",
    "movement-picker.e2e.test.ts",
    "rest-screen.e2e.test.ts",
    "workout-summary.e2e.test.ts",
    "full/rest-options-menu.e2e.test.ts",
    "full/settings-menu.e2e.test.ts",
];

void describe("shardOf", () => {
    it("runs everything when the suite is not split", () => {
        assert.deepEqual(shardOf(FILES, 1, 1), FILES);
    });

    it("covers every file exactly once across the shards", () => {
        // The property that matters. An off-by-one here does not fail a
        // build, it quietly stops running a test.
        const one = shardOf(FILES, 1, 2);
        const two = shardOf(FILES, 2, 2);
        assert.deepEqual([...one, ...two].sort(), [...FILES].sort());
        assert.equal(one.length + two.length, FILES.length);
    });

    it("splits the work rather than front-loading one job", () => {
        // Interleaved, not halved: the slowest files are not evenly spread
        // through the list, and the wall clock is whichever shard is longer.
        assert.equal(Math.abs(shardOf(FILES, 1, 2).length - shardOf(FILES, 2, 2).length) <= 1, true);
    });

    it("holds for more shards than files", () => {
        const parts = [1, 2, 3, 4, 5, 6, 7, 8].map((n) => shardOf(FILES, n, 8));
        assert.deepEqual(parts.flat().sort(), [...FILES].sort());
        assert.deepEqual(parts[7], []);
    });
});
