import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { crc32 } from "node:zlib";

import { fitPath, timestampSeconds } from "./fit-io.js";
import { collect, main, render } from "./report-fit.js";

const START = new Date(Date.UTC(2026, 7, 16));
const DAY = 24 * 3600 * 1000;

// Minimal stored-entry ZIP writer, enough to exercise the extractor.
function storedZip(entries) {
    const parts = [];
    const centrals = [];
    let offset = 0;
    for (const [name, data] of entries) {
        const nameBuffer = Buffer.from(name);
        const body = Buffer.from(data);
        const local = Buffer.alloc(30);
        local.writeUInt32LE(0x04034b50, 0);
        local.writeUInt16LE(20, 4);
        local.writeUInt32LE(crc32(body), 14);
        local.writeUInt32LE(body.length, 18);
        local.writeUInt32LE(body.length, 22);
        local.writeUInt16LE(nameBuffer.length, 26);
        const central = Buffer.alloc(46);
        central.writeUInt32LE(0x02014b50, 0);
        central.writeUInt16LE(20, 4);
        central.writeUInt16LE(20, 6);
        central.writeUInt32LE(crc32(body), 16);
        central.writeUInt32LE(body.length, 20);
        central.writeUInt32LE(body.length, 24);
        central.writeUInt16LE(nameBuffer.length, 28);
        central.writeUInt32LE(offset, 42);
        centrals.push(central, nameBuffer);
        parts.push(local, nameBuffer, body);
        offset += 30 + nameBuffer.length + body.length;
    }
    const central = Buffer.concat(centrals);
    const eocd = Buffer.alloc(22);
    eocd.writeUInt32LE(0x06054b50, 0);
    eocd.writeUInt16LE(entries.length, 8);
    eocd.writeUInt16LE(entries.length, 10);
    eocd.writeUInt32LE(central.length, 12);
    eocd.writeUInt32LE(offset, 16);
    return Buffer.concat([...parts, central, eocd]);
}

// Fabricate a readFit()-shaped wrapper; `dev` maps developer field names to values.
function makeFit(kinds) {
    const fieldNames = new Map();
    const nameToKey = new Map();
    const keyFor = (name) => {
        if (!nameToKey.has(name)) {
            const key = nameToKey.size;
            nameToKey.set(name, key);
            fieldNames.set(key, name);
        }
        return nameToKey.get(name);
    };
    const messages = {};
    for (const [kind, mesgs] of Object.entries(kinds)) {
        messages[kind] = mesgs.map(({ dev, ...rest }) => (dev
            ? { ...rest,
                developerFields: Object.fromEntries(
                    Object.entries(dev).map(([name, value]) => [keyFor(name), value])) }
            : rest));
    }
    return { messages, fieldNames, errors: [] };
}

function withTempDir(run) {
    const root = mkdtempSync(join(tmpdir(), "mace-report-"));
    try {
        return run(root);
    } finally {
        rmSync(root, { recursive: true, force: true });
    }
}

test("raw fit path is unchanged", () => {
    assert.equal(fitPath("activity.fit", "unused"), "activity.fit");
});

test("non-date has no timestamp", () => {
    assert.equal(timestampSeconds("yesterday"), null);
});

test("zip chooses activity fit and ignores paths", () => {
    withTempDir((root) => {
        const source = join(root, "export.zip");
        writeFileSync(source, storedZip([["other.fit", "other"], ["nested/123_ACTIVITY.fit", "activity"]]));
        const extracted = fitPath(source, join(root, "out"));
        assert.equal(extracted, join(root, "out", "123_ACTIVITY.fit"));
        assert.equal(readFileSync(extracted, "utf8"), "activity");
    });
});

test("zip without fit is rejected", () => {
    withTempDir((root) => {
        const source = join(root, "export.zip");
        writeFileSync(source, storedZip([["readme.txt", "nothing here"]]));
        assert.throws(() => fitPath(source, join(root, "out")), /contains no FIT/);
    });
});

