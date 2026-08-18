#!/usr/bin/env node
// Validate the integrity and data quality of a Mace & Clubs FIT export.

import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { fitPath, pythonRound, readFit } from "./fit-io.js";
import { collect } from "./report-fit.js";

function finding(severity, code, message, deduction = 0, target = null) {
    return { severity, code, message, deduction, target };
}

// Return transparent integrity findings for a collected workout report.
export function validate(report) {
    const { summary, laps, records } = report;
    const findings = [];

    const elapsed = Number(summary.elapsed ?? 0);
    if (elapsed <= 0) {
        findings.push(finding("error", "session.duration", "Session duration is missing or zero.", 30));
    }

    const work = laps.filter((lap) => lap.phase === "work" && (lap.set ?? 0) > 0);
    const rest = laps.filter((lap) => lap.phase === "rest");
    if (laps.length === 0) {
        findings.push(finding("error", "laps.missing", "No work/rest laps were recorded.", 35));
    } else if (work.length === 0) {
        findings.push(finding("error", "laps.no_work", "No numbered work laps were recorded.", 30));
    }

    const recordedSets = Math.trunc(summary.sets ?? 0);
    if (work.length > 0 && recordedSets !== work.length) {
        findings.push(finding(
            "warning", "sets.total_mismatch",
            `Session reports ${recordedSets} sets but ${work.length} work laps were found.`, 10,
        ));
    }

    const numbers = work.map((lap) => Math.trunc(lap.set));
    const expected = numbers.map((_, index) => index + 1);
    if (numbers.length > 0 && numbers.some((value, index) => value !== expected[index])) {
        findings.push(finding(
            "warning", "sets.sequence",
            `Work-set sequence is [${numbers.join(", ")}]; expected [${expected.join(", ")}].`, 8,
        ));
    }

    const ordered = [...laps].sort((a, b) => a.start - b.start);
    for (let index = 1; index < ordered.length; index++) {
        const previous = ordered[index - 1];
        const current = ordered[index];
        // Garmin stores lap starts at whole-second precision while elapsed
        // durations retain milliseconds, so sub-second boundary overlap is
        // expected in otherwise healthy exports.
        if (current.start < previous.end - 1.0) {
            findings.push(finding(
                "error", "laps.overlap",
                `Lap ${current.lap} overlaps lap ${previous.lap}.`, 20,
                `lap-${current.lap}`,
            ));
            break;
        }
    }

    const lapSeconds = laps.reduce((total, lap) => total + Number(lap.elapsed ?? 0), 0);
    if (elapsed && laps.length > 0 && Math.abs(lapSeconds - elapsed) > Math.max(2.0, elapsed * 0.02)) {
        findings.push(finding(
            "warning", "laps.duration_mismatch",
            `Laps total ${lapSeconds.toFixed(1)}s while the session reports ${elapsed.toFixed(1)}s.`, 8,
        ));
    }

    for (const lap of work) {
        if (Number(lap.elapsed ?? 0) < 10) {
            findings.push(finding(
                "warning", "sets.short",
                `Set ${lap.set} lasted under 10 seconds and may be incomplete.`, 5,
                `set-${lap.set}`,
            ));
        }
        const score = lap.smoothness;
        if (score != null && !(score >= 0 && score <= 100)) {
            findings.push(finding(
                "error", "smoothness.range",
                `Set ${lap.set} has smoothness ${score}; expected 0–100.`, 15,
                `set-${lap.set}`,
            ));
        }
        for (const [key, label] of [["motion_peak", "motion peak"], ["exposure", "motion exposure"],
                                    ["active_seconds", "active time"], ["swings", "swing count"]]) {
            const value = lap[key];
            if (value != null && value < 0) {
                findings.push(finding(
                    "error", `${key}.negative`, `Set ${lap.set} has negative ${label}.`, 15,
                    `set-${lap.set}`,
                ));
            }
        }
    }

    const motion = records.filter((point) => point.rms != null || point.peak != null);
    const heartRate = records.filter((point) => point.hr != null);
    for (const point of motion) {
        const { rms, peak } = point;
        if ((rms != null && rms < 0) || (peak != null && peak < 0)) {
            findings.push(finding("error", "motion.negative", "Motion samples contain a negative value.", 20));
            break;
        }
        if (rms != null && peak != null && peak < rms) {
            findings.push(finding(
                "warning", "motion.peak_below_rms",
                "A peak-acceleration sample is lower than its RMS intensity.", 8,
            ));
            break;
        }
    }

    const expectedSamples = Math.max(1, pythonRound(elapsed));
    const motionCoverage = elapsed ? Math.min(1.0, motion.length / expectedSamples) : 0.0;
    const hrCoverage = elapsed ? Math.min(1.0, heartRate.length / expectedSamples) : 0.0;
    if (motion.length === 0) {
        findings.push(finding(
            "info", "motion.unavailable",
            "No per-second wrist-motion series is present; Motion logging may have been off.", 0,
            "timeline",
        ));
    } else if (motionCoverage < 0.9) {
        findings.push(finding(
            "warning", "motion.coverage",
            `Motion-series coverage is ${percent(motionCoverage)}; expected at least 90%.`, 12,
            "timeline",
        ));
    }
    if (heartRate.length === 0) {
        findings.push(finding("warning", "heart_rate.unavailable", "No heart-rate samples are present.", 8,
                              "timeline"));
    } else if (hrCoverage < 0.8) {
        findings.push(finding(
            "warning", "heart_rate.coverage",
            `Heart-rate coverage is ${percent(hrCoverage)}; expected at least 80%.`, 6,
            "timeline",
        ));
    }

    const swingSeries = records.filter((point) => point.swing_total != null);
    for (let index = 1; index < swingSeries.length; index++) {
        const previous = swingSeries[index - 1];
        const current = swingSeries[index];
        if (current.swing_total < previous.swing_total) {
            findings.push(finding(
                "error", "swings.regression",
                `Cumulative swing total drops from ${previous.swing_total} to ` +
                `${current.swing_total} at ${current.t.toFixed(0)}s.`, 20, "timeline",
            ));
            break;
        }
    }
    const events = records.reduce((total, point) => total + (point.swing_event || 0), 0);
    if (swingSeries.length > 0 && events) {
        const delta = swingSeries[swingSeries.length - 1].swing_total - swingSeries[0].swing_total;
        if (events !== delta) {
            findings.push(finding(
                "warning", "swings.event_mismatch",
                `${events} swing events were marked but the cumulative total grew by ${delta}.`, 10,
                "timeline",
            ));
        }
    }
    const swingCoverage = elapsed ? Math.min(1.0, swingSeries.length / expectedSamples) : 0.0;
    if (swingSeries.length > 0 && swingCoverage < 0.9) {
        findings.push(finding(
            "warning", "swings.coverage",
            `Swing-series coverage is ${percent(swingCoverage)}; expected at least 90%.`, 8,
            "timeline",
        ));
    }
    for (const point of records) {
        const cadence = point.swing_cadence;
        if (cadence != null && !(cadence >= 0 && cadence <= 240)) {
            findings.push(finding(
                "error", "cadence.range",
                `Swing cadence ${cadence} spm is outside the plausible 0–240 range.`, 15,
                "timeline",
            ));
            break;
        }
    }
    const smoothnessSeries = records.filter((point) => point.smoothness_score != null);
    for (const point of smoothnessSeries) {
        if (!(point.smoothness_score >= 0 && point.smoothness_score <= 100)) {
            findings.push(finding(
                "error", "smoothness.series_range",
                `Rolling smoothness ${point.smoothness_score} is outside 0–100.`, 15,
                "timeline",
            ));
            break;
        }
    }

    if (summary.movement === "Unknown") {
        findings.push(finding("warning", "metadata.movement", "Movement metadata is unavailable.", 4));
    }
    if (summary.side === "Unknown") {
        findings.push(finding("warning", "metadata.side", "Working-side metadata is unavailable.", 4));
    }
    if (!summary.equipment) {
        findings.push(finding("info", "metadata.equipment", "Equipment description is unavailable.", 0));
    }

    const score = Math.max(0, 100 - findings.reduce((total, item) => total + item.deduction, 0));
    const errors = findings.filter((item) => item.severity === "error").length;
    const warnings = findings.filter((item) => item.severity === "warning").length;
    let status;
    if (errors) {
        status = "invalid";
    } else if (score >= 90 && !warnings) {
        status = "healthy";
    } else {
        status = "usable_with_gaps";
    }
    return {
        status,
        score,
        counts: { errors, warnings },
        coverage: { motion: pythonRound(motionCoverage, 3), heart_rate: pythonRound(hrCoverage, 3) },
        observed: { laps: laps.length, work_laps: work.length, rest_laps: rest.length,
                    motion_samples: motion.length, heart_rate_samples: heartRate.length,
                    swing_samples: swingSeries.length, smoothness_samples: smoothnessSeries.length },
        findings,
    };
}

