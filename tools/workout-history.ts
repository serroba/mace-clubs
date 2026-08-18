#!/usr/bin/env node
// Maintain a private local Workout Inspector history from FIT/ZIP exports.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { pythonRound } from "./fit-io.ts";
import { type Report, type ReportLap } from "./report-types.ts";
import { loadReport } from "./validate-workout.ts";

const METRICS = {
    duration: "s",
    work_seconds: "s",
    sets: "sets",
    motion_exposure: "mg-s",
    active_seconds: "s",
    weight_volume: "kg-swings",
    motion_peak: "mg",
    smoothness: "score",
} as const;

export type MetricName = keyof typeof METRICS;

export type Metrics = Partial<Record<MetricName, number | null>>;

export interface HistoryEntry {
    id: string;
    imported_at: string;
    date: string | null;
    movement: string | null;
    side: string | null;
    equipment: string | null;
    sets: number;
    duration: number | null;
    metrics: Metrics;
}

export interface History {
    version: number;
    privacy: string;
    workouts: HistoryEntry[];
}

export interface Comparison {
    metric: MetricName;
    status: "available" | "unavailable";
    samples: number;
    value?: number;
    unit?: string;
    baseline?: number;
    change_percent?: number | null;
    direction?: "higher" | "lower" | "typical";
    review?: boolean;
}

const METRIC_ENTRIES = Object.entries(METRICS) as [MetricName, string][];

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"] as const;

function median(values: readonly number[]): number {
    const sorted = [...values].sort((a, b) => a - b);
    const middle = Math.floor(sorted.length / 2);
    const upper = sorted[middle] ?? 0;
    if (sorted.length % 2 === 1) {
        return upper;
    }
    return ((sorted[middle - 1] ?? 0) + upper) / 2;
}

function lapValue(lap: ReportLap, name: MetricName): number | null {
    const value = name === "motion_exposure" ? lap.exposure : (lap as Record<string, unknown>)[name];
    return typeof value === "number" ? value : null;
}

export function metric(laps: readonly ReportLap[], name: MetricName): number | null {
    const values = laps
        .map((lap) => lapValue(lap, name))
        .filter((value): value is number => value !== null && value >= 0);
    if (values.length === 0) {
        return null;
    }
    if (name === "motion_peak") {
        return Math.max(...values);
    }
    const total = values.reduce((sum, value) => sum + value, 0);
    return name === "smoothness" ? total / values.length : total;
}

export function summarize(report: Report, identifier: string, importedAt: string | null = null): HistoryEntry {
    const work = report.laps.filter((lap) => lap.phase === "work" && (lap.set ?? 0) > 0);
    const metrics: Metrics = {
        duration: report.summary.elapsed ?? null,
        work_seconds: report.summary.work_seconds ?? null,
        sets: work.length,
    };
    for (const [name] of METRIC_ENTRIES) {
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

export function comparisons(entries: readonly HistoryEntry[], minimum = 3, window = 8): Comparison[] {
    const current = entries[entries.length - 1];
    if (current === undefined) {
        return [];
    }
    const previous = entries.slice(Math.max(0, entries.length - 1 - window), -1).filter(
        (item) => (item.metrics.sets ?? 0) > 0
            && (current.movement == null || current.movement === "Unknown" || item.movement === current.movement)
            && (current.equipment == null || item.equipment === current.equipment),
    );
    const results: Comparison[] = [];
    for (const [name, unit] of METRIC_ENTRIES) {
        const value = current.metrics[name];
        const baseline = previous
            .map((item) => item.metrics[name])
            .filter((item): item is number => typeof item === "number" && item > 0);
        if (value == null || baseline.length < minimum) {
            results.push({ metric: name, status: "unavailable", samples: baseline.length });
            continue;
        }
        const typical = median(baseline);
        const change = typical !== 0 ? ((value - typical) / typical) * 100 : null;
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

export function load(path: string): History {
    if (!existsSync(path)) {
        return { version: 1, privacy: "local-summary-only", workouts: [] };
    }
    return JSON.parse(readFileSync(path, "utf8")) as History;
}

export function save(path: string, history: History): void {
    const parent = dirname(path);
    if (parent !== "") {
        mkdirSync(parent, { recursive: true });
    }
    writeFileSync(path, `${JSON.stringify(history, null, 2)}\n`, "utf8");
}

export function sourceId(path: string): string {
    return createHash("sha256").update(readFileSync(path)).digest("hex").slice(0, 12);
}

function dateKey(item: HistoryEntry): number {
    const match = item.date != null ? /^(\d{2}) ([A-Z][a-z]{2}) (\d{4})$/.exec(item.date) : null;
    if (match === null) {
        return -Infinity;
    }
    const monthIndex = MONTHS.indexOf(match[2] as (typeof MONTHS)[number]);
    if (monthIndex < 0) {
        return -Infinity;
    }
    return Date.UTC(Number(match[3]), monthIndex, Number(match[1]));
}

export function importSource(
    history: History,
    source: string,
    loader: (path: string) => Report = loadReport,
): History {
    const identifier = sourceId(source);
    if (history.workouts.some((item) => item.id === identifier)) {
        return history;
    }
    history.workouts.push(summarize(loader(source), identifier));
    history.workouts.sort((a, b) => dateKey(a) - dateKey(b));
    return history;
}

type Command = "import" | "show" | "export" | "delete" | "clear";

interface CliArgs {
    database: string;
    command: Command;
    sources: string[];
    output: string | null;
    id: string | null;
}

function isCommand(value: string): value is Command {
    return ["import", "show", "export", "delete", "clear"].includes(value);
}

function parseArgs(argv: readonly string[]): CliArgs {
    let database = "workout-history.json";
    let command: Command | null = null;
    const sources: string[] = [];
    let index = 0;
    while (index < argv.length) {
        const argument = argv[index];
        if (argument === "--database") {
            index++;
            database = argv[index] ?? database;
        } else if (argument !== undefined && command === null) {
            if (!isCommand(argument)) {
                throw new Error("usage: workout-history.ts [--database PATH] {import|show|export|delete|clear} ...");
            }
            command = argument;
        } else if (argument !== undefined) {
            sources.push(argument);
        }
        index++;
    }
    if (command === null) {
        throw new Error("usage: workout-history.ts [--database PATH] {import|show|export|delete|clear} ...");
    }
    if (command === "import" && sources.length === 0) {
        throw new Error("import requires at least one FIT/ZIP source");
    }
    const output = command === "export" ? (sources[0] ?? null) : null;
    if (command === "export" && output === null) {
        throw new Error("export requires an output path");
    }
    const id = command === "delete" ? (sources[0] ?? null) : null;
    if (command === "delete" && id === null) {
        throw new Error("delete requires a workout id");
    }
    return { database, command, sources, output, id };
}

export function main(
    argv: readonly string[] = process.argv.slice(2),
    loader: (path: string) => Report = loadReport,
): number {
    const args = parseArgs(argv);
    const history = load(args.database);
    switch (args.command) {
        case "import":
            for (const source of args.sources) {
                importSource(history, source, loader);
            }
            save(args.database, history);
            break;
        case "delete":
            history.workouts = history.workouts.filter((item) => item.id !== args.id);
            save(args.database, history);
            break;
        case "clear":
            history.workouts = [];
            save(args.database, history);
            break;
        case "export":
            if (args.output !== null) {
                save(args.output, history);
            }
            break;
        case "show":
            break;
    }
    console.log(JSON.stringify({ ...history, latest_comparison: comparisons(history.workouts) }, null, 2));
    return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
