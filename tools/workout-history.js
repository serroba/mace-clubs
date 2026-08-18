#!/usr/bin/env node
// Maintain a private local Workout Inspector history from FIT/ZIP exports.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { pythonRound } from "./fit-io.js";
import { loadReport } from "./validate-workout.js";

const METRICS = {
    duration: "s",
    work_seconds: "s",
    sets: "sets",
    motion_exposure: "mg-s",
    active_seconds: "s",
    weight_volume: "kg-swings",
    motion_peak: "mg",
    smoothness: "score",
};

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function median(values) {
    const sorted = [...values].sort((a, b) => a - b);
    const middle = Math.floor(sorted.length / 2);
    return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

export function metric(laps, name) {
    const values = laps
        .filter((lap) => typeof lap[name] === "number" && lap[name] >= 0)
        .map((lap) => Number(lap[name]));
    if (values.length === 0) {
        return null;
    }
    if (name === "motion_peak") {
        return Math.max(...values);
    }
    if (name === "smoothness") {
        return values.reduce((total, value) => total + value, 0) / values.length;
    }
    return values.reduce((total, value) => total + value, 0);
}

export function summarize(report, identifier, importedAt = null) {
    const work = report.laps.filter((lap) => lap.phase === "work" && (lap.set ?? 0) > 0);
    const metrics = { duration: report.summary.elapsed ?? null, work_seconds: report.summary.work_seconds ?? null, sets: work.length };
    for (const name of Object.keys(METRICS)) {
        if (!(name in metrics)) {
            metrics[name] = metric(work, name);
        }
    }
    return {
        id: identifier,
        imported_at: importedAt ?? new Date().toISOString(),
        date: report.summary.date ?? null,
        movement: report.summary.movement ?? null,
        side: report.summary.side ?? null,
        equipment: report.summary.equipment ?? null,
        sets: work.length,
        duration: report.summary.elapsed ?? null,
        metrics,
    };
}

export function comparisons(entries, minimum = 3, window = 8) {
    if (entries.length === 0) {
        return [];
    }
    const current = entries[entries.length - 1];
    const previous = entries.slice(Math.max(0, entries.length - 1 - window), -1).filter(
        (item) => (item.metrics?.sets || 0) > 0
            && (!current.movement || current.movement === "Unknown" || item.movement === current.movement)
            && (!current.equipment || item.equipment === current.equipment),
    );
    const results = [];
    for (const [name, unit] of Object.entries(METRICS)) {
        const value = current.metrics?.[name];
        const baseline = previous
            .map((item) => item.metrics?.[name])
            .filter((item) => typeof item === "number" && item > 0);
        if (value == null || baseline.length < minimum) {
            results.push({ metric: name, status: "unavailable", samples: baseline.length });
            continue;
        }
        const typical = median(baseline);
        const change = typical ? ((value - typical) / typical) * 100 : null;
        const direction = change !== null && change >= 25 ? "higher"
            : change !== null && change <= -25 ? "lower" : "typical";
        results.push({
            metric: name, status: "available", value: pythonRound(value, 1), unit,
            baseline: pythonRound(typical, 1),
            change_percent: change !== null ? pythonRound(change, 1) : null,
            direction, review: change !== null && Math.abs(change) >= 50,
            samples: baseline.length,
        });
    }
    return results;
}

export function load(path) {
    if (!existsSync(path)) {
        return { version: 1, privacy: "local-summary-only", workouts: [] };
    }
    return JSON.parse(readFileSync(path, "utf8"));
}

export function save(path, history) {
    mkdirSync(dirname(path) || ".", { recursive: true });
    writeFileSync(path, `${JSON.stringify(history, null, 2)}\n`, "utf8");
}

export function sourceId(path) {
    return createHash("sha256").update(readFileSync(path)).digest("hex").slice(0, 12);
}

function dateKey(item) {
    const match = item.date ? /^(\d{2}) ([A-Z][a-z]{2}) (\d{4})$/.exec(item.date) : null;
    if (!match || !MONTHS.includes(match[2])) {
        return -Infinity;
    }
    return Date.UTC(Number(match[3]), MONTHS.indexOf(match[2]), Number(match[1]));
}

export function importSource(history, source, loader = loadReport) {
    const identifier = sourceId(source);
    if (history.workouts.some((item) => item.id === identifier)) {
        return history;
    }
    history.workouts.push(summarize(loader(source), identifier));
    history.workouts.sort((a, b) => dateKey(a) - dateKey(b));
    return history;
}

function parseArgs(argv) {
    const args = { database: "workout-history.json", command: null, sources: [], output: null, id: null };
    let index = 0;
    while (index < argv.length) {
        const argument = argv[index];
        if (argument === "--database") {
            args.database = argv[++index];
        } else if (args.command === null) {
            args.command = argument;
        } else {
            args.sources.push(argument);
        }
        index++;
    }
    if (!["import", "show", "export", "delete", "clear"].includes(args.command)) {
        throw new Error("usage: workout-history.js [--database PATH] {import|show|export|delete|clear} ...");
    }
    if (args.command === "import" && args.sources.length === 0) {
        throw new Error("import requires at least one FIT/ZIP source");
    }
    if (args.command === "export") {
        args.output = args.sources[0] ?? null;
        if (!args.output) {
            throw new Error("export requires an output path");
        }
    }
    if (args.command === "delete") {
        args.id = args.sources[0] ?? null;
        if (!args.id) {
            throw new Error("delete requires a workout id");
        }
    }
    return args;
}

export function main(argv = process.argv.slice(2), loader = loadReport) {
    const args = parseArgs(argv);
    const history = load(args.database);
    if (args.command === "import") {
        for (const source of args.sources) {
            importSource(history, source, loader);
        }
        save(args.database, history);
    } else if (args.command === "delete") {
        history.workouts = history.workouts.filter((item) => item.id !== args.id);
        save(args.database, history);
    } else if (args.command === "clear") {
        history.workouts = [];
        save(args.database, history);
    } else if (args.command === "export") {
        save(args.output, history);
    }
    console.log(JSON.stringify({ ...history, latest_comparison: comparisons(history.workouts) }, null, 2));
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
