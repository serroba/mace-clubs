#!/usr/bin/env python3
"""Maintain a private local Workout Inspector history from FIT/ZIP exports."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from statistics import median

try:
    from validate_workout import load_report
except ModuleNotFoundError:
    from tools.validate_workout import load_report


METRICS = {
    "duration": "s",
    "work_seconds": "s",
    "sets": "sets",
    "motion_exposure": "mg-s",
    "active_seconds": "s",
    "weight_volume": "kg-swings",
    "motion_peak": "mg",
    "smoothness": "score",
}


def metric(laps: list[dict], name: str) -> float | None:
    values = [float(lap[name]) for lap in laps if isinstance(lap.get(name), (int, float)) and lap[name] >= 0]
    if not values:
        return None
    if name == "motion_peak":
        return max(values)
    if name == "smoothness":
        return sum(values) / len(values)
    return sum(values)


def summarize(report: dict, identifier: str, imported_at: str | None = None) -> dict:
    work = [lap for lap in report["laps"] if lap.get("phase") == "work" and lap.get("set", 0) > 0]
    return {
        "id": identifier,
        "imported_at": imported_at or datetime.now(timezone.utc).isoformat(),
        "date": report["summary"].get("date"),
        "movement": report["summary"].get("movement"),
        "side": report["summary"].get("side"),
        "equipment": report["summary"].get("equipment"),
        "sets": len(work),
        "duration": report["summary"].get("elapsed"),
        "metrics": {
            "duration": report["summary"].get("elapsed"),
            "work_seconds": report["summary"].get("work_seconds"),
            "sets": len(work),
            **{name: metric(work, name) for name in METRICS
               if name not in ("duration", "work_seconds", "sets")},
        },
    }


def comparisons(entries: list[dict], minimum: int = 3, window: int = 8) -> list[dict]:
    if not entries:
        return []
    current = entries[-1]
    previous = [item for item in entries[max(0, len(entries) - 1 - window):-1]
                if (item.get("metrics", {}).get("sets") or 0) > 0
                and (not current.get("movement") or current.get("movement") == "Unknown"
                     or item.get("movement") == current.get("movement"))
                and (not current.get("equipment") or item.get("equipment") == current.get("equipment"))]
    results = []
    for name, unit in METRICS.items():
        value = current["metrics"].get(name)
        baseline = [item["metrics"].get(name) for item in previous]
        baseline = [item for item in baseline if isinstance(item, (int, float)) and item > 0]
        if value is None or len(baseline) < minimum:
            results.append({"metric": name, "status": "unavailable", "samples": len(baseline)})
            continue
        typical = median(baseline)
        change = (value - typical) / typical * 100 if typical else None
        direction = "higher" if change is not None and change >= 25 else "lower" if change is not None and change <= -25 else "typical"
        results.append({
            "metric": name, "status": "available", "value": round(value, 1), "unit": unit,
            "baseline": round(typical, 1), "change_percent": round(change, 1) if change is not None else None,
            "direction": direction, "review": change is not None and abs(change) >= 50,
            "samples": len(baseline),
        })
    return results


def load(path: Path) -> dict:
    if not path.exists():
        return {"version": 1, "privacy": "local-summary-only", "workouts": []}
    return json.loads(path.read_text())


def save(path: Path, history: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(history, indent=2) + "\n")


def source_id(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12]


def import_source(history: dict, source: Path) -> dict:
    identifier = source_id(source)
    if any(item["id"] == identifier for item in history["workouts"]):
        return history
    history["workouts"].append(summarize(load_report(source), identifier))
    history["workouts"].sort(key=lambda item: datetime.strptime(item["date"], "%d %b %Y")
                             if item.get("date") else datetime.min)
    return history


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=Path("workout-history.json"))
    sub = parser.add_subparsers(dest="command", required=True)
    add = sub.add_parser("import"); add.add_argument("sources", nargs="+", type=Path)
    sub.add_parser("show")
    export = sub.add_parser("export"); export.add_argument("output", type=Path)
    delete = sub.add_parser("delete"); delete.add_argument("id")
    sub.add_parser("clear")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    history = load(args.database)
    if args.command == "import":
        for source in args.sources:
            import_source(history, source)
        save(args.database, history)
    elif args.command == "delete":
        history["workouts"] = [item for item in history["workouts"] if item["id"] != args.id]
        save(args.database, history)
    elif args.command == "clear":
        history["workouts"] = []
        save(args.database, history)
    elif args.command == "export":
        save(args.output, history)
    output = {**history, "latest_comparison": comparisons(history["workouts"])}
    print(json.dumps(output, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