test("collect aligns records and excludes short set", () => {
    const fit = makeFit({
        sessionMesgs: [{
            totalElapsedTime: 35, totalTimerTime: 35,
            avgHeartRate: 80, maxHeartRate: 110,
            dev: { total_sets: 2 },
        }],
        lapMesgs: [
            { startTime: START, totalElapsedTime: 30,
              dev: { phase: 1, set_number: 1, movement_type: 4, working_side: 3, set_smoothness: 60 } },
            { startTime: new Date(START.getTime() + 30_000), totalElapsedTime: 5,
              dev: { phase: 1, set_number: 2, movement_type: 4, working_side: 3, set_smoothness: 99 } },
        ],
        recordMesgs: [
            { timestamp: new Date(START.getTime() + 1000), heartRate: 70,
              dev: { accel_rms: 1200, accel_peak: 2100, accel_zc: 4,
                     swing_total: 1, swing_event: 1, swing_cadence: 60, smoothness_score: 82 } },
        ],
        activityMesgs: [{ localTimestamp: new Date(START.getTime() + DAY) }],
    });
    const report = collect(fit);
    assert.equal(report.summary.movement, "Flow / other");
    assert.equal(report.summary.valid_sets, 1);
    assert.equal(report.summary.work_seconds, 35);
    assert.equal(report.records[0].t, 1);
    assert.equal(report.records[0].swing_total, 1);
    assert.equal(report.records[0].swing_event, 1);
    assert.equal(report.records[0].swing_cadence, 60);
    assert.equal(report.records[0].smoothness_score, 82);
    assert.equal(report.summary.date, "17 Aug 2026");
});

test("collect reads equipment and skips incomplete samples", () => {
    const fit = makeFit({
        sessionMesgs: [{
            startTime: START, totalElapsedTime: 10, totalTimerTime: 10,
            dev: { notes: "unrelated", implement_name: "Clubs: 2 x 4 kg" },
        }],
        lapMesgs: [{ totalElapsedTime: 5 }],
        recordMesgs: [{ heartRate: 80 }],
    });
    const report = collect(fit);
    assert.equal(report.summary.equipment, "Clubs: 2 x 4 kg");
    assert.equal(report.summary.date, "16 Aug 2026");
    assert.deepEqual(report.laps, []);
    assert.deepEqual(report.records, []);
});

test("collect requires a session", () => {
    assert.throws(() => collect(makeFit({})), /contains no session/);
});

test("render is self-contained and marks anomalies", () => {
    const report = {
        summary: { elapsed: 30, timer: 30, avg_hr: 80,
                   max_hr: 110, sets: 1, movement: "Flow / other",
                   side: "Two-handed", work_seconds: 3,
                   rest_seconds: 27, valid_sets: 0 },
        laps: [{ phase: "work", set: 1, elapsed: 3,
                 start: 0, end: 3, smoothness: 50,
                 motion_peak: null, swings: null }],
        records: [{ t: 1, hr: 80, rms: 1000,
                    peak: 2000, zc: 4, swing_total: 1,
                    swing_event: 1, swing_cadence: 60,
                    smoothness_score: 82 }],
    };
    const rendered = render(report, "Example <activity>");
    assert.ok(rendered.includes("<!doctype html>"));
    assert.ok(!rendered.includes("fetch("));
    assert.ok(rendered.includes("Set ${anomalies"));
    assert.ok(rendered.includes("Example &lt;activity&gt;"));
    assert.ok(rendered.includes("Work</span>"));
    assert.ok(rendered.includes("Recording quality"));
    assert.ok(rendered.includes('id="quality-score"'));
    assert.ok(rendered.includes("set-1"));
    assert.ok(rendered.includes('"status":"usable_with_gaps"'));
    assert.ok(rendered.includes('"code":"sets.short"'));
    assert.ok(rendered.includes('"target":"set-1"'));
    assert.ok(rendered.includes("Within-session signals"));
    assert.ok(rendered.includes("Set rhythm comparison"));
    assert.ok(rendered.includes("Smoothness over time"));
    assert.ok(rendered.includes("d.smoothness_score"));
    assert.ok(rendered.includes("Swing detected"));
    assert.ok(rendered.includes("Synchronized acceleration, swing cadence"));
    assert.ok(rendered.includes('"code":"smoothness_drift"'));
    assert.ok(rendered.includes("not tendon force"));
});

