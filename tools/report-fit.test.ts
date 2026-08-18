import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { crc32, deflateRawSync } from "node:zlib";

import { type FitMessages, type Mesg } from "@garmin/fitsdk";

import { type DecodedFit, fitPath, timestampSeconds, zipEntries } from "./fit-io.ts";
import { collect, decodeSource, main, render } from "./report-fit.ts";
import { type Report } from "./report-types.ts";
import { buildFit, workout } from "./synthetic-workout.ts";

const START = new Date(Date.UTC(2026, 7, 16));
const DAY = 24 * 3600 * 1000;

// Minimal stored-entry ZIP writer, enough to exercise the extractor.
function storedZip(entries: readonly [string, string | Buffer][]): Buffer {
    const parts: Buffer[] = [];
    const centrals: Buffer[] = [];
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

type FakeMesg = Mesg & Record<string, unknown> & { dev?: Record<string, string | number> };

// Fabricate a readFit()-shaped wrapper; `dev` maps developer field names to values.
function makeFit(kinds: Partial<Record<keyof FitMessages, FakeMesg[]>>): DecodedFit {
    const fieldNames = new Map<number, string>();
    const nameToKey = new Map<string, number>();
    const keyFor = (name: string): number => {
        let key = nameToKey.get(name);
        if (key === undefined) {
            key = nameToKey.size;
            nameToKey.set(name, key);
            fieldNames.set(key, name);
        }
        return key;
    };
    const messages: Record<string, Mesg[]> = {};
    for (const [kind, mesgs] of Object.entries(kinds)) {
        messages[kind] = mesgs.map(({ dev, ...rest }) => (dev === undefined
            ? rest
            : { ...rest,
                developerFields: Object.fromEntries(
                    Object.entries(dev).map(([name, value]) => [keyFor(name), value])) }));
    }
    return { messages, fieldNames, errors: [] };
}

function withTempDir<T>(run: (root: string) => T): T {
    const root = mkdtempSync(join(tmpdir(), "mace-report-"));
    try {
        return run(root);
    } finally {
        rmSync(root, { recursive: true, force: true });
    }
}

function silencingStdout<T>(run: () => T): { result: T; stdout: string } {
    const written: string[] = [];
    const original = process.stdout.write.bind(process.stdout);
    process.stdout.write = (chunk: string | Uint8Array): boolean => {
        written.push(String(chunk));
        return true;
    };
    try {
        return { result: run(), stdout: written.join("") };
    } finally {
        process.stdout.write = original;
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

test("zip extractor inflates deflated entries and rejects other methods", () => {
    const body = Buffer.from("squeezed activity bytes");
    const compressed = deflateRawSync(body);
    const zip = storedZip([["stored.fit", "plain"]]);
    const deflated = storedZip([["packed.fit", compressed]]);
    deflated.writeUInt16LE(8, 30 + "packed.fit".length + compressed.length + 10);
    const storedEntry = zipEntries(zip)[0];
    const deflatedEntry = zipEntries(deflated)[0];
    assert.ok(storedEntry !== undefined && deflatedEntry !== undefined);
    assert.equal(storedEntry.extract().toString(), "plain");
    assert.equal(deflatedEntry.extract().toString(), body.toString());
    const bogus = storedZip([["odd.fit", "data"]]);
    bogus.writeUInt16LE(9, 30 + "odd.fit".length + 4 + 10);
    const bogusEntry = zipEntries(bogus)[0];
    assert.ok(bogusEntry !== undefined);
    assert.throws(() => bogusEntry.extract(), /unsupported ZIP compression/);
    assert.throws(() => zipEntries(Buffer.from("not zipped, definitely not")), /not a ZIP/);
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
    const record = report.records[0];
    assert.ok(record !== undefined);
    assert.equal(report.summary.movement, "Flow / other");
    assert.equal(report.summary.valid_sets, 1);
    assert.equal(report.summary.work_seconds, 35);
    assert.equal(record.t, 1);
    assert.equal(record.swing_total, 1);
    assert.equal(record.swing_event, 1);
    assert.equal(record.swing_cadence, 60);
    assert.equal(record.smoothness_score, 82);
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
    const report: Report = {
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
    for (const expected of [
        "<!doctype html>",
        "Set ${anomalies",
        "Example &lt;activity&gt;",
        "Work</span>",
        "Recording quality",
        'id="quality-score"',
        "set-1",
        '"status":"usable_with_gaps"',
        '"code":"sets.short"',
        '"target":"set-1"',
        "Within-session signals",
        "Set rhythm comparison",
        "Smoothness over time",
        "d.smoothness_score",
        "Swing detected",
        "Synchronized acceleration, swing cadence",
        '"code":"smoothness_drift"',
        "not tendon force",
    ]) {
        assert.ok(rendered.includes(expected), expected);
    }
    assert.ok(!rendered.includes("fetch("));
});

test("decodeSource reads a real FIT export end to end", () => {
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
        const { result } = silencingStdout(() => main([source], () => collect(fit)));
        assert.equal(result, 0);
        assert.ok(readFileSync(join(root, "activity-report.html"), "utf8").includes("Mace &amp; Clubs"));
    });
});

test("main rejects missing or extra arguments", () => {
    const loader = (): Report => ({ summary: {}, laps: [], records: [] });
    assert.throws(() => main([], loader), /usage:/);
    assert.throws(() => main(["a.fit", "b.fit"], loader), /unexpected argument/);
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
        const { result, stdout } = silencingStdout(() => main([source, "-o", output], () => collect(fit)));
        assert.equal(result, 0);
        assert.ok(readFileSync(output, "utf8").includes("Mace &amp; Clubs"));
        assert.ok(stdout.includes(output));
    });
});
