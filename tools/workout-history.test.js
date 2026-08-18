import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { comparisons, importSource, load, main, metric, summarize } from "./workout-history.js";

function workout(value, identifier) {
    const metrics = Object.fromEntries(
        ["duration", "work_seconds", "sets", "motion_exposure", "active_seconds",
         "weight_volume", "motion_peak", "smoothness"].map((name) => [name, value]));
    return { id: identifier, metrics };
}

function withTempDir(run) {
    const root = mkdtempSync(join(tmpdir(), "mace-history-"));
    try {
        return run(root);
    } finally {
        rmSync(root, { recursive: true, force: true });
    }
}

test("metric aggregation", () => {
    const laps = [{ motion_exposure: 10, motion_peak: 20, smoothness: 60 },
                  { motion_exposure: 15, motion_peak: 18, smoothness: 80 }];
    assert.equal(metric(laps, "motion_exposure"), 25);
    assert.equal(metric(laps, "motion_peak"), 20);
    assert.equal(metric(laps, "smoothness"), 70);
    assert.equal(metric(laps, "active_seconds"), null);
});

test("summary excludes time series", () => {
    const report = { summary: { date: "16 Aug 2026", movement: "Flow", side: "Both", elapsed: 60, work_seconds: 20 },
                     laps: [{ phase: "work", set: 1, motion_exposure: 100 }],
                     records: [{ rms: 999 }] };
    const item = summarize(report, "abc", "now");
    assert.equal(item.metrics.motion_exposure, 100);
    assert.equal(item.metrics.duration, 60);
    assert.ok(!("records" in item));
});

test("comparison uses recent personal median", () => {
    const entries = [90, 100, 110, 150].map((value) => workout(value, String(value)));
    const result = comparisons(entries)[0];
    assert.equal(result.baseline, 100);
    assert.equal(result.change_percent, 50);
    assert.equal(result.direction, "higher");
    assert.ok(result.review);
});

test("comparison requires three prior values", () => {
    assert.equal(comparisons([workout(100, "a")])[0].status, "unavailable");
});

test("comparison excludes sessions without work sets", () => {
    const entries = [90, 100, 110, 150].map((value) => workout(value, String(value)));
    entries[1].metrics.sets = 0;
    assert.equal(comparisons(entries)[0].status, "unavailable");
});

test("cli imports, exports, and clears", () => {
    withTempDir((root) => {
        const source = join(root, "a.fit");
        writeFileSync(source, "fit");
        const report = { summary: { elapsed: 10, date: "16 Aug 2026", work_seconds: 5 },
                         laps: [{ phase: "work", set: 1, smoothness: 80 }], records: [] };
        const database = join(root, "history.json");
        const exported = join(root, "exported.json");
        const original = process.stdout.write;
        process.stdout.write = () => true;
        try {
            assert.equal(main(["--database", database, "import", source], () => report), 0);
            assert.equal(main(["--database", database, "export", exported]), 0);
            assert.equal(main(["--database", database, "clear"]), 0);
        } finally {
            process.stdout.write = original;
        }
        assert.equal(load(exported).workouts.length, 1);
        assert.equal(load(exported).workouts[0].metrics.smoothness, 80);
        assert.deepEqual(load(database).workouts, []);
    });
});

test("cli rejects unknown commands and incomplete arguments", () => {
    assert.throws(() => main(["frobnicate"]), /usage:/);
    assert.throws(() => main(["import"]), /at least one/);
    assert.throws(() => main(["export"]), /output path/);
    assert.throws(() => main(["delete"]), /workout id/);
});

test("import deduplicates and cli deletes", () => {
    withTempDir((root) => {
        const source = join(root, "a.fit");
        writeFileSync(source, "fit");
        const report = { summary: { elapsed: 10, date: "16 Aug 2026" }, laps: [], records: [] };
        const history = { version: 1, privacy: "local-summary-only", workouts: [] };
        const loader = () => report;
        importSource(history, source, loader);
        importSource(history, source, loader);
        assert.equal(history.workouts.length, 1);
        const database = join(root, "history.json");
        writeFileSync(database, JSON.stringify(history));
        const identifier = history.workouts[0].id;
        main(["--database", database, "delete", identifier]);
        assert.deepEqual(load(database).workouts, []);
    });
});
