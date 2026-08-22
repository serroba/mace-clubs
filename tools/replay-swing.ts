#!/usr/bin/env node
// Builds a local, self-contained HTML replay of a calibration recording
// (needs "Swing calibration logging" / swingDebugEnabled on) from its raw
// accel magnitude and per-axis gyro streams, for visually inspecting exactly
// what happened around a swing the on-device counter missed or double-counted.
//
// Usage:
//     node --experimental-strip-types tools/replay-swing.ts activity.fit
//     node --experimental-strip-types tools/replay-swing.ts garmin-export.zip -o replay.html
//
// What this reconstructs, and what it can't:
// - Rotation is real: the raw per-axis gyro (deg/s) is integrated into
//   cumulative roll/pitch/yaw for the orientation indicator. It drifts over
//   the length of a set (no drift correction), so treat it as a visual
//   reference for HOW the wrist rotated, not a precise absolute pose.
// - Intensity is real: the raw accel magnitude (25Hz) is the true recorded
//   waveform, not an aggregate.
// - Position/translation is NOT reconstructed - that needs per-axis
//   accelerometer data (only captured as combined magnitude here) plus
//   proper sensor fusion, which is out of scope and not reliable at this
//   scale anyway.
// - The counter replay reruns the exact on-device threshold/debounce/
//   refractory logic (see SwingCounter.mc) against the raw waveform, so
//   "counted"/"rejected" markers match what actually happened on the watch.
//
// Everything runs locally; nothing is uploaded anywhere.

import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { collect } from "./report-fit.ts";
import {
    type DecodedFit,
    dateField,
    fieldValue,
    fitPath,
    messagesOf,
    readFit,
    timestampSeconds,
} from "./fit-io.ts";
import { type Report } from "./report-types.ts";

const ACCEL_SAMPLE_RATE_HZ = 25;
const GYRO_STRIDE = 2;
// Mirrors SwingCounter.mc's constants - keep these in sync with that file,
// or the replay stops reflecting what the watch actually does. This is the
// tuned default (SwingCounter.MACE_HIGH_MG); the real on-watch threshold is
// user-adjustable (swingThresholdMg), which a replay from a real recording
// has no way to know - see decodeReplay's mace note.
const MACE_HIGH_MG = 1700;
const MACE_LOW_MG = 1300;
const MACE_MIN_GAP_SAMPLES = 63;
const MACE_DEBOUNCE_SAMPLES = 4;
const DEFAULT_HIGH_MG = 1800;
const DEFAULT_LOW_MG = 1300;
const DEFAULT_MIN_GAP_SAMPLES = 25;
const DEFAULT_DEBOUNCE_SAMPLES = 1;

export interface ReplayLap {
    start: number;
    end: number;
    phase: string;
    set: number;
}

export interface ReplayEvent {
    t: number;
    reason: "debounce" | "refractory";
}

export interface ReplayPayload {
    title: string;
    subtitle: string;
    duration: number;
    laps: ReplayLap[];
    accel: [number, number][];
    gyro: [number, number, number, number][];
    orientation: [number, number, number, number][];
    onDeviceEvents: number[];
    counted: number[];
    rejected: ReplayEvent[];
}

// this device's real limit (see FitFields.createSwingDebugFields): a short
// final second before a phase boundary can genuinely end early, so a
// trailing zero magnitude - never physically reachable otherwise (gravity
// alone reads ~1000mg) - is an unambiguous pad sentinel, not real data.
function trimPad(samples: number[]): number[] {
    const out = [...samples];
    while (out.length > 0 && out[out.length - 1] === 0) {
        out.pop();
    }
    return out;
}

function arrayField(fit: DecodedFit, mesg: Parameters<typeof fieldValue>[1], name: string): number[] {
    const value = fieldValue(fit, mesg, name);
    const out: number[] = [];
    if (Array.isArray(value)) {
        for (const entry of value) {
            if (typeof entry === "number") {
                out.push(entry);
            }
        }
    }
    return out;
}

