import assert from "node:assert/strict";
import test from "node:test";

import { detectStreamingGyroPeaks } from "./gyro-swing.ts";
import { readFit } from "./fit-io.ts";
import { collect } from "./report-fit.ts";
import { computeOrigin, extractGyro } from "./replay-swing.ts";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const FIXTURES = fileURLToPath(new URL("fixtures/", import.meta.url));
const SHARED_OPTIONS = { smoothingSamples: 11, thresholdDps: 250, minGapSeconds: 1 } as const;

function perSet(file: string): number[] {
    const fit = readFit(readFileSync(`${FIXTURES}${file}`));
    const report = collect(fit);
    const events = detectStreamingGyroPeaks(extractGyro(fit, computeOrigin(fit)), SHARED_OPTIONS)
        .map((peak) => peak.t);
    return report.laps
        .filter((lap) => lap.phase === "work" && (lap.set ?? 0) > 0)
        .map((lap) => events.filter((time) => time >= (lap.start ?? 0) && time <= (lap.end ?? 0)).length);
}

test("shared gyro model generalizes across labelled mace recordings", () => {
    assert.deepEqual(perSet("24071684170_ACTIVITY.fit"), [5, 5, 10, 10]);
    assert.deepEqual(perSet("24142167505_ACTIVITY.fit"), [60, 60]);
});