function percent(ratio) {
    return `${pythonRound(ratio * 100)}%`;
}

export function renderText(result) {
    const lines = [
        `Workout integrity: ${result.status} (${result.score}/100)`,
        `Coverage: motion ${percent(result.coverage.motion)}, heart rate ${percent(result.coverage.heart_rate)}`,
    ];
    for (const item of result.findings) {
        lines.push(`${item.severity.toUpperCase().padEnd(7)} ${item.code}: ${item.message}`);
    }
    if (result.findings.length === 0) {
        lines.push("No integrity or data-quality issues found.");
    }
    return lines.join("\n");
}

export function loadReport(source) {
    const temporary = mkdtempSync(join(tmpdir(), "mace-clubs-fit-"));
    try {
        return collect(readFit(readFileSync(fitPath(source, temporary))));
    } finally {
        rmSync(temporary, { recursive: true, force: true });
    }
}

function parseArgs(argv) {
    const args = { source: null, json: false };
    for (const argument of argv) {
        if (argument === "--json") {
            args.json = true;
        } else if (args.source === null) {
            args.source = argument;
        } else {
            throw new Error(`unexpected argument: ${argument}`);
        }
    }
    if (args.source === null) {
        throw new Error("usage: validate-workout.js SOURCE [--json]");
    }
    return args;
}

export function main(argv = process.argv.slice(2), loader = loadReport) {
    const args = parseArgs(argv);
    const result = validate(loader(args.source));
    console.log(args.json ? JSON.stringify(result, null, 2) : renderText(result));
    return result.counts.errors ? 1 : 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