// Matches collect()'s own origin exactly (min of every lap start and record
// timestamp), so the raw streams built here line up with report.laps.
export function computeOrigin(fit: DecodedFit): number {
    const lapStarts = messagesOf(fit, "lapMesgs")
        .map((lap) => timestampSeconds(dateField(fit, lap, "start_time")))
        .filter((value): value is number => value !== null);
    const recordTimes = messagesOf(fit, "recordMesgs")
        .map((record) => timestampSeconds(dateField(fit, record, "timestamp")))
        .filter((value): value is number => value !== null);
    const all = [...lapStarts, ...recordTimes];
    return all.length > 0 ? Math.min(...all) : 0;
}

export function extractAccel(fit: DecodedFit, origin: number): [number, number][] {
    const out: [number, number][] = [];
    for (const record of messagesOf(fit, "recordMesgs")) {
        const at = timestampSeconds(dateField(fit, record, "timestamp"));
        if (at === null) {
            continue;
        }
        const combined = trimPad([
            ...arrayField(fit, record, "accel_mag_a"),
            ...arrayField(fit, record, "accel_mag_b"),
        ]);
        combined.forEach((mg, i) => out.push([at - origin + i / ACCEL_SAMPLE_RATE_HZ, mg]));
    }
    return out;
}

function extractGyro(fit: DecodedFit, origin: number): [number, number, number, number][] {
    const out: [number, number, number, number][] = [];
    for (const record of messagesOf(fit, "recordMesgs")) {
        const at = timestampSeconds(dateField(fit, record, "timestamp"));
        if (at === null) {
            continue;
        }
        const x = arrayField(fit, record, "gyro_x");
        const y = arrayField(fit, record, "gyro_y");
        const z = arrayField(fit, record, "gyro_z");
        const n = Math.min(x.length, y.length, z.length);
        for (let i = 0; i < n; i++) {
            out.push([at - origin + (i * GYRO_STRIDE) / ACCEL_SAMPLE_RATE_HZ, x[i] ?? 0, y[i] ?? 0, z[i] ?? 0]);
        }
    }
    return out;
}

// Simple rectangular integration of angular velocity into cumulative
// roll/pitch/yaw. No drift correction - fine for a visual replay of a single
// set, not a real dead-reckoning pose estimate. dt uses each sample's actual
// gap to its predecessor rather than assuming perfectly uniform spacing.
function integrateOrientation(gyro: readonly [number, number, number, number][]): [number, number, number, number][] {
    const out: [number, number, number, number][] = [];
    let roll = 0;
    let pitch = 0;
    let yaw = 0;
    let previousT: number | null = null;
    for (const [t, x, y, z] of gyro) {
        const dt = previousT === null ? 0 : Math.max(0, t - previousT);
        roll += x * dt;
        pitch += y * dt;
        yaw += z * dt;
        out.push([t, roll, pitch, yaw]);
        previousT = t;
    }
    return out;
}

export function replayCounter(
    accel: readonly [number, number][],
    highMg: number,
    lowMg: number,
    minGapSamples: number,
    debounceSamples: number,
): { counted: number[]; rejected: ReplayEvent[] } {
    let armed = true;
    let sinceLast = minGapSamples;
    let aboveStreak = 0;
    let belowStreak = 0;
    const counted: number[] = [];
    const rejected: ReplayEvent[] = [];
    for (const [t, mg] of accel) {
        if (sinceLast < minGapSamples) {
            sinceLast++;
        }
        if (armed) {
            if (mg >= highMg) {
                aboveStreak++;
                if (sinceLast >= minGapSamples && aboveStreak >= debounceSamples) {
                    counted.push(t);
                    armed = false;
                    sinceLast = 0;
                    aboveStreak = 0;
                    belowStreak = 0;
                } else if (aboveStreak === debounceSamples) {
                    rejected.push({ t, reason: "refractory" });
                }
            } else {
                if (aboveStreak > 0 && aboveStreak < debounceSamples) {
                    rejected.push({ t, reason: "debounce" });
                }
                aboveStreak = 0;
            }
        } else if (mg <= lowMg) {
            belowStreak++;
            if (belowStreak >= debounceSamples) {
                armed = true;
                belowStreak = 0;
            }
        } else {
            belowStreak = 0;
        }
    }
    return { counted, rejected };
}

