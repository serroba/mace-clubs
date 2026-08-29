#!/usr/bin/env node
// Scores accelerometer, gyroscope, and conservative fused swing candidates
// against every labelled mace recording in tools/fixtures/.
//
// The gyro sweep is intentionally offline research: raw exported axes are
// decimated, so its smoothing window is half the production 25Hz width. The
// detector itself is causal and mirrors the watch's delayed local-maximum
// confirmation plus refractory interval.
//
// Usage:
//     node --experimental-strip-types tools/tune-swing-counter.ts
//
// Add recordings to tools/fixtures/index.json only when per-work-set ground
// truth is known independently of the FIT file.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { detectStreamingGyroPeaks, type GyroPeakOptions } from "./gyro-swing.ts";
import { readFit } from "./fit-io.ts";
import { collect, type FullReport } from "./report-fit.ts";
import { computeOrigin, extractAccel, extractGyro, replayCounter } from "./replay-swing.ts";

const MACE_HIGH_MG = 1700;
const MACE_LOW_MG = 1300;
const MACE_MIN_GAP_SAMPLES = 63;
const MACE_DEBOUNCE_SAMPLES = 4;

const GYRO_SMOOTHING_SAMPLES = [3, 5, 7, 9, 11];
const GYRO_MIN_GAP_SECONDS = [1, 1.5, 2, 2.5, 3];
const GYRO_THRESHOLD_MIN_DPS = 120;
const GYRO_THRESHOLD_MAX_DPS = 320;
const GYRO_THRESHOLD_STEP_DPS = 10;
const FUSION_MATCH_SECONDS = 0.75;

const FIXTURES_DIR = fileURLToPath(new URL("fixtures", import.meta.url));

interface Fixture {
    readonly id: string;
    readonly file: string;
    readonly equipment: string;
    readonly realSwingsPerSet: number[];
}

interface FixtureIndex {
    readonly fixtures: Fixture[];
}

interface LoadedFixture {
    readonly fixture: Fixture;
    readonly report: FullReport;
    readonly accelEvents: number[];
    readonly gyro: ReturnType<typeof extractGyro>;
}

interface EventScore {
    readonly perSet: number[];
    readonly absError: number;
    readonly restFalsePositives: number;
}

interface CandidateScore {
    readonly options: GyroPeakOptions;
    readonly gyroAbsError: number;
    readonly gyroRestFalsePositives: number;
    readonly fusedAbsError: number;
    readonly fusedRestFalsePositives: number;
}

function countIn(events: readonly number[], start: number, end: number): number {
    return events.filter((time) => time >= start && time <= end).length;
}

function scoreEvents(loaded: LoadedFixture, events: readonly number[]): EventScore {
    const workLaps = loaded.report.laps.filter((lap) => lap.phase === "work" && (lap.set ?? 0) > 0);
    const perSet = workLaps.map((lap) => countIn(events, lap.start ?? 0, lap.end ?? 0));
    const restLaps = loaded.report.laps.filter((lap) => lap.phase === "rest");
    const restFalsePositives = restLaps.reduce(
        (sum, lap) => sum + countIn(events, lap.start ?? 0, lap.end ?? 0),
        0,
    );
    const absError = perSet.reduce(
        (sum, detected, index) => sum
            + Math.abs(detected - (loaded.fixture.realSwingsPerSet[index] ?? 0)),
        0,
    );
    return { perSet, absError, restFalsePositives };
}

// Gyro is primary. Add only acceleration events that are not already explained
// by a nearby rotational peak, so fusion can recover a gyro miss without
// reinstating the accelerometer-only failure mode.
function fusedEvents(rotationEvents: readonly number[], accelEvents: readonly number[]): number[] {
    const fused = [...rotationEvents];
    for (const accel of accelEvents) {
        if (fused.every((gyro) => Math.abs(gyro - accel) > FUSION_MATCH_SECONDS)) {
            fused.push(accel);
        }
    }
    fused.sort((a, b) => a - b);
    return fused;
}

function loadFixture(fixture: Fixture): LoadedFixture {
    const fit = readFit(readFileSync(join(FIXTURES_DIR, fixture.file)));
    const report = collect(fit);
    const origin = computeOrigin(fit);
    const accel = extractAccel(fit, origin);
    const { counted } = replayCounter(
        accel,
        MACE_HIGH_MG,
        MACE_LOW_MG,
        MACE_MIN_GAP_SAMPLES,
        MACE_DEBOUNCE_SAMPLES,
    );
    return { fixture, report, accelEvents: counted, gyro: extractGyro(fit, origin) };
}

function gyroEvents(loaded: LoadedFixture, options: GyroPeakOptions): number[] {
    return detectStreamingGyroPeaks(loaded.gyro, options).map((peak) => peak.t);
}

function optionGrid(): GyroPeakOptions[] {
    const options: GyroPeakOptions[] = [];
    for (const smoothingSamples of GYRO_SMOOTHING_SAMPLES) {
        for (let thresholdDps = GYRO_THRESHOLD_MIN_DPS;
            thresholdDps <= GYRO_THRESHOLD_MAX_DPS;
            thresholdDps += GYRO_THRESHOLD_STEP_DPS) {
            for (const minGapSeconds of GYRO_MIN_GAP_SECONDS) {
                options.push({ smoothingSamples, thresholdDps, minGapSeconds });
            }
        }
    }
    return options;
}

