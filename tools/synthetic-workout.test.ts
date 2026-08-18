import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { fieldValue, messagesOf, readFit } from "./fit-io.ts";
import { BASELINE, buildFit, main, renderSvg, samples, workout } from "./synthetic-workout.ts";

function withTempDir<T>(run: (root: string) => T): T {
    const root = mkdtempSync(join(tmpdir(), "mace-synthetic-test-"));
    try {
        return run(root);
    } finally {
        rmSync(root, { recursive: true, force: true });
    }
}

test("scenario has expected phases and deliberate spike", () => {
    const windows = workout();
    const spike = windows[42];
    assert.ok(spike !== undefined);
    assert.equal(windows.length, 50);
    assert.equal(windows.filter((item) => item.phase === "rest").length, 10);
    assert.equal(windows.filter((item) => item.phase === "work").length, 40);
    assert.equal(spike.style, "spike");
    assert.ok(spike.peak > Math.max(...windows.slice(0, 42).map((item) => item.peak)));
});

test("still window preserves gravity but has no dynamic motion", () => {
    const still = workout()[0];
    assert.ok(still !== undefined);
    assert.deepEqual(
        [still.rms, still.peak, still.crossings, still.dynamic_rms, still.dynamic_peak],
        [1000, 1000, 0, 0, 0]);
});

test("unknown motion style is rejected", () => {
    assert.throws(() => samples("teleporting", 0), /unknown motion style/);
});

test("generated fit round trips developer fields", () => {
    withTempDir((root) => {
        const path = join(root, "synthetic.fit");
        buildFit(workout(), path);
        const fit = readFit(readFileSync(path));
        assert.deepEqual(fit.errors, []);
        const records = messagesOf(fit, "recordMesgs");
        const firstRecord = records[0];
        const spikeRecord = records[42];
        const lastRecord = records[records.length - 1];
        const spikeWindow = workout()[42];
        assert.ok(firstRecord !== undefined && spikeRecord !== undefined
                  && lastRecord !== undefined && spikeWindow !== undefined);
        assert.equal(records.length, 50);
        assert.equal(fieldValue(fit, firstRecord, "accel_rms"), 1000);
        assert.equal(fieldValue(fit, spikeRecord, "accel_peak"), spikeWindow.peak);
        const events = records.map((record) => fieldValue(fit, record, "swing_event"))
            .filter((value): value is number => typeof value === "number");
        const eventTotal = events.reduce((total, value) => total + value, 0);
        assert.equal(events.length, records.length);
        assert.ok(eventTotal > 0);
        assert.equal(eventTotal, fieldValue(fit, lastRecord, "swing_total"));
        assert.ok(records.every((record) => fieldValue(fit, record, "swing_cadence") !== null));
        const smoothness = records.map((record) => fieldValue(fit, record, "smoothness_score"))
            .filter((value): value is number => typeof value === "number");
        assert.equal(smoothness.length, records.length);
        assert.ok(smoothness.some((score) => score > 0));
        assert.ok(smoothness.every((score) => score >= 0 && score <= 100));
        const session = messagesOf(fit, "sessionMesgs")[0];
        assert.ok(session !== undefined);
        assert.equal(fieldValue(fit, session, "total_sets"), 2);
        assert.equal(fieldValue(fit, session, "work_time"), 40);
        const laps = messagesOf(fit, "lapMesgs");
        assert.deepEqual(laps.map((lap) => fieldValue(fit, lap, "set_number")), [0, 1, 0, 2]);
        assert.deepEqual(laps.map((lap) => fieldValue(fit, lap, "phase")), [0, 1, 0, 1]);
    });
});

test("visual is deterministic", () => {
    const svg = renderSvg(workout());
    assert.equal(readFileSync(BASELINE, "utf8"), svg);
    assert.ok(svg.includes("deliberate spike"));
});

test("cli generates all review artifacts", () => {
    withTempDir((root) => {
        const output = join(root, "artifacts");
        assert.equal(main(["--output-dir", output]), 0);
        assert.deepEqual(
            new Set(readdirSync(output)),
            new Set(["synthetic-workout.fit", "synthetic-workout.svg"]));
    });
});

test("check mode accepts reviewed outputs and rejects drift", () => {
    withTempDir((root) => {
        const baseline = join(root, "baseline.svg");
        writeFileSync(baseline, renderSvg(workout()));
        assert.equal(main(["--check", "--output-dir", join(root, "ok")], baseline), 0);
        writeFileSync(baseline, "changed");
        assert.throws(
            () => main(["--check", "--output-dir", join(root, "bad")], baseline),
            /visual baseline differs/);
        assert.ok(existsSync(join(root, "ok", "synthetic-workout.svg")));
    });
});
