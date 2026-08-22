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
//     node --experimental-strip-types tools/analyze-fit.ts path/to/activity.fit [more.fit ...]
//
// Everything runs locally; nothing is uploaded anywhere.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import {
    type DecodedFit,
    dateField,
    fieldValue,
    messagesOf,
    numberField,
    readFit,
    timestampSeconds,
} from "./fit-io.ts";

const MOVEMENT_LABELS: Readonly<Record<number, string>> = {
    0: "360",
    1: "10-to-2",
    2: "Mill",
    3: "Shield cast",
    4: "Flow / other",
    5: "Reverse mill",
    6: "Bullwhip",
};
const SIDE_LABELS: Readonly<Record<number, string>> = {
    0: "Left", 1: "Right", 2: "Alternating", 3: "Two-handed",
};
const EQUIPMENT_LABELS: Readonly<Record<number, string>> = { 0: "Mace", 1: "Clubs", 2: "Bulava" };

// Threshold sweep for SwingCounter calibration (milli-g). The shipped
// defaults are HIGH_MG=1800 / LOW_MG=1300.
const SWEEP_MG = [1200, 1400, 1600, 1800, 2000, 2200, 2500, 3000];

function display(value: unknown): string {
    if (value instanceof Date) {
        return value.toISOString();
    }
    if (Array.isArray(value)) {
        return value.map(display).join(",");
    }
    switch (typeof value) {
        case "string":
            return value;
        case "number":
        case "bigint":
        case "boolean":
            return String(value);
        default:
            return "-";
    }
}

function printSession(fit: DecodedFit): void {
    // The store numbers each upload; sideloads report the developer's own
    // build. Either way it identifies which app build recorded the file.
    for (const devId of messagesOf(fit, "developerDataIdMesgs")) {
        const version = fieldValue(fit, devId, "application_version");
        if (version !== null) {
            console.log(`app build (application_version): ${display(version)}`);
        }
    }
    for (const session of messagesOf(fit, "sessionMesgs")) {
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
            const value = fieldValue(fit, session, name);
            if (value === null) {
                continue;
            }
            const shown = name === "implement_type" && typeof value === "number"
                ? (EQUIPMENT_LABELS[value] ?? display(value))
                : display(value);
            console.log(`  ${name}: ${shown}`);
        }
    }
}

// Return [start, end, isWork] per lap.
//
// Newer app versions write an explicit phase developer field; older ones
// only carry set_number, where work laps are 1-based and rest laps zero.
function lapWindows(fit: DecodedFit): [number, number, boolean][] {
    const windows: [number, number, boolean][] = [];
    for (const lap of messagesOf(fit, "lapMesgs")) {
        const start = timestampSeconds(dateField(fit, lap, "start_time"));
        const elapsed = numberField(fit, lap, "total_elapsed_time");
        if (start === null || elapsed === null) {
            continue;
        }
        const phase = numberField(fit, lap, "phase");
        const isWork = phase !== null ? phase === 1 : numberField(fit, lap, "set_number", 0) > 0;
        windows.push([start, start + elapsed, isWork]);
    }
    return windows;
}

function printLaps(fit: DecodedFit): void {
    console.log("== Laps ==");
    const widths = [3, 4, 5, 6, 13, 11, 7, 7, 7];
    const row = (values: readonly string[]): string =>
        `  ${values.map((value, index) => value.padStart(widths[index] ?? 0)).join(" ")}`;
    console.log(row(["lap", "set", "phase", "dur_s", "movement", "side", "weight", "smooth", "swings"]));
    messagesOf(fit, "lapMesgs").forEach((lap, index) => {
        const phase = numberField(fit, lap, "phase");
        const movement = numberField(fit, lap, "movement_type");
        const side = numberField(fit, lap, "working_side");
        console.log(row([
            String(index + 1),
            display(fieldValue(fit, lap, "set_number")),
            phase === 1 ? "work" : phase === 0 ? "rest" : "-",
            display(fieldValue(fit, lap, "phase_duration")),
            (movement !== null ? MOVEMENT_LABELS[movement] : undefined) ?? "-",
            (side !== null ? SIDE_LABELS[side] : undefined) ?? "-",
            display(fieldValue(fit, lap, "implement_weight")),
            display(fieldValue(fit, lap, "set_smoothness")),
            display(fieldValue(fit, lap, "swing_count")),
        ]));
    });
}

