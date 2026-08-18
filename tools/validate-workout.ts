#!/usr/bin/env node
// Validate the integrity and data quality of a Mace & Clubs FIT export.

import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { fitPath, pythonRound, readFit } from "./fit-io.ts";
import { collect } from "./report-fit.ts";
import {
    type Finding,
    type Report,
    type ReportLap,
    type Severity,
    type ValidationResult,
    type ValidationStatus,
} from "./report-types.ts";

function finding(
    severity: Severity,
    code: string,
    message: string,
    deduction = 0,
    target: string | null = null,
): Finding {
    return { severity, code, message, deduction, target };
}

function percent(ratio: number): string {
    return `${String(pythonRound(ratio * 100))}%`;
}

// Return transparent integrity findings for a collected workout report.
export function validate(report: Report): ValidationResult {
    const { summary, laps, records } = report;
    const findings: Finding[] = [];

    const elapsed = summary.elapsed ?? 0;
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
            `Session reports ${String(recordedSets)} sets but ${String(work.length)} work laps were found.`, 10,
        ));
    }

    const numbers = work.map((lap) => Math.trunc(lap.set ?? 0));
    const expected = numbers.map((_, index) => index + 1);
    if (numbers.length > 0 && numbers.some((value, index) => value !== expected[index])) {
        findings.push(finding(
            "warning", "sets.sequence",
            `Work-set sequence is [${numbers.join(", ")}]; expected [${expected.join(", ")}].`, 8,
        ));
    }

    const ordered = [...laps].sort((a, b) => (a.start ?? 0) - (b.start ?? 0));
    for (let index = 1; index < ordered.length; index++) {
        const previous = ordered[index - 1];
        const current = ordered[index];
        if (previous === undefined || current === undefined) {
            continue;
        }
        // Garmin stores lap starts at whole-second precision while elapsed
        // durations retain milliseconds, so sub-second boundary overlap is
        // expected in otherwise healthy exports.
        if ((current.start ?? 0) < (previous.end ?? 0) - 1.0) {
            findings.push(finding(
                "error", "laps.overlap",
                `Lap ${String(current.lap)} overlaps lap ${String(previous.lap)}.`, 20,
                `lap-${String(current.lap)}`,
            ));
            break;
        }
    }

    const lapSeconds = laps.reduce((total, lap) => total + (lap.elapsed ?? 0), 0);
    if (elapsed !== 0 && laps.length > 0 && Math.abs(lapSeconds - elapsed) > Math.max(2.0, elapsed * 0.02)) {
        findings.push(finding(
            "warning", "laps.duration_mismatch",
            `Laps total ${lapSeconds.toFixed(1)}s while the session reports ${elapsed.toFixed(1)}s.`, 8,
        ));
    }

    const negatives: [keyof ReportLap, string][] = [
        ["motion_peak", "motion peak"], ["exposure", "motion exposure"],
        ["active_seconds", "active time"], ["swings", "swing count"],
    ];
    for (const lap of work) {
        if ((lap.elapsed ?? 0) < 10) {
            findings.push(finding(
                "warning", "sets.short",
                `Set ${String(lap.set)} lasted under 10 seconds and may be incomplete.`, 5,
                `set-${String(lap.set)}`,
            ));
        }
        const score = lap.smoothness;
        if (score != null && !(score >= 0 && score <= 100)) {
            findings.push(finding(
                "error", "smoothness.range",
                `Set ${String(lap.set)} has smoothness ${String(score)}; expected 0–100.`, 15,
                `set-${String(lap.set)}`,
            ));
        }
        for (const [key, label] of negatives) {
            const value = lap[key];
            if (typeof value === "number" && value < 0) {
                findings.push(finding(
                    "error", `${key}.negative`, `Set ${String(lap.set)} has negative ${label}.`, 15,
                    `set-${String(lap.set)}`,
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
    const motionCoverage = elapsed !== 0 ? Math.min(1.0, motion.length / expectedSamples) : 0.0;
    const hrCoverage = elapsed !== 0 ? Math.min(1.0, heartRate.length / expectedSamples) : 0.0;
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

    const swingSeries = records.filter(
        (point): point is typeof point & { swing_total: number } => point.swing_total != null,
    );
    for (let index = 1; index < swingSeries.length; index++) {
        const previous = swingSeries[index - 1];
        const current = swingSeries[index];
        if (previous === undefined || current === undefined) {
            continue;
        }
        if (current.swing_total < previous.swing_total) {
            findings.push(finding(
                "error", "swings.regression",
                `Cumulative swing total drops from ${String(previous.swing_total)} to `
                + `${String(current.swing_total)} at ${current.t.toFixed(0)}s.`, 20, "timeline",
            ));
            break;
        }
    }
    const events = records.reduce((total, point) => total + (point.swing_event ?? 0), 0);
    const firstSwing = swingSeries[0];
    const lastSwing = swingSeries[swingSeries.length - 1];
    if (firstSwing !== undefined && lastSwing !== undefined && events !== 0) {
        const delta = lastSwing.swing_total - firstSwing.swing_total;
        if (events !== delta) {
            findings.push(finding(
                "warning", "swings.event_mismatch",
                `${String(events)} swing events were marked but the cumulative total grew by ${String(delta)}.`, 10,
                "timeline",
            ));
        }
    }
    const swingCoverage = elapsed !== 0 ? Math.min(1.0, swingSeries.length / expectedSamples) : 0.0;
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
                `Swing cadence ${String(cadence)} spm is outside the plausible 0–240 range.`, 15,
                "timeline",
            ));
            break;
        }
    }
    const smoothnessSeries = records.filter((point) => point.smoothness_score != null);
    for (const point of smoothnessSeries) {
        const score = point.smoothness_score ?? 0;
        if (!(score >= 0 && score <= 100)) {
            findings.push(finding(
                "error", "smoothness.series_range",
                `Rolling smoothness ${String(score)} is outside 0–100.`, 15,
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
    if (summary.equipment == null || summary.equipment === "") {
        findings.push(finding("info", "metadata.equipment", "Equipment description is unavailable.", 0));
    }

    const score = Math.max(0, 100 - findings.reduce((total, item) => total + item.deduction, 0));
    const errors = findings.filter((item) => item.severity === "error").length;
    const warnings = findings.filter((item) => item.severity === "warning").length;
    let status: ValidationStatus;
    if (errors > 0) {
        status = "invalid";
    } else if (score >= 90 && warnings === 0) {
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

export function renderText(result: ValidationResult): string {
    const lines = [
        `Workout integrity: ${result.status} (${String(result.score)}/100)`,
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

export function loadReport(source: string): Report {
    const temporary = mkdtempSync(join(tmpdir(), "mace-clubs-fit-"));
    try {
        return collect(readFit(readFileSync(fitPath(source, temporary))));
    } finally {
        rmSync(temporary, { recursive: true, force: true });
    }
}

interface CliArgs {
    source: string;
    json: boolean;
}

function parseArgs(argv: readonly string[]): CliArgs {
    let source: string | null = null;
    let json = false;
    for (const argument of argv) {
        if (argument === "--json") {
            json = true;
        } else if (source === null) {
            source = argument;
        } else {
            throw new Error(`unexpected argument: ${argument}`);
        }
    }
    if (source === null) {
        throw new Error("usage: validate-workout.ts SOURCE [--json]");
    }
    return { source, json };
}

export function main(
    argv: readonly string[] = process.argv.slice(2),
    loader: (source: string) => Report = loadReport,
): number {
    const args = parseArgs(argv);
    const result = validate(loader(args.source));
    console.log(args.json ? JSON.stringify(result, null, 2) : renderText(result));
    return result.counts.errors > 0 ? 1 : 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    process.exitCode = main();
}
