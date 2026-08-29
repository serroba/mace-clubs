import assert from "node:assert/strict";
import test from "node:test";

import { detectGyroPeaks, detectStreamingGyroPeaks, type GyroSample } from "./gyro-swing.ts";

test("detects separated smoothed rotation peaks", () => {
    const rates = [0, 100, 300, 100, 0, 0, 120, 320, 120, 0];
    const samples: GyroSample[] = rates.map((rate, index) => [index * 0.5, rate, 0, 0]);
    const peaks = detectGyroPeaks(samples, {
        smoothingSamples: 1,
        thresholdDps: 250,
        minGapSeconds: 1.5,
    });
    assert.deepEqual(peaks.map((peak) => peak.t), [1, 3.5]);
});

test("keeps the strongest peak inside a refractory neighbourhood", () => {
    const rates = [0, 280, 0, 0, 350, 0, 0];
    const samples: GyroSample[] = rates.map((rate, index) => [index * 0.4, rate, 0, 0]);
    const peaks = detectGyroPeaks(samples, {
        smoothingSamples: 1,
        thresholdDps: 250,
        minGapSeconds: 1.5,
    });
    assert.deepEqual(peaks.map((peak) => peak.t), [1.6]);
});

test("returns no peaks when gyro data is unavailable", () => {
    assert.deepEqual(detectGyroPeaks([], {
        smoothingSamples: 7,
        thresholdDps: 270,
        minGapSeconds: 1.5,
    }), []);
});

test("streaming detector confirms a peak one sample later", () => {
    const rates = [0, 100, 300, 100, 0, 0, 120, 320, 120, 0];
    const samples: GyroSample[] = rates.map((rate, index) => [index * 0.5, rate, 0, 0]);
    const peaks = detectStreamingGyroPeaks(samples, {
        smoothingSamples: 1,
        thresholdDps: 250,
        minGapSeconds: 1.5,
    });
    assert.deepEqual(peaks.map((peak) => peak.t), [1, 3.5]);
});