export function buildPayload(fit: DecodedFit, report: Report): ReplayPayload {
    const origin = computeOrigin(fit);
    const accel = extractAccel(fit, origin);
    const gyro = extractGyro(fit, origin);
    const orientation = integrateOrientation(gyro);
    const isMace = (report.summary.equipment ?? "").toLowerCase().includes("mace");
    const { counted, rejected } = replayCounter(
        accel,
        isMace ? MACE_HIGH_MG : DEFAULT_HIGH_MG,
        isMace ? MACE_LOW_MG : DEFAULT_LOW_MG,
        isMace ? MACE_MIN_GAP_SAMPLES : DEFAULT_MIN_GAP_SAMPLES,
        isMace ? MACE_DEBOUNCE_SAMPLES : DEFAULT_DEBOUNCE_SAMPLES,
    );
    const onDeviceEvents = report.records.filter((r) => r.swing_event === 1).map((r) => r.t);
    const laps: ReplayLap[] = report.laps.map((lap) => ({
        start: lap.start ?? 0,
        end: lap.end ?? 0,
        phase: lap.phase ?? "rest",
        set: lap.set ?? 0,
    }));
    const subtitle = [report.summary.date, report.summary.equipment, report.summary.movement]
        .filter(Boolean).join(" · ");
    return {
        title: "Mace & Clubs · swing replay",
        subtitle,
        duration: report.summary.elapsed ?? (accel.at(-1)?.[0] ?? 0),
        laps,
        accel,
        gyro,
        orientation,
        onDeviceEvents,
        counted,
        rejected,
    };
}

export function decodeReplay(source: string): ReplayPayload {
    const temporary = mkdtempSync(join(tmpdir(), "mace-clubs-replay-"));
    try {
        const fit = readFit(readFileSync(fitPath(source, temporary)));
        const report = collect(fit);
        return buildPayload(fit, report);
    } finally {
        rmSync(temporary, { recursive: true, force: true });
    }
}

const TEMPLATE_PATH = fileURLToPath(new URL("replay-template.html", import.meta.url));

export function render(payload: ReplayPayload): string {
    return readFileSync(TEMPLATE_PATH, "utf8")
        .split("__TITLE__").join(payload.title)
        .split("__PAYLOAD__").join(JSON.stringify(payload));
}

interface CliArgs {
    source: string;
    output: string | null;
}

function parseArgs(argv: readonly string[]): CliArgs {
    let source: string | null = null;
    let output: string | null = null;
    for (let index = 0; index < argv.length; index++) {
        const argument = argv[index];
        if (argument === "-o" || argument === "--output") {
            output = argv[++index] ?? null;
        } else if (source === null && argument !== undefined) {
            source = argument;
        } else {
            throw new Error(`unexpected argument: ${String(argument)}`);
        }
    }
    if (source === null) {
        throw new Error("usage: replay-swing.ts SOURCE [-o OUTPUT]");
    }
    return { source, output };
}

export function main(
    argv: readonly string[] = process.argv.slice(2),
    loader: (source: string) => ReplayPayload = decodeReplay,
): number {
    const args = parseArgs(argv);
    const stem = basename(args.source, extname(args.source));
    const output = args.output ?? join(dirname(args.source), `${stem}-replay.html`);
    const payload = loader(args.source);
    if (payload.accel.length === 0) {
        console.error(
            "no accel_mag_a/accel_mag_b data found - record with "
            + "\"Swing calibration logging\" (swingDebugEnabled) turned on",
        );
        return 1;
    }
    writeFileSync(output, render(payload), "utf8");
    console.log(resolve(output));
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
