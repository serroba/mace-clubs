#!/usr/bin/env node
// Generate a private, self-contained workout report from a Garmin FIT export.
//
// Usage:
//     node --experimental-strip-types tools/report-fit.ts activity.fit
//     node --experimental-strip-types tools/report-fit.ts garmin-export.zip -o report.html
//
// The report never uploads data. It visualizes the app's per-second motion
// features alongside Garmin heart rate and the work/rest laps recorded by the app.

import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { analyze } from "./analyze-workout.ts";
import {
    type DecodedFit,
    dateField,
    fitPath,
    messagesOf,
    numberField,
    pythonRound,
    readFit,
    timestampSeconds,
} from "./fit-io.ts";
import { computeOrigin, extractGyro } from "./replay-swing.ts";
import { type Report, type ReportLap, type ReportPoint } from "./report-types.ts";
import { validate } from "./validate-workout.ts";

// [t, x, y, z] deg/s - only present for calibration recordings (swingDebugEnabled).
export type GyroSample = [number, number, number, number];

export interface FullReport extends Report {
    gyro?: GyroSample[];
}

const MOVEMENTS: Readonly<Record<number, string>> = {
    0: "360",
    1: "10-to-2",
    2: "Mill",
    3: "Shield cast",
    4: "Flow / other",
    5: "Reverse mill",
    6: "Bullwhip",
    7: "Combo",
};
const SIDES: Readonly<Record<number, string>> = {
    0: "Left", 1: "Right", 2: "Alternating", 3: "Two-handed",
};
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"] as const;

function formatDate(date: Date): string {
    const month = MONTHS[date.getUTCMonth()] ?? "Jan";
    return `${String(date.getUTCDate()).padStart(2, "0")} ${month} ${String(date.getUTCFullYear())}`;
}

function escapeHtml(text: string): string {
    return text
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#x27;");
}

function labelled(table: Readonly<Record<number, string>>, key: number | null): string {
    return (key !== null ? table[key] : undefined) ?? "Unknown";
}