function scoreCandidate(fixtures: readonly LoadedFixture[], options: GyroPeakOptions): CandidateScore {
    let gyroAbsError = 0;
    let gyroRestFalsePositives = 0;
    let fusedAbsError = 0;
    let fusedRestFalsePositives = 0;
    for (const loaded of fixtures) {
        const gyro = gyroEvents(loaded, options);
        const gyroScore = scoreEvents(loaded, gyro);
        const fusedScore = scoreEvents(loaded, fusedEvents(gyro, loaded.accelEvents));
        gyroAbsError += gyroScore.absError;
        gyroRestFalsePositives += gyroScore.restFalsePositives;
        fusedAbsError += fusedScore.absError;
        fusedRestFalsePositives += fusedScore.restFalsePositives;
    }
    return {
        options,
        gyroAbsError,
        gyroRestFalsePositives,
        fusedAbsError,
        fusedRestFalsePositives,
    };
}

function betterGyro(a: CandidateScore, b: CandidateScore): number {
    const comparisons = [
        a.gyroAbsError - b.gyroAbsError,
        a.gyroRestFalsePositives - b.gyroRestFalsePositives,
        a.options.smoothingSamples - b.options.smoothingSamples,
        a.options.thresholdDps - b.options.thresholdDps,
        a.options.minGapSeconds - b.options.minGapSeconds,
    ];
    return comparisons.find((comparison) => comparison !== 0) ?? 0;
}

function betterFused(a: CandidateScore, b: CandidateScore): number {
    const comparisons = [
        a.fusedAbsError - b.fusedAbsError,
        a.fusedRestFalsePositives - b.fusedRestFalsePositives,
        betterGyro(a, b),
    ];
    return comparisons.find((comparison) => comparison !== 0) ?? 0;
}

function printFixture(
    loaded: LoadedFixture,
    gyroOptions: GyroPeakOptions | null,
    fusedOptions: GyroPeakOptions | null,
): void {
    const accel = scoreEvents(loaded, loaded.accelEvents);
    const truth = loaded.fixture.realSwingsPerSet.join(",");
    console.log(
        `${loaded.fixture.id}: accel=[${accel.perSet.join(",")}] real=[${truth}] `
        + `absError=${accel.absError.toString()} restFP=${accel.restFalsePositives.toString()}`,
    );
    if (loaded.gyro.length === 0 || gyroOptions === null || fusedOptions === null) {
        console.log("  gyro/fused: unavailable (fixture has no raw gyro axes)");
        return;
    }
    const gyro = gyroEvents(loaded, gyroOptions);
    const gyroScore = scoreEvents(loaded, gyro);
    const fusedGyro = gyroEvents(loaded, fusedOptions);
    const fusedScore = scoreEvents(loaded, fusedEvents(fusedGyro, loaded.accelEvents));
    console.log(
        `  gyro=[${gyroScore.perSet.join(",")}] absError=${gyroScore.absError.toString()} `
        + `restFP=${gyroScore.restFalsePositives.toString()}`,
    );
    console.log(
        `  fused=[${fusedScore.perSet.join(",")}] absError=${fusedScore.absError.toString()} `
        + `restFP=${fusedScore.restFalsePositives.toString()}`,
    );
}

export function main(): number {
    const index = JSON.parse(readFileSync(join(FIXTURES_DIR, "index.json"), "utf8")) as FixtureIndex;
    const loaded = index.fixtures
        .filter((fixture) => fixture.equipment === "mace")
        .map(loadFixture);
    if (loaded.length === 0) {
        console.error("no mace fixtures found in tools/fixtures/index.json");
        return 1;
    }
    const withGyro = loaded.filter((fixture) => fixture.gyro.length > 0);
    const candidates = withGyro.length > 0
        ? optionGrid().map((options) => scoreCandidate(withGyro, options))
        : [];
    candidates.sort(betterGyro);
    const bestGyro = candidates[0] ?? null;
    const fusedCandidates = [...candidates].sort(betterFused);
    const bestFused = fusedCandidates[0] ?? null;

    for (const fixture of loaded) {
        printFixture(fixture, bestGyro?.options ?? null, bestFused?.options ?? null);
    }
    console.log(
        `\nAccelerometer baseline: MACE_HIGH_MG=${MACE_HIGH_MG.toString()} across `
        + `${loaded.length.toString()} fixtures.`,
    );
    if (bestGyro !== null) {
        console.log(
            `Best gyro across ${withGyro.length.toString()} gyro fixtures: `
            + `smooth=${bestGyro.options.smoothingSamples.toString()} samples `
            + `threshold=${bestGyro.options.thresholdDps.toString()}deg/s `
            + `gap=${bestGyro.options.minGapSeconds.toString()}s; `
            + `absError=${bestGyro.gyroAbsError.toString()} `
            + `restFP=${bestGyro.gyroRestFalsePositives.toString()}.`,
        );
    }
    if (bestFused !== null) {
        console.log(
            `Best conservative fusion: smooth=${bestFused.options.smoothingSamples.toString()} samples `
            + `threshold=${bestFused.options.thresholdDps.toString()}deg/s `
            + `gap=${bestFused.options.minGapSeconds.toString()}s; `
            + `absError=${bestFused.fusedAbsError.toString()} `
            + `restFP=${bestFused.fusedRestFalsePositives.toString()}.`,
        );
    }
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
