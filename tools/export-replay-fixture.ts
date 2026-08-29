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

function pascalCase(id: string): string {
    return id.charAt(0).toUpperCase() + id.slice(1);
}

function formatFloatArray(values: readonly number[]): string {
    return `[${values.map((value) => value.toFixed(4)).join(", ")}]`;
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

    const fit = readFit(readFileSync(join(FIXTURES_DIR, fixture.file)));
    const origin = computeOrigin(fit);
    const gyro = extractGyro(fit, origin);
    if (gyro.length === 0) {
        console.error(
            `fixture "${id}" has no recorded gyro data (swingDebugEnabled off, or predates gyro capture)`,
        );
        process.exitCode = 1;
        return;
    }

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

    const entries = buckets.map((bucket, second) => {
        const midpoint = second + 0.5;
        const workOpen = workLaps.some((lap) => lap.start <= midpoint && midpoint < lap.end);
        return (
            `        { :workOpen => ${String(workOpen)}, ` +
            `:gyroX => ${formatFloatArray(bucket.gyroX)} as Array<Float>, ` +
            `:gyroY => ${formatFloatArray(bucket.gyroY)} as Array<Float>, ` +
            `:gyroZ => ${formatFloatArray(bucket.gyroZ)} as Array<Float> }`
        );
    });

    const moduleName = `RecordedFixture${pascalCase(id)}`;
    const source = `import Toybox.Lang;

// Real recorded gyroscope replay data for tools/fixtures/index.json's "${id}"
// fixture, extracted from ${fixture.file}. One entry per second, 0-indexed
// from the FIT recording's origin (the same origin computeOrigin() uses in
// report-fit.ts/replay-swing.ts). Dev/CI only: excluded from every store
// build by the (:test) annotation (see monkey.jungle).
//
// gyroX/Y/Z are the real per-axis deg/s samples the watch recorded, decimated
// 2x at capture time (~12.5Hz) to fit the FIT developer-field budget - the
// debug export never stores full 25Hz gyro, so replaying this cannot exactly
// reproduce tools/fixtures/index.json's onDeviceDetectedPerSet. It exercises
// the real production SwingCounter deterministically against real (if
// coarser) motion, which is what matters for catching whether a tuning
// change moves the count on this recording. See RecordedSwingReplay.mc and
// RecordedSwingReplayTest.mc for how this feeds through.
//
// Regenerate with: node --experimental-strip-types tools/export-replay-fixture.ts ${id}
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
