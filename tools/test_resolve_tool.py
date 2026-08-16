import os
import tempfile
import unittest
from pathlib import Path

from tools.resolve_tool import resolve


def executable(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch()
    path.chmod(0o755)
    return path


def working_executable(path: Path) -> Path:
    executable(path)
    path.write_text("#!/bin/sh\nexit 0\n")
    return path


class ResolveToolTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.home = Path(self.tempdir.name)

    def tearDown(self):
        self.tempdir.cleanup()

    def test_path_takes_precedence(self):
        expected = executable(self.home / "path-bin" / "monkeyc")
        self.assertEqual(str(expected), resolve("monkeyc", self.home, str(expected.parent)))

    def test_macos_sdk_manager_config_is_used(self):
        sdk = self.home / "Garmin SDK"
        expected = executable(sdk / "bin" / "monkeyc")
        config = self.home / "Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
        config.parent.mkdir(parents=True)
        config.write_text(f"{sdk}/\n")
        self.assertEqual(str(expected), resolve("monkeyc", self.home, ""))

    def test_linux_sdk_manager_config_is_used(self):
        sdk = self.home / "connectiq-sdk"
        expected = executable(sdk / "bin" / "monkeydo")
        config = self.home / ".Garmin/ConnectIQ/current-sdk.cfg"
        config.parent.mkdir(parents=True)
        config.write_text(str(sdk))
        self.assertEqual(str(expected), resolve("monkeydo", self.home, ""))

    def test_cargo_bin_is_used_for_rust_tools(self):
        expected = executable(self.home / ".cargo/bin/monkey-c-linter")
        self.assertEqual(str(expected), resolve("monkey-c-linter", self.home, ""))

    def test_missing_tool_returns_conventional_name(self):
        self.assertEqual("monkeyc", resolve("monkeyc", self.home, ""))

    def test_working_java_on_path_is_used(self):
        expected = working_executable(self.home / "jdk/bin/java")
        self.assertEqual(str(expected), resolve("java", self.home, str(expected.parent)))

    def test_broken_java_on_path_is_ignored(self):
        broken = executable(self.home / "broken/bin/java")
        self.assertNotEqual(str(broken), resolve("java", self.home, str(broken.parent)))


if __name__ == "__main__":
    unittest.main()
