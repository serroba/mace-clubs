import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { loadReport, main, renderText, validate } from "./validate-workout.js";

function healthyReport() {
    return {
        summary: { elapsed: 20, sets: 1, movement: "Flow / other",
                   side: "Two-handed", equipment: "Clubs: 2 x 4 kg" },
        laps: [{ lap: 1, start: 0, end: 20, elapsed: 20,
                 phase: "work", set: 1, smoothness: 80,
                 motion_peak: 2200, exposure: 1000,
                 active_seconds: 18, swings: 20 }],
        records: Array.from({ length: 20 }, (_, second) => ({
            t: second, rms: 1000, peak: 2000, hr: 90,
            swing_total: second, swing_event: second ? 1 : 0,
            swing_cadence: 60, smoothness_score: 80,
        })),
    };
}

const codes = (result) => new Set(result.findings.map((item) => item.code));

function withCapturedStdout(run) {
    const written = [];
    const original = process.stdout.write;
    process.stdout.write = (chunk) => {
        written.push(String(chunk));
        return true;
    };
    try {
        return { result: run(), stdout: written.join("") };
    } finally {
        process.stdout.write = original;
    }
}

test("healthy recording scores 100", () => {
    const result = validate(healthyReport());
    assert.equal(result.status, "healthy");
    assert.equal(result.score, 100);
    assert.deepEqual(result.counts, { errors: 0, warnings: 0 });
    assert.equal(result.observed.work_laps, 1);
});

test("gaps and metadata are explained", () => {
    const report = healthyReport();
    Object.assign(report.summary, { sets: 2, movement: "Unknown", side: "Unknown", equipment: null });
    report.records = report.records.slice(0, 5);
    const result = validate(report);
    assert.equal(result.status, "usable_with_gaps");
    for (const code of ["sets.total_mismatch", "motion.coverage", "heart_rate.coverage",
                        "metadata.movement", "metadata.side", "metadata.equipment"]) {
        assert.ok(codes(result).has(code), code);
    }
});

test("motion is optional when logging is off", () => {
    const report = healthyReport();
    report.records = Array.from({ length: 20 }, (_, second) => ({ t: second, rms: null, peak: null, hr: 90 }));
    const result = validate(report);
    assert.equal(result.status, "healthy");
    assert.ok(codes(result).has("motion.unavailable"));
});

test("structural and range errors fail", () => {
    const report = healthyReport();
    report.summary.elapsed = 0;
    report.laps = [
        { lap: 1, start: 0, end: 10, elapsed: 9, phase: "work",
          set: 2, smoothness: 101, motion_peak: -1, exposure: -2,
          active_seconds: -3, swings: -4 },
        { lap: 2, start: 8.5, end: 15, elapsed: 6.5, phase: "rest", set: 0 },
    ];
    report.records = [{ t: 1, rms: -1, peak: -2, hr: null }];
    const result = validate(report);
    assert.equal(result.status, "invalid");
    assert.equal(result.score, 0);
    for (const code of ["session.duration", "sets.sequence", "laps.overlap",
                        "sets.short", "smoothness.range", "motion_peak.negative", "motion.negative",
                        "heart_rate.unavailable"]) {
        assert.ok(codes(result).has(code), code);
    }
});

test("subsecond lap boundary rounding is allowed", () => {
    const report = healthyReport();
    report.laps = [
        { lap: 1, start: 0, end: 10.4, elapsed: 10.4, phase: "work",
          set: 1, smoothness: 80 },
        { lap: 2, start: 10, end: 20, elapsed: 9.6, phase: "rest", set: 0 },
    ];
    assert.ok(!codes(validate(report)).has("laps.overlap"));
});

test("set finding links to affected set", () => {
    const report = healthyReport();
    report.laps[0].elapsed = 3;
    const short = validate(report).findings.find((item) => item.code === "sets.short");
    assert.equal(short.target, "set-1");
});

test("missing laps is invalid", () => {
    const report = healthyReport();
    report.laps = [];
    const result = validate(report);
    assert.equal(result.status, "invalid");
    assert.ok(codes(result).has("laps.missing"));
});

test("laps without numbered work are invalid", () => {
    const report = healthyReport();
    report.summary.sets = 0;
    report.laps = [{ lap: 1, start: 0, end: 20, elapsed: 20, phase: "rest", set: 0 }];
    const result = validate(report);
    assert.equal(result.status, "invalid");
    assert.ok(codes(result).has("laps.no_work"));
});

test("peak below rms and duration mismatch warn", () => {
    const report = healthyReport();
    report.summary.elapsed = 30;
    report.records = Array.from({ length: 30 }, (_, second) => ({ t: second, rms: 2000, peak: 1000, hr: 90 }));
    const result = validate(report);
    assert.ok(codes(result).has("motion.peak_below_rms"));
    assert.ok(codes(result).has("laps.duration_mismatch"));
});

test("swing total regression is invalid", () => {
    const report = healthyReport();
    report.records[10].swing_total = 3;
    const result = validate(report);
    assert.equal(result.status, "invalid");
    const regression = result.findings.find((item) => item.code === "swings.regression");
    assert.equal(regression.target, "timeline");
});

test("swing events must reconcile with total", () => {
    const report = healthyReport();
    report.records[5].swing_event = 3;
    assert.ok(codes(validate(report)).has("swings.event_mismatch"));
});

test("partial swing series warns on coverage", () => {
    const report = healthyReport();
    for (const record of report.records.slice(4)) {
        record.swing_total = null;
        record.swing_event = null;
    }
    assert.ok(codes(validate(report)).has("swings.coverage"));
});

test("cadence and rolling smoothness ranges", () => {
    const report = healthyReport();
    report.records[3].swing_cadence = 250;
    report.records[4].smoothness_score = 130;
    const result = validate(report);
    assert.equal(result.status, "invalid");
    assert.ok(codes(result).has("cadence.range"));
    assert.ok(codes(result).has("smoothness.series_range"));
});

test("series counts are observed", () => {
    const result = validate(healthyReport());
    assert.equal(result.observed.swing_samples, 20);
    assert.equal(result.observed.smoothness_samples, 20);
});

test("text and json cli", () => {
    const text = renderText(validate(healthyReport()));
    assert.match(text, /healthy \(100\/100\)/);
    assert.match(text, /No integrity/);

    const { result, stdout } = withCapturedStdout(
        () => main(["activity.fit", "--json"], () => healthyReport()));
    assert.equal(result, 0);
    assert.equal(JSON.parse(stdout).score, 100);
});

test("cli fails for structural errors", () => {
    const report = healthyReport();
    report.laps = [];
    const { result, stdout } = withCapturedStdout(() => main(["activity.fit"], () => report));
    assert.equal(result, 1);
    assert.match(stdout, /ERROR/);
});

test("cli rejects missing or extra arguments", () => {
    assert.throws(() => main([], () => healthyReport()), /usage:/);
    assert.throws(() => main(["a.fit", "b.fit"], () => healthyReport()), /unexpected argument/);
});

test("loadReport parses a real FIT export", () => {
    return import("./synthetic-workout.js").then(({ buildFit, workout }) => {
        const root = mkdtempSync(join(tmpdir(), "mace-validate-"));
        try {
            const source = join(root, "activity.fit");
            buildFit(workout(), source);
            const report = loadReport(source);
            assert.equal(report.summary.elapsed, 50);
            assert.equal(validate(report).status, "healthy");
        } finally {
            rmSync(root, { recursive: true, force: true });
        }
    });
});
