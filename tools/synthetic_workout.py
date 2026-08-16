#!/usr/bin/env python3
"""Build the reviewable FIT and visual fixture for the synthetic workout."""

from __future__ import annotations

import argparse
import math
import tempfile
from dataclasses import dataclass
from pathlib import Path

from fit_tool.base_type import BaseType
from fit_tool.developer_field import DeveloperField
from fit_tool.fit_file_builder import FitFileBuilder
from fit_tool.profile.messages.activity_message import ActivityMessage
from fit_tool.profile.messages.developer_data_id_message import DeveloperDataIdMessage
from fit_tool.profile.messages.field_description_message import FieldDescriptionMessage
from fit_tool.profile.messages.file_id_message import FileIdMessage
from fit_tool.profile.messages.lap_message import LapMessage
from fit_tool.profile.messages.record_message import RecordMessage
from fit_tool.profile.messages.session_message import SessionMessage
from fit_tool.profile.profile_type import FileType, Manufacturer


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "tools/baselines/synthetic-workout.svg"
START_MS = 1_700_000_000_000
SAMPLE_RATE = 25


@dataclass(frozen=True)
class Window:
    second: int
    phase: str
    style: str
    x: tuple[int, ...]
    y: tuple[int, ...]
    z: tuple[int, ...]
    rms: int
    peak: int
    crossings: int
    dynamic_rms: int
    dynamic_peak: int


def samples(style: str, second: int) -> tuple[tuple[int, ...], ...]:
    axes = [[], [], []]
    for index in range(SAMPLE_RATE):
        angle = 2 * math.pi * index / SAMPLE_RATE
        if style == "still":
            values = (0, 0, 1000)
        elif style == "smooth":
            amplitude = 560
            values = (
                round(amplitude * math.sin(angle)),
                round(amplitude * 0.55 * math.cos(angle)),
                round(1000 + amplitude * 0.22 * math.sin(2 * angle)),
            )
        elif style == "irregular":
            amplitude = 430 + ((second * 97 + index * 53) % 360)
            values = (
                round(amplitude * math.sin(angle + second * 0.17)),
                round(amplitude * 0.7 * math.cos(1.3 * angle)),
                round(1000 + amplitude * 0.3 * math.sin(2.4 * angle)),
            )
        elif style == "spike":
            values = (4200, -900, 1600) if index == 12 else (
                round(650 * math.sin(angle)),
                round(300 * math.cos(angle)),
                round(1000 + 160 * math.sin(2 * angle)),
            )
        else:
            raise ValueError(f"unknown motion style: {style}")
        for axis, value in zip(axes, values):
            axis.append(value)
    return tuple(tuple(axis) for axis in axes)


def features(x: tuple[int, ...], y: tuple[int, ...], z: tuple[int, ...]) -> tuple[int, ...]:
    magnitudes = [math.sqrt(a * a + b * b + c * c) for a, b, c in zip(x, y, z)]
    mean = sum(magnitudes) / len(magnitudes)
    means = tuple(sum(axis) / len(axis) for axis in (x, y, z))
    crossings = 0
    previous = 0
    for magnitude in magnitudes:
        sign = 1 if magnitude > mean else -1 if magnitude < mean else 0
        if sign and previous and sign != previous:
            crossings += 1
        if sign:
            previous = sign
    dynamic = [
        math.sqrt((a - means[0]) ** 2 + (b - means[1]) ** 2 + (c - means[2]) ** 2)
        for a, b, c in zip(x, y, z)
    ]
    return (
        int(math.sqrt(sum(value * value for value in magnitudes) / len(magnitudes))),
        int(max(magnitudes)),
        crossings,
        int(math.sqrt(sum(value * value for value in dynamic) / len(dynamic))),
        int(max(dynamic)),
    )


def workout() -> list[Window]:
    timeline = []
    for second in range(50):
        if second < 5 or 25 <= second < 30:
            phase, style = "rest", "still"
        elif second < 25:
            phase, style = "work", "smooth"
        else:
            phase, style = "work", "spike" if second == 42 else "irregular"
        x, y, z = samples(style, second)
        values = features(x, y, z)
        timeline.append(Window(second, phase, style, x, y, z, *values))
    return timeline


