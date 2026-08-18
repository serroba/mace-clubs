#!/usr/bin/env node
// Derive transparent, non-medical within-session workout signals.

import { pythonRound } from "./fit-io.js";

const mean = (values) => values.reduce((total, value) => total + value, 0) / values.length;

export function confidence(samples) {
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

function unavailable(code, label, reason, samples = 0) {
    return {
        code, label, status: "unavailable", value: null,
        unit: null, direction: "unknown", confidence: confidence(samples),
        samples, message: reason,
    };
}

function splitChange(values) {
    const midpoint = Math.floor(values.length / 2);
    const early = mean(values.slice(0, midpoint));
    const late = mean(values.slice(values.length - midpoint));
    return [early, late, late - early];
}

function trendSignal(code, label, values, unit, relative = false) {
    const samples = values.length;
    if (samples < 4) {
        return unavailable(code, label, `Needs at least 4 valid work sets; found ${samples}.`, samples);
    }
    const [early, late, change] = splitChange(values);
    const value = relative && early ? (change / early) * 100 : change;
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

function balanceSignal(work) {
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
        totals[lap.side] += Number(lap.exposure || lap.active_seconds || lap.elapsed);
    }
    const total = totals.Left + totals.Right;
    const left = total ? (totals.Left / total) * 100 : 50;
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

function dropoutSignal(report) {
    const elapsed = Number(report.summary.elapsed ?? 0);
    const times = report.records
        .filter((point) => point.rms != null || point.peak != null)
        .map((point) => Number(point.t))
        .sort((a, b) => a - b);
    if (!elapsed || times.length === 0) {
        return unavailable("sensor_dropout", "Motion continuity", "No motion series is available.");
    }
    const boundaries = [0, ...times, elapsed];
    let longest = 0;
    for (let index = 1; index < boundaries.length; index++) {
        longest = Math.max(longest, boundaries[index] - boundaries[index - 1] - 1);
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
export function analyze(report) {
    const work = report.laps.filter(
        (lap) => lap.phase === "work" && (lap.set ?? 0) > 0 && (lap.elapsed ?? 0) >= 10,
    );
    const smoothness = work
        .filter((lap) => typeof lap.smoothness === "number" && lap.smoothness >= 0)
        .map((lap) => Number(lap.smoothness));
    const peaks = work
        .filter((lap) => typeof lap.motion_peak === "number" && lap.motion_peak >= 0)
        .map((lap) => Number(lap.motion_peak));
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
