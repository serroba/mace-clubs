#!/usr/bin/env node
// Generate a private, self-contained workout report from a Garmin FIT export.
//
// Usage:
//     node tools/report-fit.js activity.fit
//     node tools/report-fit.js garmin-export.zip -o report.html
//
// The report never uploads data. It visualizes the app's per-second motion
// features alongside Garmin heart rate and the work/rest laps recorded by the app.

import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { analyze } from "./analyze-workout.js";
import { fieldValue, fitPath, messagesOf, pythonRound, readFit, timestampSeconds } from "./fit-io.js";
import { validate } from "./validate-workout.js";

const MOVEMENTS = {
    0: "360",
    1: "10-to-2",
    2: "Mill",
    3: "Shield cast",
    4: "Flow / other",
    5: "Reverse mill",
    6: "Bullwhip",
    7: "Combo",
};
const SIDES = { 0: "Left", 1: "Right", 2: "Alternating", 3: "Two-handed" };
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function formatDate(date) {
    return `${String(date.getUTCDate()).padStart(2, "0")} ${MONTHS[date.getUTCMonth()]} ${date.getUTCFullYear()}`;
}

function escapeHtml(text) {
    return text
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#x27;");
}

export function collect(fit) {
    const sessions = messagesOf(fit, "session");
    if (sessions.length === 0) {
        throw new Error("FIT file contains no session");
    }
    const session = sessions[0];
    const sessionStart = fieldValue(fit, session, "start_time");
    const activities = messagesOf(fit, "activity");
    const localStart = activities.length > 0 ? fieldValue(fit, activities[0], "local_timestamp") : null;
    let equipment = null;
    const sessionValues = [...Object.values(session), ...Object.values(session.developerFields ?? {})];
    for (const candidate of sessionValues) {
        if (typeof candidate === "string"
            && ["mace", "club", "bulava"].some((name) => candidate.toLowerCase().includes(name))) {
            equipment = candidate;
            break;
        }
    }

    const rawLaps = [];
    messagesOf(fit, "lap").forEach((lap, index) => {
        const start = timestampSeconds(fieldValue(fit, lap, "start_time"));
        const elapsed = fieldValue(fit, lap, "total_elapsed_time");
        if (start === null || elapsed === null) {
            return;
        }
        const phase = fieldValue(fit, lap, "phase");
        const setNumber = Math.trunc(fieldValue(fit, lap, "set_number", 0));
        const isWork = phase !== null ? phase === 1 : setNumber > 0;
        rawLaps.push({
            lap: index + 1,
            start_abs: start,
            end_abs: start + Number(elapsed),
            set: setNumber,
            phase: isWork ? "work" : "rest",
            duration: pythonRound(Number(fieldValue(fit, lap, "phase_duration", elapsed)), 1),
            elapsed: pythonRound(Number(elapsed), 1),
            movement: MOVEMENTS[fieldValue(fit, lap, "movement_type")] ?? "Unknown",
            side: SIDES[fieldValue(fit, lap, "working_side")] ?? "Unknown",
            weight: fieldValue(fit, lap, "implement_weight"),
            smoothness: fieldValue(fit, lap, "set_smoothness"),
            swings: fieldValue(fit, lap, "swing_count"),
            exposure: fieldValue(fit, lap, "motion_exposure"),
            motion_peak: fieldValue(fit, lap, "motion_peak"),
            active_seconds: fieldValue(fit, lap, "active_seconds"),
            weight_volume: fieldValue(fit, lap, "weight_volume"),
        });
    });

    const records = [];
    for (const record of messagesOf(fit, "record")) {
        const at = timestampSeconds(fieldValue(fit, record, "timestamp"));
        if (at === null) {
            continue;
        }
        const point = {
            at_abs: at,
            hr: fieldValue(fit, record, "heart_rate"),
            rms: fieldValue(fit, record, "accel_rms"),
            peak: fieldValue(fit, record, "accel_peak"),
            zc: fieldValue(fit, record, "accel_zc"),
            swing_total: fieldValue(fit, record, "swing_total"),
            swing_event: fieldValue(fit, record, "swing_event"),
            swing_cadence: fieldValue(fit, record, "swing_cadence"),
            smoothness_score: fieldValue(fit, record, "smoothness_score"),
        };
        if (["hr", "rms", "peak", "zc", "swing_total", "swing_event", "swing_cadence", "smoothness_score"]
            .some((key) => point[key] !== null)) {
            records.push(point);
        }
    }

    const starts = [...rawLaps.map((lap) => lap.start_abs), ...records.map((point) => point.at_abs)];
    const origin = starts.length > 0 ? Math.min(...starts) : 0;
    for (const lap of rawLaps) {
        lap.start = pythonRound(lap.start_abs - origin, 3);
        lap.end = pythonRound(lap.end_abs - origin, 3);
        delete lap.start_abs;
        delete lap.end_abs;
    }
    for (const point of records) {
        point.t = pythonRound(point.at_abs - origin, 3);
        delete point.at_abs;
    }

    const workLaps = rawLaps.filter((lap) => lap.phase === "work" && lap.set > 0);
    const validSets = workLaps.filter((lap) => lap.elapsed >= 10);
    const movement = workLaps.find((lap) => lap.movement !== "Unknown")?.movement ?? "Unknown";
    const side = workLaps.find((lap) => lap.side !== "Unknown")?.side ?? "Unknown";
    const dateSource = localStart instanceof Date ? localStart : sessionStart;

    return {
        summary: {
            elapsed: pythonRound(Number(fieldValue(fit, session, "total_elapsed_time", 0)), 1),
            timer: pythonRound(Number(fieldValue(fit, session, "total_timer_time", 0)), 1),
            avg_hr: fieldValue(fit, session, "avg_heart_rate"),
            max_hr: fieldValue(fit, session, "max_heart_rate"),
            sets: fieldValue(fit, session, "total_sets", workLaps.length),
            movement,
            side,
            equipment,
            date: dateSource instanceof Date ? formatDate(dateSource) : null,
            work_seconds: pythonRound(workLaps.reduce((total, lap) => total + lap.elapsed, 0), 1),
            rest_seconds: pythonRound(
                rawLaps.filter((lap) => lap.phase === "rest").reduce((total, lap) => total + lap.elapsed, 0), 1),
            valid_sets: validSets.length,
        },
        laps: rawLaps,
        records,
    };
}