FIELD_TYPES = {
    0: ("total_sets", "sets", BaseType.UINT16, 2),
    1: ("battery_used", "%", BaseType.FLOAT32, 4),
    2: ("accel_rms", "mg", BaseType.UINT16, 2),
    3: ("accel_peak", "mg", BaseType.UINT16, 2),
    4: ("accel_zc", "crossings", BaseType.UINT8, 1),
    6: ("implement_count", "implements", BaseType.UINT8, 1),
    7: ("implement_weight", "g", BaseType.UINT16, 2),
    8: ("set_number", "set", BaseType.UINT16, 2),
    10: ("phase", "0=rest 1=work", BaseType.UINT8, 1),
    11: ("phase_duration", "s", BaseType.UINT16, 2),
    14: ("set_smoothness", "score", BaseType.SINT16, 2),
    17: ("total_swings", "swings", BaseType.UINT16, 2),
    18: ("swing_count", "swings", BaseType.UINT16, 2),
    19: ("motion_exposure", "mg-s", BaseType.UINT32, 4),
    20: ("motion_peak", "mg", BaseType.UINT16, 2),
    21: ("active_seconds", "s", BaseType.UINT16, 2),
    22: ("weight_volume", "kg-swings", BaseType.UINT32, 4),
    15: ("movement_type", "movement", BaseType.UINT8, 1),
    16: ("working_side", "side", BaseType.UINT8, 1),
    23: ("work_time", "s", BaseType.UINT32, 4),
    24: ("rest_time", "s", BaseType.UINT32, 4),
    26: ("implement_name", "", BaseType.STRING, 16),
}


def developer_field(field_id: int, value: int | float | str) -> DeveloperField:
    name, units, base_type, size = FIELD_TYPES[field_id]
    field = DeveloperField(
        developer_data_index=0, field_id=field_id, name=name,
        units=units, base_type=base_type, size=size,
    )
    field.set_value(0, value)
    return field


def build_fit(windows: list[Window], destination: Path) -> None:
    builder = FitFileBuilder(auto_define=True)
    file_id = FileIdMessage()
    file_id.type = FileType.ACTIVITY
    file_id.manufacturer = Manufacturer.DEVELOPMENT.value
    file_id.product = 1
    file_id.serial_number = 424242
    file_id.time_created = START_MS
    builder.add(file_id)

    developer = DeveloperDataIdMessage()
    developer.developer_data_index = 0
    developer.application_id = bytes.fromhex("6f0f19e1a0e14842a7b70ac011223344")
    developer.application_version = 999
    builder.add(developer)
    for field_id, (name, units, base_type, _) in FIELD_TYPES.items():
        description = FieldDescriptionMessage()
        description.developer_data_index = 0
        description.field_definition_number = field_id
        description.fit_base_type_id = base_type
        description.field_name = name
        description.units = units
        builder.add(description)

    for window in windows:
        record = RecordMessage(developer_fields=[
            developer_field(2, window.rms),
            developer_field(3, window.peak),
            developer_field(4, window.crossings),
        ])
        record.timestamp = START_MS + window.second * 1000
        record.heart_rate = 68 + round(window.second * 0.65) + (7 if window.phase == "work" else 0)
        builder.add(record)

    laps = [
        (0, 5, 0, 0, -1, 0),
        (5, 20, 1, 1, 88, 20),
        (25, 5, 0, 0, -1, 0),
        (30, 20, 1, 2, 61, 17),
    ]
    for index, (start, duration, phase, set_number, smoothness, swings) in enumerate(laps):
        segment = windows[start:start + duration]
        lap = LapMessage(developer_fields=[
            developer_field(8, set_number), developer_field(10, phase),
            developer_field(11, duration), developer_field(14, smoothness),
            developer_field(15, 4), developer_field(16, 3),
            developer_field(18, swings),
            developer_field(19, sum(item.dynamic_rms for item in segment)),
            developer_field(20, max(item.dynamic_peak for item in segment)),
            developer_field(21, duration if phase else 0),
            developer_field(22, 8 * swings if phase else 0),
        ])
        lap.message_index = index
        lap.start_time = START_MS + start * 1000
        lap.timestamp = START_MS + (start + duration) * 1000
        lap.total_elapsed_time = duration
        lap.total_timer_time = duration
        builder.add(lap)

    session = SessionMessage(developer_fields=[
        developer_field(0, 2), developer_field(1, 1.5),
        developer_field(6, 2), developer_field(7, 4000),
        developer_field(17, 37), developer_field(23, 40), developer_field(24, 10),
        developer_field(26, "Clubs: 2 x 4 kg"),
    ])
    session.start_time = START_MS
    session.timestamp = START_MS + 50_000
    session.total_elapsed_time = 50
    session.total_timer_time = 50
    session.avg_heart_rate = 91
    session.max_heart_rate = 107
    session.num_laps = len(laps)
    builder.add(session)

    activity = ActivityMessage()
    activity.timestamp = START_MS + 50_000
    activity.total_timer_time = 50
    activity.num_sessions = 1
    builder.add(activity)
    destination.parent.mkdir(parents=True, exist_ok=True)
    builder.build().to_file(str(destination))


