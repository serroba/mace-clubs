#!/usr/bin/env node
// Scores SwingCounter's mace constants against every recording in
// tools/fixtures/ - a repeatable check for whether tuning is getting better
// or worse as more real recordings come in, instead of hand-rolling a new
// one-off script each time (this replaces the throwaway script used to
// derive SwingCounter.MACE_HIGH_MG=1700 in the first place).
//
// Usage:
//     node --experimental-strip-types tools/tune-swing-counter.ts
//
// To add a fixture: drop the FIT file in tools/fixtures/ and add an entry
// to tools/fixtures/index.json with realSwingsPerSet - the ground truth
// per work set, which nothing in the FIT file itself can tell you. This
// only scores mace fixtures; SwingCounter's shared defaultCounter() (clubs/
// bulava) has no real recordings to check against yet.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { readFit } from "./fit-io.ts";
import { collect } from "./report-fit.ts";
import { computeOrigin, extractAccel, replayCounter } from "./replay-swing.ts";

// Mirrors SwingCounter.mc's mace constants - keep these in sync with that
// file, same caveat as replay-swing.ts's copy.
const MACE_HIGH_MG = 1700;
const MACE_LOW_MG = 1300;
const MACE_MIN_GAP_SAMPLES = 63;
const MACE_DEBOUNCE_SAMPLES = 4;

const FIXTURES_DIR = fileURLToPath(new URL("fixtures", import.meta.url));

interface Fixture {
    id: string;
    file: string;
    equipment: string;
    realSwingsPerSet: number[];
}

interface FixtureIndex {
    fixtures: Fixture[];
}

function countIn(events: readonly number[], start: number, end: number): number {
    return events.filter((t) => t >= start && t <= end).length;
}

interface FixtureScore {
    perSet: number[];
    absError: number;
    restFalsePositives: number;
}

function scoreFixture(fixture: Fixture): FixtureScore {
    const fit = readFit(readFileSync(join(FIXTURES_DIR, fixture.file)));
    const report = collect(fit);
    const origin = computeOrigin(fit);
    const accel = extractAccel(fit, origin);
    const { counted } = replayCounter(accel, MACE_HIGH_MG, MACE_LOW_MG, MACE_MIN_GAP_SAMPLES, MACE_DEBOUNCE_SAMPLES);
    const workLaps = report.laps.filter((lap) => lap.phase === "work" && (lap.set ?? 0) > 0);
    const perSet = workLaps.map((lap) => countIn(counted, lap.start ?? 0, lap.end ?? 0));
    const restLaps = report.laps.filter((lap) => lap.phase === "rest");
    const restFalsePositives = restLaps.reduce((sum, lap) => sum + countIn(counted, lap.start ?? 0, lap.end ?? 0), 0);
    const absError = perSet.reduce(
        (sum, detected, i) => sum + Math.abs(detected - (fixture.realSwingsPerSet[i] ?? 0)),
        0,
    );
    return { perSet, absError, restFalsePositives };
}

export function main(): number {
    const index = JSON.parse(readFileSync(join(FIXTURES_DIR, "index.json"), "utf8")) as FixtureIndex;
    const maceFixtures = index.fixtures.filter((fixture) => fixture.equipment === "mace");
    if (maceFixtures.length === 0) {
        console.error("no mace fixtures found in tools/fixtures/index.json");
        return 1;
    }
    let totalAbsError = 0;
    let totalRestFalsePositives = 0;
    for (const fixture of maceFixtures) {
        const result = scoreFixture(fixture);
        totalAbsError += result.absError;
        totalRestFalsePositives += result.restFalsePositives;
        console.log(
            `${fixture.id}: detected=[${result.perSet.join(",")}] real=[${fixture.realSwingsPerSet.join(",")}] `
            + `absError=${result.absError.toString()} restFalsePositives=${result.restFalsePositives.toString()}`,
        );
    }
    console.log(
        `\nMACE_HIGH_MG=${MACE_HIGH_MG.toString()} across ${maceFixtures.length.toString()} fixtures: `
        + `total absError=${totalAbsError.toString()} total restFalsePositives=${totalRestFalsePositives.toString()}`,
    );
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
