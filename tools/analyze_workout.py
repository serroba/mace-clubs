#!/usr/bin/env python3
"""Derive transparent, non-medical within-session workout signals."""

from __future__ import annotations

from statistics import mean


def confidence(samples: int) -> str:
    if samples >= 8:
        return "high"
    if samples >= 4:
        return "medium"
    if samples >= 2:
        return "low"
    return "insufficient"


def unavailable(code: str, label: str, reason: str, samples: int = 0) -> dict:
    return {
        "code": code, "label": label, "status": "unavailable", "value": None,
        "unit": None, "direction": "unknown", "confidence": confidence(samples),
        "samples": samples, "message": reason,
    }


def split_change(values: list[float]) -> tuple[float, float, float]:
    midpoint = len(values) // 2
    early, late = mean(values[:midpoint]), mean(values[-midpoint:])
    return early, late, late - early


def trend_signal(code: str, label: str, values: list[float], unit: str,
                 relative: bool = False) -> dict:
    samples = len(values)
    if samples < 4:
        return unavailable(code, label, f"Needs at least 4 valid work sets; found {samples}.", samples)
    early, late, change = split_change(values)
    value = change / early * 100 if relative and early else change
    threshold = 10 if relative else 5
    direction = "higher" if value >= threshold else "lower" if value <= -threshold else "stable"
    wording = "increased" if value > 0 else "decreased" if value < 0 else "was unchanged"
    return {
        "code": code, "label": label, "status": "available", "value": round(value, 1),
        "unit": unit, "direction": direction, "confidence": confidence(samples),
        "samples": samples, "early": round(early, 1), "late": round(late, 1),
        "message": f"Late-session average {wording} by {abs(value):.1f}{unit} versus early sets.",
    }


def balance_signal(work: list[dict]) -> dict:
    unilateral = [lap for lap in work if lap.get("side") in ("Left", "Right")]
    if len(unilateral) < 4 or {lap["side"] for lap in unilateral} != {"Left", "Right"}:
        return unavailable(
            "side_balance", "Left/right exposure",
            "Needs at least 4 unilateral sets with both left and right represented.", len(unilateral),
        )
    totals = {"Left": 0.0, "Right": 0.0}
    for lap in unilateral:
        totals[lap["side"]] += float(lap.get("exposure") or lap.get("active_seconds") or lap["elapsed"])
    total = totals["Left"] + totals["Right"]
    left = totals["Left"] / total * 100 if total else 50.0
    difference = left - 50
    direction = "left" if difference >= 5 else "right" if difference <= -5 else "balanced"
    return {
        "code": "side_balance", "label": "Left/right exposure", "status": "available",
        "value": round(left, 1), "unit": "% left", "direction": direction,
        "confidence": confidence(len(unilateral)), "samples": len(unilateral),
        "left": round(left, 1), "right": round(100 - left, 1),
        "message": f"Recorded exposure was {left:.1f}% left and {100-left:.1f}% right.",
    }


def dropout_signal(report: dict) -> dict:
    elapsed = float(report["summary"].get("elapsed") or 0)
    times = sorted(float(point["t"]) for point in report["records"]
                   if point.get("rms") is not None or point.get("peak") is not None)
    if not elapsed or not times:
        return unavailable("sensor_dropout", "Motion continuity", "No motion series is available.")
    boundaries = [0.0, *times, elapsed]
    longest = max(max(0.0, end - start - 1.0) for start, end in zip(boundaries, boundaries[1:]))
    coverage = min(100.0, len(times) / max(1, round(elapsed)) * 100)
    direction = "gap" if longest >= 3 else "continuous"
    return {
        "code": "sensor_dropout", "label": "Motion continuity", "status": "available",
        "value": round(longest, 1), "unit": "s longest gap", "direction": direction,
        "confidence": "high", "samples": len(times), "coverage": round(coverage, 1),
        "message": f"Motion coverage was {coverage:.1f}%; longest missing interval was {longest:.1f}s.",
    }


def analyze(report: dict) -> dict:
    """Return descriptive signals; never injury, tendon-force, or readiness claims."""
    work = [lap for lap in report["laps"]
            if lap.get("phase") == "work" and lap.get("set", 0) > 0 and lap.get("elapsed", 0) >= 10]
    smoothness = [float(lap["smoothness"]) for lap in work
                  if isinstance(lap.get("smoothness"), (int, float)) and lap["smoothness"] >= 0]
    peaks = [float(lap["motion_peak"]) for lap in work
             if isinstance(lap.get("motion_peak"), (int, float)) and lap["motion_peak"] >= 0]
    signals = [
        trend_signal("smoothness_drift", "Smoothness drift", smoothness, " points"),
        trend_signal("peak_change", "Late-session peak change", peaks, "%", relative=True),
        balance_signal(work),
        dropout_signal(report),
    ]
    return {
        "signals": signals,
        "available": sum(signal["status"] == "available" for signal in signals),
        "disclaimer": "Descriptive session signals only—not tendon force, injury risk, or readiness.",
    }