def render_svg(windows: list[Window]) -> str:
    width, height = 960, 580
    left, right, top, chart_bottom = 72, 28, 92, 400
    chart_width = width - left - right
    maximum = max(item.peak for item in windows)
    x = lambda second: left + chart_width * second / (len(windows) - 1)
    y = lambda value: chart_bottom - (chart_bottom - top) * value / maximum
    points = lambda key: " ".join(f"{x(item.second):.1f},{y(getattr(item, key)):.1f}" for item in windows)
    backgrounds = []
    for start, duration, phase in ((0, 5, "Rest"), (5, 20, "Smooth"), (25, 5, "Rest"), (30, 20, "Irregular")):
        color = "#e9f0f7" if phase == "Rest" else "#fff0e9"
        backgrounds.append(
            f'<rect x="{x(start):.1f}" y="{top}" width="{chart_width * duration / 50:.1f}" '
            f'height="{chart_bottom-top}" fill="{color}"/><text x="{x(start)+8:.1f}" y="{top+20}" '
            f'font-size="13" fill="#6f6961">{phase}</text>'
        )
    bars = []
    for set_number, score, start in ((1, 88, 5), (2, 61, 30)):
        bar_x = 220 + (set_number - 1) * 260
        bar_height = score * 0.65
        bars.append(
            f'<rect x="{bar_x}" y="{565-bar_height:.1f}" width="110" height="{bar_height:.1f}" '
            f'rx="3" fill="#397a68"/><text x="{bar_x+55}" y="{553-bar_height:.1f}" '
            f'text-anchor="middle" font-size="16" fill="#24211d">{score}</text><text x="{bar_x+55}" '
            f'y="578" text-anchor="middle" font-size="13" fill="#6f6961">Set {set_number}</text>'
        )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<rect width="100%" height="100%" fill="#f7f5f1"/><text x="{left}" y="38" font-family="system-ui,sans-serif" font-size="25" font-weight="600" fill="#24211d">Synthetic motion confidence check</text>
<text x="{left}" y="64" font-family="system-ui,sans-serif" font-size="14" fill="#6f6961">Stillness → smooth periodic swings → rest → irregular swings with one deliberate spike</text>
<g font-family="system-ui,sans-serif">{''.join(backgrounds)}
<line x1="{left}" y1="{chart_bottom}" x2="{width-right}" y2="{chart_bottom}" stroke="#bdb7af"/>
<polyline points="{points('rms')}" fill="none" stroke="#bd3e14" stroke-width="3"/>
<polyline points="{points('peak')}" fill="none" stroke="#e4a02b" stroke-width="2"/>
<text x="{left}" y="425" font-size="13" fill="#bd3e14">Acceleration RMS</text><text x="220" y="425" font-size="13" fill="#b37813">Peak acceleration</text>
<text x="{left}" y="466" font-size="18" font-weight="600" fill="#24211d">Expected smoothness contrast</text>{''.join(bars)}</g></svg>'''


def generated_outputs(directory: Path) -> dict[Path, str | bytes]:
    windows = workout()
    fit_path = directory / "synthetic-workout.fit"
    build_fit(windows, fit_path)
    return {
        fit_path: fit_path.read_bytes(),
        directory / "synthetic-workout.svg": render_svg(windows),
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=Path("build/synthetic-workout"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    with tempfile.TemporaryDirectory(prefix="mace-synthetic-") as temporary:
        outputs = generated_outputs(Path(temporary))
        svg = next(value for path, value in outputs.items() if path.suffix == ".svg")
        if args.check:
            failures = []
            if not BASELINE.exists() or BASELINE.read_text() != svg:
                failures.append(f"visual baseline differs: regenerate {BASELINE}")
            if failures:
                raise SystemExit("\n".join(failures))
        args.output_dir.mkdir(parents=True, exist_ok=True)
        for source, content in outputs.items():
            destination = args.output_dir / source.name
            destination.write_bytes(content) if isinstance(content, bytes) else destination.write_text(content)
    print(args.output_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