// Threshold sweep over per-second accel_peak, split work vs rest.
function analyzeMotion(fit: DecodedFit): void {
    const windows = lapWindows(fit);
    const peaks: Record<"work" | "rest", number[]> = { work: [], rest: [] };
    const troughs: Record<"work" | "rest", number[]> = { work: [], rest: [] };
    for (const record of messagesOf(fit, "recordMesgs")) {
        const peak = numberField(fit, record, "accel_peak");
        const min = numberField(fit, record, "accel_min");
        const at = timestampSeconds(dateField(fit, record, "timestamp"));
        if (peak === null || at === null) {
            continue;
        }
        let bucket: "work" | "rest" = "rest";
        for (const [start, end, isWork] of windows) {
            if (start <= at && at <= end) {
                bucket = isWork ? "work" : "rest";
                break;
            }
        }
        peaks[bucket].push(peak);
        if (min !== null) {
            troughs[bucket].push(min);
        }
    }

    if (peaks.work.length === 0 && peaks.rest.length === 0) {
        console.log("== Motion ==");
        console.log("  no accel features found (record with Motion logging ON to calibrate)");
        return;
    }

    console.log("== Motion (per-second accel_peak, mg) ==");
    for (const bucket of ["work", "rest"] as const) {
        const values = [...peaks[bucket]].sort((a, b) => a - b);
        const mid = values[Math.floor(values.length / 2)];
        const p90 = values[Math.trunc(values.length * 0.9)];
        const first = values[0];
        const last = values[values.length - 1];
        if (first === undefined || last === undefined || mid === undefined || p90 === undefined) {
            console.log(`  ${bucket}: no samples`);
            continue;
        }
        console.log(
            `  ${bucket}: n=${String(values.length)} min=${String(first)} median=${String(mid)} `
            + `p90=${String(p90)} max=${String(last)}`);
    }

    console.log("  threshold sweep (% of seconds with peak >= threshold):");
    console.log(`  ${"mg".padStart(9)} ${"work".padStart(7)} ${"rest".padStart(7)}`);
    for (const threshold of SWEEP_MG) {
        const share = (bucket: "work" | "rest"): number => {
            const values = peaks[bucket];
            return values.length > 0
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

    if (troughs.work.length === 0 && troughs.rest.length === 0) {
        return;
    }
    console.log("\n== Motion trough (per-second accel_min, mg; needs swingDebugEnabled) ==");
    for (const bucket of ["work", "rest"] as const) {
        const values = [...troughs[bucket]].sort((a, b) => a - b);
        const mid = values[Math.floor(values.length / 2)];
        const p10 = values[Math.trunc(values.length * 0.1)];
        const first = values[0];
        const last = values[values.length - 1];
        if (first === undefined || last === undefined || mid === undefined || p10 === undefined) {
            console.log(`  ${bucket}: no samples`);
            continue;
        }
        console.log(
            `  ${bucket}: n=${String(values.length)} min=${String(first)} p10=${String(p10)} `
            + `median=${String(mid)} max=${String(last)}`);
    }
    console.log("  re-arm sweep (% of seconds whose trough clears the floor, i.e. min <= threshold):");
    console.log(`  ${"mg".padStart(9)} ${"work".padStart(7)} ${"rest".padStart(7)}`);
    for (const threshold of SWEEP_MG) {
        const share = (bucket: "work" | "rest"): number => {
            const values = troughs[bucket];
            return values.length > 0
                ? (100 * values.filter((value) => value <= threshold).length) / values.length
                : 0;
        };
        const marker = threshold === 1300 ? " <- shipped LOW_MG" : "";
        console.log(
            `  ${String(threshold).padStart(9)} ${share("work").toFixed(1).padStart(6)}% `
            + `${share("rest").toFixed(1).padStart(6)}%${marker}`);
    }
    console.log(
        "  A low share in the work column means most seconds never dip below\n"
        + "  LOW_MG - the counter can get stuck unarmed until a lucky deep dip.");
}

export function main(paths: readonly string[] = process.argv.slice(2)): number {
    if (paths.length === 0) {
        console.error("usage: analyze-fit.ts activity.fit [more.fit ...]");
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