export function collect(fit: DecodedFit): Report {
    const sessions = messagesOf(fit, "sessionMesgs");
    const session = sessions[0];
    if (session === undefined) {
        throw new Error("FIT file contains no session");
    }
    const sessionStart = dateField(fit, session, "start_time");
    const activity = messagesOf(fit, "activityMesgs")[0];
    const localStart = activity === undefined ? null : dateField(fit, activity, "local_timestamp");
    let equipment: string | null = null;
    const sessionValues: unknown[] = [
        ...Object.values(session as Record<string, unknown>),
        ...Object.values(session.developerFields ?? {}),
    ];
    for (const candidate of sessionValues) {
        if (typeof candidate === "string"
            && ["mace", "club", "bulava"].some((name) => candidate.toLowerCase().includes(name))) {
            equipment = candidate;
            break;
        }
    }

    const rawLaps: { startAbs: number; endAbs: number; lap: ReportLap }[] = [];
    messagesOf(fit, "lapMesgs").forEach((lap, index) => {
        const start = timestampSeconds(dateField(fit, lap, "start_time"));
        const elapsed = numberField(fit, lap, "total_elapsed_time");
        if (start === null || elapsed === null) {
            return;
        }
        const phase = numberField(fit, lap, "phase");
        const setNumber = Math.trunc(numberField(fit, lap, "set_number", 0));
        const isWork = phase !== null ? phase === 1 : setNumber > 0;
        rawLaps.push({
            startAbs: start,
            endAbs: start + elapsed,
            lap: {
                lap: index + 1,
                start: 0,
                end: 0,
                set: setNumber,
                phase: isWork ? "work" : "rest",
                duration: pythonRound(numberField(fit, lap, "phase_duration", elapsed), 1),
                elapsed: pythonRound(elapsed, 1),
                movement: labelled(MOVEMENTS, numberField(fit, lap, "movement_type")),
                side: labelled(SIDES, numberField(fit, lap, "working_side")),
                weight: numberField(fit, lap, "implement_weight"),
                smoothness: numberField(fit, lap, "set_smoothness"),
                swings: numberField(fit, lap, "swing_count"),
                exposure: numberField(fit, lap, "motion_exposure"),
                motion_peak: numberField(fit, lap, "motion_peak"),
                active_seconds: numberField(fit, lap, "active_seconds"),
                weight_volume: numberField(fit, lap, "weight_volume"),
            },
        });
    });

    const rawRecords: { atAbs: number; point: ReportPoint }[] = [];
    for (const record of messagesOf(fit, "recordMesgs")) {
        const at = timestampSeconds(dateField(fit, record, "timestamp"));
        if (at === null) {
            continue;
        }
        const point: ReportPoint = {
            t: 0,
            hr: numberField(fit, record, "heart_rate"),
            rms: numberField(fit, record, "accel_rms"),
            peak: numberField(fit, record, "accel_peak"),
            zc: numberField(fit, record, "accel_zc"),
            swing_total: numberField(fit, record, "swing_total"),
            swing_event: numberField(fit, record, "swing_event"),
            swing_cadence: numberField(fit, record, "swing_cadence"),
            smoothness_score: numberField(fit, record, "smoothness_score"),
        };
        if ([point.hr, point.rms, point.peak, point.zc, point.swing_total,
             point.swing_event, point.swing_cadence, point.smoothness_score]
            .some((value) => value !== null)) {
            rawRecords.push({ atAbs: at, point });
        }
    }

    const starts = [...rawLaps.map((item) => item.startAbs), ...rawRecords.map((item) => item.atAbs)];
    const origin = starts.length > 0 ? Math.min(...starts) : 0;
    const laps = rawLaps.map(({ startAbs, endAbs, lap }) => ({
        ...lap,
        start: pythonRound(startAbs - origin, 3),
        end: pythonRound(endAbs - origin, 3),
    }));
    const records = rawRecords.map(({ atAbs, point }) => ({
        ...point,
        t: pythonRound(atAbs - origin, 3),
    }));

    const workLaps = laps.filter((lap) => lap.phase === "work" && (lap.set ?? 0) > 0);
    const validSets = workLaps.filter((lap) => (lap.elapsed ?? 0) >= 10);
    const movement = workLaps.find((lap) => lap.movement !== "Unknown")?.movement ?? "Unknown";
    const side = workLaps.find((lap) => lap.side !== "Unknown")?.side ?? "Unknown";
    const dateSource = localStart ?? sessionStart;

    return {
        summary: {
            elapsed: pythonRound(numberField(fit, session, "total_elapsed_time", 0), 1),
            timer: pythonRound(numberField(fit, session, "total_timer_time", 0), 1),
            avg_hr: numberField(fit, session, "avg_heart_rate"),
            max_hr: numberField(fit, session, "max_heart_rate"),
            sets: numberField(fit, session, "total_sets", workLaps.length),
            movement,
            side,
            equipment,
            date: dateSource !== null ? formatDate(dateSource) : null,
            work_seconds: pythonRound(workLaps.reduce((total, lap) => total + (lap.elapsed ?? 0), 0), 1),
            rest_seconds: pythonRound(
                laps.filter((lap) => lap.phase === "rest")
                    .reduce((total, lap) => total + (lap.elapsed ?? 0), 0), 1),
            valid_sets: validSets.length,
        },
        laps,
        records,
    };
}

const TEMPLATE_PATH = fileURLToPath(new URL("report-template.html", import.meta.url));

export function render(report: FullReport, title: string): string {
    const enriched: FullReport = {
        ...report,
        quality: report.quality ?? validate(report),
        analysis: report.analysis ?? analyze(report),
    };
    return readFileSync(TEMPLATE_PATH, "utf8")
        .split("__TITLE__").join(escapeHtml(title))
        .split("__PAYLOAD__").join(JSON.stringify(enriched));
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
        throw new Error("usage: report-fit.ts SOURCE [-o OUTPUT]");
    }
    return { source, output };
}

export function decodeSource(source: string): FullReport {
    const temporary = mkdtempSync(join(tmpdir(), "mace-clubs-fit-"));
    try {
        const fit = readFit(readFileSync(fitPath(source, temporary)));
        const report = collect(fit);
        const gyro = extractGyro(fit, computeOrigin(fit));
        return gyro.length > 0 ? { ...report, gyro } : report;
    } finally {
        rmSync(temporary, { recursive: true, force: true });
    }
}

export function main(
    argv: readonly string[] = process.argv.slice(2),
    loader: (source: string) => FullReport = decodeSource,
): number {
    const args = parseArgs(argv);
    const stem = basename(args.source, extname(args.source));
    const output = args.output ?? join(dirname(args.source), `${stem}-report.html`);
    writeFileSync(output, render(loader(args.source), `Mace & Clubs · ${stem}`), "utf8");
    console.log(resolve(output));
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
