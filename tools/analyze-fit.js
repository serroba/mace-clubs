#!/usr/bin/env node
// Offline analysis of Mace & Clubs FIT activities.
//
// Reads the raw FIT exported from Garmin Connect ("Export Original") or copied
// from GARMIN/Activity on the watch, prints the app's developer fields per
// session and per lap, and — when the activity was recorded with the Motion
// logging setting on — sweeps swing-detection thresholds over the per-second
// accelerometer features to ground SwingCounter.HIGH_MG in real data.
//
// Usage:
//     node tools/analyze-fit.js path/to/activity.fit [more.fit ...]
//
// Everything runs locally; nothing is uploaded anywhere.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { fieldValue, messagesOf, readFit, timestampSeconds } from "./fit-io.js";

const MOVEMENT_LABELS = {
    0: "360",
    1: "10-to-2",
    2: "Mill",
    3: "Shield cast",
    4: "Flow / other",
    5: "Reverse mill",
    6: "Bullwhip",
};
const SIDE_LABELS = { 0: "Left", 1: "Right", 2: "Alternating", 3: "Two-handed" };
const EQUIPMENT_LABELS = { 0: "Mace", 1: "Clubs", 2: "Bulava" };

// Threshold sweep for SwingCounter calibration (milli-g). The shipped
// defaults are HIGH_MG=1800 / LOW_MG=1300.
const SWEEP_MG = [1200, 1400, 1600, 1800, 2000, 2200, 2500, 3000];

function printSession(fit) {
    // The store numbers each upload; sideloads report the developer's own
    // build. Either way it identifies which app build recorded the file.
    for (const devId of messagesOf(fit, "developer_data_id")) {
        const version = fieldValue(fit, devId, "application_version");
        if (version !== null) {
            console.log(`app build (application_version): ${version}`);
        }
    }
    for (const session of messagesOf(fit, "session")) {
        console.log("== Session ==");
        for (const name of [
            "sport",
            "sub_sport",
            "total_elapsed_time",
            "total_timer_time",
            "avg_heart_rate",
            "max_heart_rate",
            "total_sets",
            "total_swings",
            "battery_used",
            "implement_type",
            "implement_count",
            "implement_weight",
            "watch_wrist",
        ]) {
            let value = fieldValue(fit, session, name);
            if (value === null) {
                continue;
            }
            if (name === "implement_type") {
                value = EQUIPMENT_LABELS[value] ?? value;
            }
            console.log(`  ${name}: ${value}`);
        }
    }
}

// Return [start, end, isWork] per lap.
//
// Newer app versions write an explicit phase developer field; older ones
// only carry set_number, where work laps are 1-based and rest laps zero.
function lapWindows(fit) {
    const windows = [];
    for (const lap of messagesOf(fit, "lap")) {
        const start = timestampSeconds(fieldValue(fit, lap, "start_time"));
        const elapsed = fieldValue(fit, lap, "total_elapsed_time");
        if (start === null || elapsed === null) {
            continue;
        }
        const phase = fieldValue(fit, lap, "phase");
        const isWork = phase !== null ? phase === 1 : (fieldValue(fit, lap, "set_number") ?? 0) > 0;
        windows.push([start, start + Number(elapsed), isWork]);
    }
    return windows;
}

function printLaps(fit) {
    console.log("== Laps ==");
    const row = (values) => {
        const widths = [3, 4, 5, 6, 13, 11, 7, 7, 7];
        return `  ${values.map((value, index) => String(value).padStart(widths[index])).join(" ")}`;
    };
    console.log(row(["lap", "set", "phase", "dur_s", "movement", "side", "weight", "smooth", "swings"]));
    messagesOf(fit, "lap").forEach((lap, index) => {
        const phase = fieldValue(fit, lap, "phase");
        console.log(row([
            index + 1,
            fieldValue(fit, lap, "set_number", "-"),
            phase === 1 ? "work" : phase === 0 ? "rest" : "-",
            fieldValue(fit, lap, "phase_duration", "-"),
            MOVEMENT_LABELS[fieldValue(fit, lap, "movement_type")] ?? "-",
            SIDE_LABELS[fieldValue(fit, lap, "working_side")] ?? "-",
            fieldValue(fit, lap, "implement_weight", "-"),
            fieldValue(fit, lap, "set_smoothness", "-"),
            fieldValue(fit, lap, "swing_count", "-"),
        ]));
    });
}

// Threshold sweep over per-second accel_peak, split work vs rest.
function analyzeMotion(fit) {
    const windows = lapWindows(fit);
    const peaks = { work: [], rest: [] };
    for (const record of messagesOf(fit, "record")) {
        const peak = fieldValue(fit, record, "accel_peak");
        const at = timestampSeconds(fieldValue(fit, record, "timestamp"));
        if (peak === null || at === null) {
            continue;
        }
        let bucket = "rest";
        for (const [start, end, isWork] of windows) {
            if (start <= at && at <= end) {
                bucket = isWork ? "work" : "rest";
                break;
            }
        }
        peaks[bucket].push(peak);
    }

    if (peaks.work.length === 0 && peaks.rest.length === 0) {
        console.log("== Motion ==");
        console.log("  no accel features found (record with Motion logging ON to calibrate)");
        return;
    }

    console.log("== Motion (per-second accel_peak, mg) ==");
    for (const bucket of ["work", "rest"]) {
        const values = [...peaks[bucket]].sort((a, b) => a - b);
        if (values.length === 0) {
            console.log(`  ${bucket}: no samples`);
            continue;
        }
        const mid = values[Math.floor(values.length / 2)];
        const p90 = values[Math.trunc(values.length * 0.9)];
        console.log(
            `  ${bucket}: n=${values.length} min=${values[0]} median=${mid} `
            + `p90=${p90} max=${values[values.length - 1]}`);
    }

    console.log("  threshold sweep (% of seconds with peak >= threshold):");
    console.log(`  ${"mg".padStart(9)} ${"work".padStart(7)} ${"rest".padStart(7)}`);
    for (const threshold of SWEEP_MG) {
        const share = (bucket) => {
            const values = peaks[bucket];
            return values.length
                ? (100 * values.filter((value) => value >= threshold).length) / values.length
                : 0;
        };
        const marker = threshold === 1800 ? " <- shipped HIGH_MG" : "";
        console.log(
            `  ${String(threshold).padStart(9)} ${share("work").toFixed(1).padStart(6)}% `
            + `${share("rest").toFixed(1).padStart(6)}%${marker}`);
    }
    console.log(
        "  A good HIGH_MG keeps the work column near your real swing cadence\n"
        + "  (one crossing per swing-second) while the rest column stays ~0.");
}

export function main(paths = process.argv.slice(2)) {
    if (paths.length === 0) {
        console.error("usage: analyze-fit.js activity.fit [more.fit ...]");
        return 2;
    }
    for (const path of paths) {
        console.log(`\n### ${path}`);
        const fit = readFit(readFileSync(path));
        printSession(fit);
        printLaps(fit);
        analyzeMotion(fit);
    }
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
