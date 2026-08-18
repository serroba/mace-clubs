#!/usr/bin/env python3
"""Validate the integrity and data quality of a Mace & Clubs FIT export."""

from __future__ import annotations

import argparse
import json
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

from fitparse import FitFile

@dataclass(frozen=True)
class Finding:
    severity: str
    code: str
    message: str
    deduction: int = 0
    target: str | None = None


def finding(severity: str, code: str, message: str, deduction: int = 0,
            target: str | None = None) -> Finding:
    return Finding(severity, code, message, deduction, target)


def validate(report: dict) -> dict:
    """Return transparent integrity findings for a collected workout report."""
    summary = report["summary"]
    laps = report["laps"]
    records = report["records"]
    findings: list[Finding] = []

    elapsed = float(summary.get("elapsed") or 0)
    if elapsed <= 0:
        findings.append(finding("error", "session.duration", "Session duration is missing or zero.", 30))

    work = [lap for lap in laps if lap.get("phase") == "work" and lap.get("set", 0) > 0]
    rest = [lap for lap in laps if lap.get("phase") == "rest"]
    if not laps:
        findings.append(finding("error", "laps.missing", "No work/rest laps were recorded.", 35))
    elif not work:
        findings.append(finding("error", "laps.no_work", "No numbered work laps were recorded.", 30))

    recorded_sets = int(summary.get("sets") or 0)
    if work and recorded_sets != len(work):
        findings.append(finding(
            "warning", "sets.total_mismatch",
            f"Session reports {recorded_sets} sets but {len(work)} work laps were found.", 10,
        ))

    numbers = [int(lap["set"]) for lap in work]
    expected = list(range(1, len(numbers) + 1))
    if numbers and numbers != expected:
        findings.append(finding(
            "warning", "sets.sequence", f"Work-set sequence is {numbers}; expected {expected}.", 8,
        ))

    ordered = sorted(laps, key=lambda lap: lap["start"])
    for previous, current in zip(ordered, ordered[1:]):
        # Garmin stores lap starts at whole-second precision while elapsed
        # durations retain milliseconds, so sub-second boundary overlap is
        # expected in otherwise healthy exports.
        if current["start"] < previous["end"] - 1.0:
            findings.append(finding(
                "error", "laps.overlap",
                f"Lap {current['lap']} overlaps lap {previous['lap']}.", 20,
                f"lap-{current['lap']}",
            ))
            break

    lap_seconds = sum(float(lap.get("elapsed") or 0) for lap in laps)
    if elapsed and laps and abs(lap_seconds - elapsed) > max(2.0, elapsed * 0.02):
        findings.append(finding(
            "warning", "laps.duration_mismatch",
            f"Laps total {lap_seconds:.1f}s while the session reports {elapsed:.1f}s.", 8,
        ))

    for lap in work:
        if float(lap.get("elapsed") or 0) < 10:
            findings.append(finding(
                "warning", "sets.short",
                f"Set {lap['set']} lasted under 10 seconds and may be incomplete.", 5,
                f"set-{lap['set']}",
            ))
        score = lap.get("smoothness")
        if score is not None and not 0 <= score <= 100:
            findings.append(finding(
                "error", "smoothness.range",
                f"Set {lap['set']} has smoothness {score}; expected 0–100.", 15,
                f"set-{lap['set']}",
            ))
        for key, label in (("motion_peak", "motion peak"), ("exposure", "motion exposure"),
                           ("active_seconds", "active time"), ("swings", "swing count")):
            value = lap.get(key)
            if value is not None and value < 0:
                findings.append(finding(
                    "error", f"{key}.negative", f"Set {lap['set']} has negative {label}.", 15,
                    f"set-{lap['set']}",
                ))

    motion = [point for point in records if point.get("rms") is not None or point.get("peak") is not None]
    heart_rate = [point for point in records if point.get("hr") is not None]
    for point in motion:
        rms, peak = point.get("rms"), point.get("peak")
        if (rms is not None and rms < 0) or (peak is not None and peak < 0):
            findings.append(finding("error", "motion.negative", "Motion samples contain a negative value.", 20))
            break
        if rms is not None and peak is not None and peak < rms:
            findings.append(finding(
                "warning", "motion.peak_below_rms",
                "A peak-acceleration sample is lower than its RMS intensity.", 8,
            ))
            break

    expected_samples = max(1, round(elapsed))
    motion_coverage = min(1.0, len(motion) / expected_samples) if elapsed else 0.0
    hr_coverage = min(1.0, len(heart_rate) / expected_samples) if elapsed else 0.0
    if not motion:
        findings.append(finding(
            "info", "motion.unavailable",
            "No per-second wrist-motion series is present; Motion logging may have been off.", 0,
            "timeline",
        ))
    elif motion_coverage < 0.9:
        findings.append(finding(
            "warning", "motion.coverage",
            f"Motion-series coverage is {motion_coverage:.0%}; expected at least 90%.", 12,
            "timeline",
        ))
    if not heart_rate:
        findings.append(finding("warning", "heart_rate.unavailable", "No heart-rate samples are present.", 8,
                                "timeline"))
    elif hr_coverage < 0.8:
        findings.append(finding(
            "warning", "heart_rate.coverage",
            f"Heart-rate coverage is {hr_coverage:.0%}; expected at least 80%.", 6,
            "timeline",
        ))

    swing_series = [point for point in records if point.get("swing_total") is not None]
    for previous, current in zip(swing_series, swing_series[1:]):
        if current["swing_total"] < previous["swing_total"]:
            findings.append(finding(
                "error", "swings.regression",
                f"Cumulative swing total drops from {previous['swing_total']} to "
                f"{current['swing_total']} at {current['t']:.0f}s.", 20, "timeline",
            ))
            break
    events = sum(point.get("swing_event") or 0 for point in records)
    if swing_series and events:
        delta = swing_series[-1]["swing_total"] - swing_series[0]["swing_total"]
        if events != delta:
            findings.append(finding(
                "warning", "swings.event_mismatch",
                f"{events} swing events were marked but the cumulative total grew by {delta}.", 10,
                "timeline",
            ))
    swing_coverage = min(1.0, len(swing_series) / expected_samples) if elapsed else 0.0
    if swing_series and swing_coverage < 0.9:
        findings.append(finding(
            "warning", "swings.coverage",
            f"Swing-series coverage is {swing_coverage:.0%}; expected at least 90%.", 8,
            "timeline",
        ))
    for point in records:
        cadence = point.get("swing_cadence")
        if cadence is not None and not 0 <= cadence <= 240:
            findings.append(finding(
                "error", "cadence.range",
                f"Swing cadence {cadence} spm is outside the plausible 0–240 range.", 15,
                "timeline",
            ))
            break
    smoothness_series = [point for point in records if point.get("smoothness_score") is not None]
    for point in smoothness_series:
        if not 0 <= point["smoothness_score"] <= 100:
            findings.append(finding(
                "error", "smoothness.series_range",
                f"Rolling smoothness {point['smoothness_score']} is outside 0–100.", 15,
                "timeline",
            ))
            break

    if summary.get("movement") == "Unknown":
        findings.append(finding("warning", "metadata.movement", "Movement metadata is unavailable.", 4))
    if summary.get("side") == "Unknown":
        findings.append(finding("warning", "metadata.side", "Working-side metadata is unavailable.", 4))
    if not summary.get("equipment"):
        findings.append(finding("info", "metadata.equipment", "Equipment description is unavailable.", 0))

    score = max(0, 100 - sum(item.deduction for item in findings))
    errors = sum(item.severity == "error" for item in findings)
    warnings = sum(item.severity == "warning" for item in findings)
    if errors:
        status = "invalid"
    elif score >= 90 and not warnings:
        status = "healthy"
    else:
        status = "usable_with_gaps"
    return {
        "status": status,
        "score": score,
        "counts": {"errors": errors, "warnings": warnings},
        "coverage": {"motion": round(motion_coverage, 3), "heart_rate": round(hr_coverage, 3)},
        "observed": {"laps": len(laps), "work_laps": len(work), "rest_laps": len(rest),
                     "motion_samples": len(motion), "heart_rate_samples": len(heart_rate),
                     "swing_samples": len(swing_series), "smoothness_samples": len(smoothness_series)},
        "findings": [asdict(item) for item in findings],
    }


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="raw FIT activity or Garmin ZIP export")
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    return parser.parse_args(argv)


def render_text(result: dict) -> str:
    lines = [
        f"Workout integrity: {result['status']} ({result['score']}/100)",
        f"Coverage: motion {result['coverage']['motion']:.0%}, heart rate {result['coverage']['heart_rate']:.0%}",
    ]
    for item in result["findings"]:
        lines.append(f"{item['severity'].upper():7} {item['code']}: {item['message']}")
    if not result["findings"]:
        lines.append("No integrity or data-quality issues found.")
    return "\n".join(lines)


def load_report(source: Path) -> dict:
    try:
        from report_fit import collect, fit_path
    except ModuleNotFoundError:  # Imported as tools.validate_workout by tests.
        from tools.report_fit import collect, fit_path
    with tempfile.TemporaryDirectory(prefix="mace-clubs-fit-") as temporary:
        fit_source = fit_path(source, Path(temporary))
        return collect(FitFile(str(fit_source)))


def main(argv=None) -> int:
    args = parse_args(argv)
    report = load_report(args.source)
    result = validate(report)
    print(json.dumps(result, indent=2) if args.json else render_text(result))
    return 1 if result["counts"]["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
