#!/usr/bin/env python3
"""Validate the contract between FIT resources and fields created in Monkey C."""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


FIELD_PATTERN = re.compile(
    r'createField\(\s*"(?P<name>[^"]+)"\s*,\s*(?P<id>FIELD_ID_[A-Z0-9_]+|\d+)\s*,\s*'
    r'FitContributor\.DATA_TYPE_(?P<data_type>[A-Z0-9_]+)\s*,\s*'
    r'\{\s*:mesgType\s*=>\s*FitContributor\.MESG_TYPE_(?P<message>[A-Z]+)\s*,'
    r'(?:(?!\}\s*\)).)*?:units\s*=>\s*"(?P<units>[^"]*)"',
    re.DOTALL,
)
CONSTANT_PATTERN = re.compile(r"const\s+(FIELD_ID_[A-Z0-9_]+)\s*=\s*(\d+)\s*;")
STRING_REF_PATTERN = re.compile(r"^@Strings\.(.+)$")


def validate(root: Path) -> list[str]:
    errors: list[str] = []
    source = (root / "source" / "WorkoutSession.mc").read_text(encoding="utf-8")
    constants = {name: int(value) for name, value in CONSTANT_PATTERN.findall(source)}
    created = {}
    for match in FIELD_PATTERN.finditer(source):
        details = match.groupdict()
        identifier = details["id"]
        if identifier.isdigit():
            field_id = int(identifier)
        elif identifier in constants:
            field_id = constants[identifier]
        else:
            errors.append(f"created FIT field uses unresolved id constant {identifier}")
            continue
        created[field_id] = details

    strings_root = ET.parse(root / "resources" / "strings" / "strings.xml").getroot()
    strings = {node.attrib["id"] for node in strings_root.findall("string")}
    fields_root = ET.parse(root / "resources" / "fitfields.xml").getroot()
    contributions = fields_root.findall("./fitContributions/fitField")

    seen_ids: set[int] = set()
    sort_orders: dict[str, set[int]] = {}
    for field in contributions:
        field_id = int(field.attrib["id"])
        if field_id in seen_ids:
            errors.append(f"FIT field id {field_id} is declared more than once")
        seen_ids.add(field_id)

        created_field = created.get(field_id)
        if created_field is None:
            errors.append(f"FIT field id {field_id} is not created by WorkoutSession")

        display_targets = [
            target
            for target in ("displayInChart", "displayInActivityLaps", "displayInActivitySummary")
            if field.attrib.get(target) == "true"
        ]
        if len(display_targets) != 1:
            errors.append(f"FIT field id {field_id} must have exactly one display target")
        elif "sortOrder" in field.attrib:
            order = int(field.attrib["sortOrder"])
            used = sort_orders.setdefault(display_targets[0], set())
            if order in used:
                errors.append(f"duplicate {display_targets[0]} sortOrder {order}")
            used.add(order)

        for attribute in ("dataLabel", "unitLabel", "chartTitle"):
            value = field.attrib.get(attribute)
            if value is None:
                continue
            reference = STRING_REF_PATTERN.match(value)
            if reference and reference.group(1) not in strings:
                errors.append(f"FIT field id {field_id} references missing string {value}")

        if field.attrib.get("displayInChart") == "true":
            if not field.attrib.get("chartTitle"):
                errors.append(f"chart field id {field_id} has no chartTitle")
            if created_field and created_field["message"] != "RECORD":
                errors.append(f"chart field id {field_id} must use MESG_TYPE_RECORD")
            unit_ref = STRING_REF_PATTERN.match(field.attrib.get("unitLabel", ""))
            expected_unit_string = "FitPeakUnit" if created_field and created_field["units"] == "mg" else None
            if expected_unit_string and (not unit_ref or unit_ref.group(1) != expected_unit_string):
                errors.append(f"chart field id {field_id} must display its recorded mg unit")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    errors = validate(args.root)
    if errors:
        print("FIT schema validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("FIT schema contract is valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