const TEMPLATE_PATH = fileURLToPath(new URL("report-template.html", import.meta.url));

export function render(report, title) {
    const enriched = {
        ...report,
        quality: report.quality ?? validate(report),
        analysis: report.analysis ?? analyze(report),
    };
    return readFileSync(TEMPLATE_PATH, "utf8")
        .split("__TITLE__").join(escapeHtml(title))
        .split("__PAYLOAD__").join(JSON.stringify(enriched));
}

function parseArgs(argv) {
    const args = { source: null, output: null };
    for (let index = 0; index < argv.length; index++) {
        const argument = argv[index];
        if (argument === "-o" || argument === "--output") {
            args.output = argv[++index];
        } else if (args.source === null) {
            args.source = argument;
        } else {
            throw new Error(`unexpected argument: ${argument}`);
        }
    }
    if (args.source === null) {
        throw new Error("usage: report-fit.js SOURCE [-o OUTPUT]");
    }
    return args;
}

export function decodeSource(source) {
    const temporary = mkdtempSync(join(tmpdir(), "mace-clubs-fit-"));
    try {
        return collect(readFit(readFileSync(fitPath(source, temporary))));
    } finally {
        rmSync(temporary, { recursive: true, force: true });
    }
}

export function main(argv = process.argv.slice(2), loader = decodeSource) {
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
