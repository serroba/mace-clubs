import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { type Report, type ReportLap } from "./report-types.ts";
import {
    comparisons,
    type History,
    type HistoryEntry,
    importSource,
    load,
    main,
    metric,
    type MetricName,
    type Metrics,
    summarize,
} from "./workout-history.ts";

const METRIC_NAMES: readonly MetricName[] = [
    "duration", "work_seconds", "sets", "motion_exposure",
    "active_seconds", "weight_volume", "motion_peak", "smoothness",
];

function workout(value: number, identifier: string): HistoryEntry {
    const metrics: Metrics = Object.fromEntries(METRIC_NAMES.map((name) => [name, value]));
    return { id: identifier, imported_at: "now", date: null, movement: null,
             side: null, equipment: null, sets: value, duration: value, metrics };
}

function withTempDir<T>(run: (root: string) => T): T {
    const root = mkdtempSync(join(tmpdir(), "mace-history-"));
    try {
        return run(root);
    } finally {
        rmSync(root, { recursive: true, force: true });
    }
}

function silencingStdout<T>(run: () => T): T {
    const original = process.stdout.write.bind(process.stdout);
    process.stdout.write = (): boolean => true;
    try {
        return run();
    } finally {
        process.stdout.write = original;
    }
}

test("metric aggregation", () => {
    const laps: ReportLap[] = [{ exposure: 10, motion_peak: 20, smoothness: 60 },
                               { exposure: 15, motion_peak: 18, smoothness: 80 }];
    assert.equal(metric(laps, "motion_exposure"), 25);
    assert.equal(metric(laps, "motion_peak"), 20);
    assert.equal(metric(laps, "smoothness"), 70);
    assert.equal(metric(laps, "active_seconds"), null);
});

test("summary excludes time series", () => {
    const report: Report = {
        summary: { date: "16 Aug 2026", movement: "Flow", side: "Both", elapsed: 60, work_seconds: 20 },
        laps: [{ phase: "work", set: 1, exposure: 100 }],
        records: [{ t: 0, rms: 999 }],
    };
    const item = summarize(report, "abc", "now");
    assert.equal(item.metrics.motion_exposure, 100);
    assert.equal(item.metrics.duration, 60);
    assert.ok(!("records" in item));
});

test("comparison uses recent personal median", () => {
    const entries = [90, 100, 110, 150].map((value) => workout(value, String(value)));
    const result = comparisons(entries)[0];
    assert.ok(result !== undefined);
    assert.equal(result.baseline, 100);
    assert.equal(result.change_percent, 50);
    assert.equal(result.direction, "higher");
    assert.equal(result.review, true);
});

test("comparison requires three prior values", () => {
    const result = comparisons([workout(100, "a")])[0];
    assert.ok(result !== undefined);
    assert.equal(result.status, "unavailable");
});

test("comparison excludes sessions without work sets", () => {
    const entries = [90, 100, 110, 150].map((value) => workout(value, String(value)));
    const second = entries[1];
    assert.ok(second !== undefined);
    second.metrics.sets = 0;
    const result = comparisons(entries)[0];
    assert.ok(result !== undefined);
    assert.equal(result.status, "unavailable");
});

test("cli imports, exports, and clears", () => {
    withTempDir((root) => {
        const source = join(root, "a.fit");
        writeFileSync(source, "fit");
        const report: Report = { summary: { elapsed: 10, date: "16 Aug 2026", work_seconds: 5 },
                                 laps: [{ phase: "work", set: 1, smoothness: 80 }], records: [] };
        const database = join(root, "history.json");
        const exported = join(root, "exported.json");
        silencingStdout(() => {
            assert.equal(main(["--database", database, "import", source], () => report), 0);
            assert.equal(main(["--database", database, "export", exported]), 0);
            assert.equal(main(["--database", database, "clear"]), 0);
        });
        assert.equal(load(exported).workouts.length, 1);
        assert.equal(load(exported).workouts[0]?.metrics.smoothness, 80);
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
        const report: Report = { summary: { elapsed: 10, date: "16 Aug 2026" }, laps: [], records: [] };
        const history: History = { version: 1, privacy: "local-summary-only", workouts: [] };
        const loader = (): Report => report;
        importSource(history, source, loader);
        importSource(history, source, loader);
        assert.equal(history.workouts.length, 1);
        const database = join(root, "history.json");
        writeFileSync(database, JSON.stringify(history));
        const identifier = history.workouts[0]?.id;
        assert.ok(identifier !== undefined);
        silencingStdout(() => main(["--database", database, "delete", identifier]));
        assert.deepEqual(load(database).workouts, []);
    });
});
