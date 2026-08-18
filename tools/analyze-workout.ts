#!/usr/bin/env node
// Derive transparent, non-medical within-session workout signals.

import { pythonRound } from "./fit-io.ts";
import {
    type Analysis,
    type Confidence,
    type Report,
    type ReportLap,
    type Signal,
} from "./report-types.ts";

const mean = (values: readonly number[]): number =>
    values.reduce((total, value) => total + value, 0) / values.length;

export function confidence(samples: number): Confidence {
    if (samples >= 8) {
        return "high";
    }
    if (samples >= 4) {
        return "medium";
    }
    if (samples >= 2) {
        return "low";
    }
    return "insufficient";
}

function unavailable(code: string, label: string, reason: string, samples = 0): Signal {
    return {
        code, label, status: "unavailable", value: null,
        unit: null, direction: "unknown", confidence: confidence(samples),
        samples, message: reason,
    };
}

function splitChange(values: readonly number[]): [number, number, number] {
    const midpoint = Math.floor(values.length / 2);
    const early = mean(values.slice(0, midpoint));
    const late = mean(values.slice(values.length - midpoint));
    return [early, late, late - early];
}

function trendSignal(
    code: string,
    label: string,
    values: readonly number[],
    unit: string,
    relative = false,
): Signal {
    const samples = values.length;
    if (samples < 4) {
        return unavailable(code, label, `Needs at least 4 valid work sets; found ${String(samples)}.`, samples);
    }
    const [early, late, change] = splitChange(values);
    const value = relative && early !== 0 ? (change / early) * 100 : change;
    const threshold = relative ? 10 : 5;
    const direction = value >= threshold ? "higher" : value <= -threshold ? "lower" : "stable";
    const wording = value > 0 ? "increased" : value < 0 ? "decreased" : "was unchanged";
    return {
        code, label, status: "available", value: pythonRound(value, 1),
        unit, direction, confidence: confidence(samples),
        samples, early: pythonRound(early, 1), late: pythonRound(late, 1),
        message: `Late-session average ${wording} by ${Math.abs(value).toFixed(1)}${unit} versus early sets.`,
    };
}

function exposureOf(lap: ReportLap): number {
    for (const candidate of [lap.exposure, lap.active_seconds, lap.elapsed]) {
        if (typeof candidate === "number" && candidate !== 0) {
            return candidate;
        }
    }
    return 0;
}

function balanceSignal(work: readonly ReportLap[]): Signal {
    const unilateral = work.filter((lap) => lap.side === "Left" || lap.side === "Right");
    const sides = new Set(unilateral.map((lap) => lap.side));
    if (unilateral.length < 4 || sides.size !== 2) {
        return unavailable(
            "side_balance", "Left/right exposure",
            "Needs at least 4 unilateral sets with both left and right represented.", unilateral.length,
        );
    }
    const totals = { Left: 0, Right: 0 };
    for (const lap of unilateral) {
        totals[lap.side === "Left" ? "Left" : "Right"] += exposureOf(lap);
    }
    const total = totals.Left + totals.Right;
    const left = total !== 0 ? (totals.Left / total) * 100 : 50;
    const difference = left - 50;
    const direction = difference >= 5 ? "left" : difference <= -5 ? "right" : "balanced";
    return {
        code: "side_balance", label: "Left/right exposure", status: "available",
        value: pythonRound(left, 1), unit: "% left", direction,
        confidence: confidence(unilateral.length), samples: unilateral.length,
        left: pythonRound(left, 1), right: pythonRound(100 - left, 1),
        message: `Recorded exposure was ${left.toFixed(1)}% left and ${(100 - left).toFixed(1)}% right.`,
    };
}

function dropoutSignal(report: Report): Signal {
    const elapsed = report.summary.elapsed ?? 0;
    const times = report.records
        .filter((point) => point.rms != null || point.peak != null)
        .map((point) => point.t)
        .sort((a, b) => a - b);
    if (elapsed === 0 || times.length === 0) {
        return unavailable("sensor_dropout", "Motion continuity", "No motion series is available.");
    }
    const boundaries = [0, ...times, elapsed];
    let longest = 0;
    for (let index = 1; index < boundaries.length; index++) {
        longest = Math.max(longest, (boundaries[index] ?? 0) - (boundaries[index - 1] ?? 0) - 1);
    }
    const coverage = Math.min(100, (times.length / Math.max(1, pythonRound(elapsed))) * 100);
    const direction = longest >= 3 ? "gap" : "continuous";
    return {
        code: "sensor_dropout", label: "Motion continuity", status: "available",
        value: pythonRound(longest, 1), unit: "s longest gap", direction,
        confidence: "high", samples: times.length, coverage: pythonRound(coverage, 1),
        message: `Motion coverage was ${coverage.toFixed(1)}%; longest missing interval was ${longest.toFixed(1)}s.`,
    };
}

// Return descriptive signals; never injury, tendon-force, or readiness claims.
export function analyze(report: Report): Analysis {
    const work = report.laps.filter(
        (lap) => lap.phase === "work" && (lap.set ?? 0) > 0 && (lap.elapsed ?? 0) >= 10,
    );
    const smoothness = work
        .map((lap) => lap.smoothness)
        .filter((value): value is number => typeof value === "number" && value >= 0);
    const peaks = work
        .map((lap) => lap.motion_peak)
        .filter((value): value is number => typeof value === "number" && value >= 0);
    const signals = [
        trendSignal("smoothness_drift", "Smoothness drift", smoothness, " points"),
        trendSignal("peak_change", "Late-session peak change", peaks, "%", true),
        balanceSignal(work),
        dropoutSignal(report),
    ];
    return {
        signals,
        available: signals.filter((signal) => signal.status === "available").length,
        disclaimer: "Descriptive session signals only—not tendon force, injury risk, or readiness.",
    };
}
