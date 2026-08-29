#!/usr/bin/env node
// Exports a real recorded fixture's per-second gyroscope samples and
// work/rest phase as a Monkey C source file, so on-device replay tests
// (source/motion/RecordedSwingReplay.mc and friends) can feed them through
// the actual production watch code - not a reimplementation - to check
// whether a change moves the calculated values on a real recording. This is
// the data-generation half of that replay-testing framework; only fixtures
// with recorded gyro data (swingDebugEnabled, post-gyro-capture) currently
// export. Dev/CI only: the generated file is a (:test)-annotated module,
// excluded from every store build (see monkey.jungle's base.excludeAnnotations).
//
// Usage:
//     node --experimental-strip-types tools/export-replay-fixture.ts recB
//     node --experimental-strip-types tools/export-replay-fixture.ts recB --resample25hz

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { readFit } from "./fit-io.ts";
import { collect } from "./report-fit.ts";
import { computeOrigin, extractGyro } from "./replay-swing.ts";

const FIXTURES_DIR = fileURLToPath(new URL("fixtures", import.meta.url));
const OUTPUT_DIR = fileURLToPath(new URL("../source/motion", import.meta.url));

interface Fixture {
    readonly id: string;
    readonly file: string;
}

interface FixtureIndex {
    readonly fixtures: Fixture[];
}

interface SecondBucket {
    readonly gyroX: number[];
    readonly gyroY: number[];
    readonly gyroZ: number[];
}

const PRODUCTION_SAMPLE_RATE_HZ = 25;

// The debug FIT export only ever stores gyro decimated 2x (~12.5Hz) to fit
// the developer-field budget, but SwingCounter's constants (GYRO_SMOOTHING_SAMPLES,
// GYRO_MIN_GAP_SAMPLES) are sample COUNTS meant for real 25Hz input - feeding
// them decimated samples directly halves the wall-clock time those counts
// actually span, which would make any replay-driven tuning search optimize
// parameters for the wrong input rate. Linearly interpolating back to a true
// 25Hz stream restores correct window/refractory timing; it cannot recover
// real sub-80ms rotation detail that was never captured, so replay still
// won't exactly reproduce true on-device full-resolution counts.
//
// This roughly doubles the sample count, which pushes recC's generated file
// past tools/pre_commit.sh's 1 MiB block once formatted - so it's opt-in via
// --resample25hz, writing a separate *Tuning module that stays gitignored
// (see .gitignore) rather than the small, committed, always-decimated
// regression fixture. SwingTuningSearch.mc is the only thing that needs it;
// regenerate before running `make tuning-search`.
function resampleTo25Hz(samples: readonly [number, number, number, number][]): [number, number, number, number][] {
    const first = samples[0];
    const last = samples[samples.length - 1];
    if (first === undefined || last === undefined) {
        return [...samples];
    }
    const step = 1 / PRODUCTION_SAMPLE_RATE_HZ;
    const start = Math.ceil(first[0] * PRODUCTION_SAMPLE_RATE_HZ) * step;
    const end = Math.floor(last[0] * PRODUCTION_SAMPLE_RATE_HZ) * step;
    const out: [number, number, number, number][] = [];
    let cursor = 0;
    for (let t = start; t <= end + 1e-9; t += step) {
        while (cursor < samples.length - 2 && (samples[cursor + 1]?.[0] ?? Infinity) <= t) {
            cursor += 1;
        }
        const before = samples[cursor];
        const after = samples[Math.min(cursor + 1, samples.length - 1)];
        if (before === undefined || after === undefined) {
            continue;
        }
        const span = after[0] - before[0];
        const frac = span > 0 ? (t - before[0]) / span : 0;
        out.push([
            t,
            before[1] + (after[1] - before[1]) * frac,
            before[2] + (after[2] - before[2]) * frac,
            before[3] + (after[3] - before[3]) * frac,
        ]);
    }
    return out;
}

function pascalCase(id: string): string {
    return id.charAt(0).toUpperCase() + id.slice(1);
}

function formatFloatArray(values: readonly number[], decimals: number): string {
    return `[${values.map((value) => value.toFixed(decimals)).join(", ")}]`;
}

