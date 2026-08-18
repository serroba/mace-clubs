import assert from "node:assert/strict";
import { test } from "node:test";

import { analyze, confidence } from "./analyze-workout.js";

function report(laps, records = null, elapsed = 60) {
    return { summary: { elapsed }, laps, records: records ?? [] };
}

function work(number, smoothness, peak, side = "Two-handed", exposure = 100) {
    return { phase: "work", set: number, elapsed: 20, smoothness,
             motion_peak: peak, side, exposure };
}

test("confidence thresholds", () => {
    assert.deepEqual([0, 2, 4, 8].map(confidence),
                     ["insufficient", "low", "medium", "high"]);
});

test("detects smoothness decline and peak increase", () => {
    const laps = [
        [90, 1000], [88, 1050], [86, 1100], [84, 1150],
        [72, 1400], [70, 1450], [68, 1500], [66, 1550],
    ].map(([score, peak], index) => work(index + 1, score, peak));
    const result = analyze(report(laps));
    const [smooth, peak] = result.signals;
    assert.deepEqual([smooth.direction, smooth.confidence], ["lower", "high"]);
    assert.deepEqual([peak.direction, peak.confidence], ["higher", "high"]);
    assert.ok(smooth.value < -15);
    assert.ok(peak.value > 30);
});

test("small sample is unavailable", () => {
    const result = analyze(report([work(1, 80, 1000), work(2, 70, 1200)]));
    assert.equal(result.signals[0].status, "unavailable");
    assert.equal(result.signals[0].samples, 2);
});

test("left/right balance uses exposure", () => {
    const laps = [work(1, 80, 1000, "Left", 200), work(2, 80, 1000, "Right", 100),
                  work(3, 80, 1000, "Left", 200), work(4, 80, 1000, "Right", 100)];
    const signal = analyze(report(laps)).signals[2];
    assert.equal(signal.direction, "left");
    assert.equal(signal.left, 66.7);
});

test("two-handed sets do not claim balance", () => {
    const laps = Array.from({ length: 8 }, (_, index) => work(index + 1, 80, 1000));
    assert.equal(analyze(report(laps)).signals[2].status, "unavailable");
});

test("dropout detects missing interval", () => {
    const records = [0, 1, 2, 8, 9].map((second) => ({ t: second, rms: 1000 }));
    const signal = analyze(report([], records, 10)).signals[3];
    assert.equal(signal.direction, "gap");
    assert.equal(signal.value, 5.0);
    assert.equal(signal.coverage, 50.0);
});

test("no motion reports unavailable", () => {
    const result = analyze(report([]));
    assert.equal(result.signals[3].status, "unavailable");
    assert.match(result.disclaimer, /not tendon force/);
});
