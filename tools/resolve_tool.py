#!/usr/bin/env python3
"""Resolve local Connect IQ and Rust tools without depending on shell startup."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


CONNECT_IQ_TOOLS = {"connectiq", "monkeyc", "monkeydo", "monkeygraph"}
RUST_TOOLS = {"monkey-c-formatter", "monkey-c-linter", "rafiki"}


def working_java(candidate: Path) -> bool:
    try:
        result = subprocess.run(
            [candidate, "-version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def resolve(tool: str, home: Path, path: str) -> str:
    on_path = shutil.which(tool, path=path)
    if on_path and (tool != "java" or working_java(Path(on_path))):
        return on_path

    if tool == "java":
        java_home = os.environ.get("JAVA_HOME")
        candidates = [
            Path(java_home) / "bin/java" if java_home else None,
            Path("/opt/homebrew/opt/openjdk/bin/java"),
            Path("/usr/local/opt/openjdk/bin/java"),
        ]
        for candidate in candidates:
            if candidate and working_java(candidate):
                return str(candidate)

    if tool in CONNECT_IQ_TOOLS:
        configs = (
            home / "Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg",
            home / ".Garmin/ConnectIQ/current-sdk.cfg",
        )
        for config in configs:
            try:
                sdk = Path(config.read_text(encoding="utf-8").strip())
            except OSError:
                continue
            candidate = sdk / "bin" / tool
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return str(candidate)

    if tool in RUST_TOOLS:
        candidate = home / ".cargo" / "bin" / tool
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)

    # Preserve the conventional command name so Make's doctor target can
    # report an actionable missing-tool error.
    return tool


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} TOOL", file=sys.stderr)
        return 2
    print(resolve(sys.argv[1], Path.home(), os.environ.get("PATH", "")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