test("zip extractor inflates deflated entries and rejects other methods", async () => {
    const { deflateRawSync } = await import("node:zlib");
    const { zipEntries } = await import("./fit-io.js");
    const body = Buffer.from("squeezed activity bytes");
    const compressed = deflateRawSync(body);
    const zip = storedZip([["stored.fit", "plain"]]);
    // rewrite the stored entry into a deflated one at the same offsets
    const deflated = storedZip([["packed.fit", compressed]]);
    deflated.writeUInt16LE(8, 8); // local header method
    deflated.writeUInt16LE(8, 30 + "packed.fit".length + compressed.length + 10); // central method
    assert.equal(zipEntries(zip)[0].extract().toString(), "plain");
    assert.equal(zipEntries(deflated)[0].extract().toString(), body.toString());
    const bogus = storedZip([["odd.fit", "data"]]);
    bogus.writeUInt16LE(9, 30 + "odd.fit".length + 4 + 10);
    assert.throws(() => zipEntries(bogus)[0].extract(), /unsupported ZIP compression/);
    assert.throws(() => zipEntries(Buffer.from("not zipped, definitely not")), /not a ZIP/);
});

test("decodeSource reads a real FIT export end to end", async () => {
    const { decodeSource } = await import("./report-fit.js");
    const { buildFit, workout } = await import("./synthetic-workout.js");
    withTempDir((root) => {
        const source = join(root, "activity.fit");
        buildFit(workout(), source);
        const report = decodeSource(source);
        assert.equal(report.records.length, 50);
        assert.equal(report.summary.sets, 2);
        assert.equal(report.summary.equipment, "Clubs: 2 x 4 kg");
    });
});

test("main derives the default output path", () => {
    const fit = makeFit({ sessionMesgs: [{ startTime: START, totalElapsedTime: 10, totalTimerTime: 10 }] });
    withTempDir((root) => {
        const source = join(root, "activity.fit");
        writeFileSync(source, "placeholder");
        const original = process.stdout.write;
        process.stdout.write = () => true;
        try {
            assert.equal(main([source], () => collect(fit)), 0);
        } finally {
            process.stdout.write = original;
        }
        assert.ok(readFileSync(join(root, "activity-report.html"), "utf8").includes("Mace &amp; Clubs"));
    });
});

test("main rejects missing or extra arguments", () => {
    assert.throws(() => main([], () => null), /usage:/);
    assert.throws(() => main(["a.fit", "b.fit"], () => null), /unexpected argument/);
});

test("main writes report", () => {
    const fit = makeFit({
        sessionMesgs: [{ startTime: START, totalElapsedTime: 10,
                         totalTimerTime: 10, avgHeartRate: 80, maxHeartRate: 90,
                         dev: { total_sets: 1 } }],
        lapMesgs: [{ startTime: START, totalElapsedTime: 10,
                     dev: { phase: 1, set_number: 1, movement_type: 0, working_side: 3, set_smoothness: 60 } }],
        recordMesgs: [{ timestamp: START, heartRate: 80,
                        dev: { accel_rms: 1000, accel_peak: 2000, accel_zc: 4 } }],
    });
    withTempDir((root) => {
        const source = join(root, "activity.fit");
        const output = join(root, "report.html");
        writeFileSync(source, "placeholder");
        const written = [];
        const original = process.stdout.write;
        process.stdout.write = (chunk) => {
            written.push(String(chunk));
            return true;
        };
        let result;
        try {
            result = main([source, "-o", output], () => collect(fit));
        } finally {
            process.stdout.write = original;
        }
        assert.equal(result, 0);
        assert.ok(readFileSync(output, "utf8").includes("Mace &amp; Clubs"));
        assert.ok(written.join("").includes(output));
    });
});
