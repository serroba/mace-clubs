#!/usr/bin/env python3
"""Offline analysis of Mace & Clubs FIT activities.

Reads the raw FIT exported from Garmin Connect ("Export Original") or copied
from GARMIN/Activity on the watch, prints the app's developer fields per
session and per lap, and — when the activity was recorded with the Motion
logging setting on — sweeps swing-detection thresholds over the per-second
accelerometer features to ground SwingCounter.HIGH_MG in real data.

Usage:
    tools/.venv/bin/python tools/analyze_fit.py path/to/activity.fit [more.fit ...]

Everything runs locally; nothing is uploaded anywhere.
"""

import sys
from collections import defaultdict

try:
    from fitparse import FitFile
except ImportError:
    sys.exit("fitparse missing - run: tools/.venv/bin/pip install fitparse")

MOVEMENT_LABELS = {
    0: "360",
    1: "10-to-2",
    2: "Mill",
    3: "Shield cast",
    4: "Flow / other",
    5: "Reverse mill",
    6: "Bullwhip",
}
SIDE_LABELS = {0: "Left", 1: "Right", 2: "Alternating", 3: "Two-handed"}
EQUIPMENT_LABELS = {0: "Mace", 1: "Clubs", 2: "Bulava"}

# Threshold sweep for SwingCounter calibration (milli-g). The shipped
# defaults are HIGH_MG=1800 / LOW_MG=1300.
SWEEP_MG = [1200, 1400, 1600, 1800, 2000, 2200, 2500, 3000]


def field(message, name, default=None):
    value = message.get_value(name)
    return default if value is None else value


def print_session(fit):
    # The store numbers each upload; sideloads report the developer's own
    # build. Either way it identifies which app build recorded the file.
    for dev_id in fit.get_messages("developer_data_id"):
        version = field(dev_id, "application_version")
        if version is not None:
            print(f"app build (application_version): {version}")
    for session in fit.get_messages("session"):
        print("== Session ==")
        for name in (
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
        ):
            value = field(session, name)
            if value is None:
                continue
            if name == "implement_type":
                value = EQUIPMENT_LABELS.get(value, value)
            print(f"  {name}: {value}")


def lap_windows(fit):
    """Return (start, end, is_work) per lap.

    Newer app versions write an explicit phase developer field; older ones
    only carry set_number, where work laps are 1-based and rest laps zero.
    """
    windows = []
    for lap in fit.get_messages("lap"):
        start = field(lap, "start_time")
        elapsed = field(lap, "total_elapsed_time")
        if start is None or elapsed is None:
            continue
        phase = field(lap, "phase")
        if phase is not None:
            is_work = phase == 1
        else:
            is_work = (field(lap, "set_number") or 0) > 0
        end_ts = start.timestamp() + elapsed
        windows.append((start.timestamp(), end_ts, is_work))
    return windows


def print_laps(fit):
    print("== Laps ==")
    header = "  {:>3} {:>4} {:>5} {:>6} {:>13} {:>11} {:>7} {:>7} {:>7}".format(
        "lap", "set", "phase", "dur_s", "movement", "side", "weight", "smooth", "swings"
    )
    print(header)
    for index, lap in enumerate(fit.get_messages("lap")):
        phase = field(lap, "phase")
        print(
            "  {:>3} {:>4} {:>5} {:>6} {:>13} {:>11} {:>7} {:>7} {:>7}".format(
                index + 1,
                str(field(lap, "set_number", "-")),
                {1: "work", 0: "rest"}.get(phase, "-"),
                str(field(lap, "phase_duration", "-")),
                MOVEMENT_LABELS.get(field(lap, "movement_type"), "-"),
                SIDE_LABELS.get(field(lap, "working_side"), "-"),
                str(field(lap, "implement_weight", "-")),
                str(field(lap, "set_smoothness", "-")),
                str(field(lap, "swing_count", "-")),
            )
        )


def analyze_motion(fit):
    """Threshold sweep over per-second accel_peak, split work vs rest."""
    windows = lap_windows(fit)
    peaks = {"work": [], "rest": []}
    for record in fit.get_messages("record"):
        peak = field(record, "accel_peak")
        timestamp = field(record, "timestamp")
        if peak is None or timestamp is None:
            continue
        ts = timestamp.timestamp()
        bucket = "rest"
        for start, end, is_work in windows:
            if start <= ts <= end:
                bucket = "work" if is_work else "rest"
                break
        peaks[bucket].append(peak)

    if not peaks["work"] and not peaks["rest"]:
        print("== Motion ==")
        print("  no accel features found (record with Motion logging ON to calibrate)")
        return

    print("== Motion (per-second accel_peak, mg) ==")
    for bucket in ("work", "rest"):
        values = sorted(peaks[bucket])
        if not values:
            print(f"  {bucket}: no samples")
            continue
        mid = values[len(values) // 2]
        p90 = values[int(len(values) * 0.9)]
        print(
            f"  {bucket}: n={len(values)} min={values[0]} median={mid} "
            f"p90={p90} max={values[-1]}"
        )

    print("  threshold sweep (% of seconds with peak >= threshold):")
    print("  {:>9} {:>7} {:>7}".format("mg", "work", "rest"))
    for threshold in SWEEP_MG:
        row = {}
        for bucket in ("work", "rest"):
            values = peaks[bucket]
            row[bucket] = (
                100.0 * sum(1 for v in values if v >= threshold) / len(values)
                if values
                else 0.0
            )
        marker = " <- shipped HIGH_MG" if threshold == 1800 else ""
        print(
            "  {:>9} {:>6.1f}% {:>6.1f}%{}".format(
                threshold, row["work"], row["rest"], marker
            )
        )
    print(
        "  A good HIGH_MG keeps the work column near your real swing cadence\n"
        "  (one crossing per swing-second) while the rest column stays ~0."
    )


def main(paths):
    if not paths:
        sys.exit(__doc__)
    for path in paths:
        print(f"\n### {path}")
        fit = FitFile(path)
        print_session(fit)
        print_laps(fit)
        analyze_motion(fit)


if __name__ == "__main__":
    main(sys.argv[1:])