function main(): void {
    const id = process.argv[2];
    if (id === undefined) {
        console.error("usage: export-replay-fixture.ts <fixtureId>");
        process.exitCode = 1;
        return;
    }

    const index = JSON.parse(readFileSync(join(FIXTURES_DIR, "index.json"), "utf8")) as FixtureIndex;
    const fixture = index.fixtures.find((candidate) => candidate.id === id);
    if (fixture === undefined) {
        console.error(`no fixture "${id}" in tools/fixtures/index.json`);
        process.exitCode = 1;
        return;
    }

    const resample = process.argv.includes("--resample25hz");

    const fit = readFit(readFileSync(join(FIXTURES_DIR, fixture.file)));
    const origin = computeOrigin(fit);
    const rawGyro = extractGyro(fit, origin);
    if (rawGyro.length === 0) {
        console.error(
            `fixture "${id}" has no recorded gyro data (swingDebugEnabled off, or predates gyro capture)`,
        );
        process.exitCode = 1;
        return;
    }
    const gyro = resample ? resampleTo25Hz(rawGyro) : rawGyro;

    const report = collect(fit);
    const workLaps: { start: number; end: number }[] = [];
    for (const lap of report.laps) {
        if (lap.phase === "work" && (lap.set ?? 0) > 0 && lap.start !== undefined && lap.end !== undefined) {
            workLaps.push({ start: lap.start, end: lap.end });
        }
    }
    const lastEnd = Math.max(...report.laps.map((lap) => lap.end ?? 0));
    const secondsCount = Math.ceil(lastEnd);

    const buckets: SecondBucket[] = Array.from({ length: secondsCount }, () => ({
        gyroX: [],
        gyroY: [],
        gyroZ: [],
    }));
    for (const [t, x, y, z] of gyro) {
        const bucket = Math.floor(t);
        if (bucket >= 0 && bucket < secondsCount) {
            const target = buckets[bucket];
            if (target !== undefined) {
                target.gyroX.push(x);
                target.gyroY.push(y);
                target.gyroZ.push(z);
            }
        }
    }

    // The resampled/tuning variant roughly doubles the sample count, so it
    // keeps tighter precision to help stay clear of the 1 MiB file-size
    // block (2 decimal places is already well beyond sensor precision -
    // raw capture is integer deg/s, interpolation adds fractional but not
    // meaningful sub-hundredth detail).
    const decimals = resample ? 2 : 4;
    const entries = buckets.map((bucket, second) => {
        const midpoint = second + 0.5;
        const workOpen = workLaps.some((lap) => lap.start <= midpoint && midpoint < lap.end);
        return (
            `        { :workOpen => ${String(workOpen)}, ` +
            `:gyroX => ${formatFloatArray(bucket.gyroX, decimals)} as Array<Float>, ` +
            `:gyroY => ${formatFloatArray(bucket.gyroY, decimals)} as Array<Float>, ` +
            `:gyroZ => ${formatFloatArray(bucket.gyroZ, decimals)} as Array<Float> }`
        );
    });

    const moduleName = `RecordedFixture${pascalCase(id)}${resample ? "Tuning" : ""}`;
    const gyroDescription = resample
        ? `// gyroX/Y/Z are the real per-axis deg/s samples the watch recorded, decimated
// 2x at capture time (~12.5Hz) to fit the FIT developer-field budget, then
// linearly interpolated back to a true 25Hz stream here so SwingCounter's
// sample-count constants (GYRO_SMOOTHING_SAMPLES, GYRO_MIN_GAP_SAMPLES) mean
// what they mean in production. That recovers correct window/refractory
// timing but not real sub-80ms rotation detail lost at capture, so replaying
// this still won't exactly reproduce tools/fixtures/index.json's
// onDeviceDetectedPerSet. Dev-local only: gitignored, not committed - this
// file exists only to feed SwingTuningSearch.mc's grid search
// (\`make tuning-search\`); regenerate it before running that.`
        : `// gyroX/Y/Z are the real per-axis deg/s samples the watch recorded, decimated
// 2x at capture time (~12.5Hz) to fit the FIT developer-field budget - the
// debug export never stores full 25Hz gyro, so replaying this cannot exactly
// reproduce tools/fixtures/index.json's onDeviceDetectedPerSet. It exercises
// the real production SwingCounter deterministically against real (if
// coarser) motion, which is what matters for catching whether a tuning
// change moves the count on this recording. See RecordedSwingReplay.mc and
// RecordedSwingReplayTest.mc for how this feeds through.
//
// Dev/CI only: excluded from every store build by the (:test) annotation
// (see monkey.jungle).`;
    const source = `import Toybox.Lang;

// Real recorded gyroscope replay data for tools/fixtures/index.json's "${id}"
// fixture, extracted from ${fixture.file}. One entry per second, 0-indexed
// from the FIT recording's origin (the same origin computeOrigin() uses in
// report-fit.ts/replay-swing.ts).
//
${gyroDescription}
//
// Regenerate with: node --experimental-strip-types tools/export-replay-fixture.ts ${id}${resample ? " --resample25hz" : ""}
(:test)
module ${moduleName} {
    function seconds() as Array<Dictionary> {
        return [
${entries.join(",\n")}
        ] as Array<Dictionary>;
    }
}
`;

    const outputPath = join(OUTPUT_DIR, `${moduleName}.mc`);
    writeFileSync(outputPath, source);
    console.log(`wrote ${outputPath} (${String(secondsCount)}s span, ${String(gyro.length)} gyro samples)`);
}

main();
