import importlib.util
import tempfile
import unittest
import zipfile
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
from io import StringIO
from pathlib import Path
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "report_fit", Path(__file__).with_name("report_fit.py")
)
REPORT_FIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT_FIT)


class Message:
    def __init__(self, **fields):
        self._values = fields
        self.fields = []

    def get_value(self, name):
        return self._values.get(name)


class Fit:
    def __init__(self, messages):
        self.messages = messages

    def get_messages(self, name):
        return self.messages.get(name, [])


class Field:
    def __init__(self, value):
        self.value = value


class SessionMessage(Message):
    def __init__(self, developer_values=None, **fields):
        super().__init__(**fields)
        self.fields = [Field(item) for item in (developer_values or [])]


class ReportFitTest(unittest.TestCase):
    def test_raw_fit_path_is_unchanged(self):
        source = Path("activity.fit")
        self.assertIs(REPORT_FIT.fit_path(source, Path("unused")), source)

    def test_non_datetime_has_no_timestamp(self):
        self.assertIsNone(REPORT_FIT.timestamp("yesterday"))

    def test_zip_chooses_activity_fit_and_ignores_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "export.zip"
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("other.fit", b"other")
                archive.writestr("nested/123_ACTIVITY.fit", b"activity")
            extracted = REPORT_FIT.fit_path(source, root / "out")
            self.assertEqual(extracted.name, "123_ACTIVITY.fit")
            self.assertEqual(extracted.read_bytes(), b"activity")

    def test_zip_without_fit_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "export.zip"
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("readme.txt", "nothing here")
            with self.assertRaisesRegex(ValueError, "contains no FIT"):
                REPORT_FIT.fit_path(source, root / "out")

    def test_collect_aligns_records_and_excludes_short_set(self):
        start = datetime(2026, 8, 16, tzinfo=timezone.utc)
        fit = Fit({
            "session": [Message(
                total_elapsed_time=35,
                total_timer_time=35,
                avg_heart_rate=80,
                max_heart_rate=110,
                total_sets=2,
            )],
            "lap": [
                Message(start_time=start, total_elapsed_time=30, phase=1,
                        set_number=1, movement_type=4, working_side=3,
                        set_smoothness=60),
                Message(start_time=start + timedelta(seconds=30),
                        total_elapsed_time=5, phase=1, set_number=2,
                        movement_type=4, working_side=3, set_smoothness=99),
            ],
            "record": [
                Message(timestamp=start + timedelta(seconds=1), heart_rate=70,
                        accel_rms=1200, accel_peak=2100, accel_zc=4),
            ],
            "activity": [Message(local_timestamp=start + timedelta(days=1))],
        })
        report = REPORT_FIT.collect(fit)
        self.assertEqual(report["summary"]["movement"], "Flow / other")
        self.assertEqual(report["summary"]["valid_sets"], 1)
        self.assertEqual(report["summary"]["work_seconds"], 35)
        self.assertEqual(report["records"][0]["t"], 1)
        self.assertEqual(report["summary"]["date"], "17 Aug 2026")

    def test_collect_reads_equipment_and_skips_incomplete_samples(self):
        start = datetime(2026, 8, 16, tzinfo=timezone.utc)
        fit = Fit({
            "session": [SessionMessage(
                developer_values=["unrelated", "Clubs: 2 x 4 kg"],
                start_time=start, total_elapsed_time=10, total_timer_time=10,
            )],
            "lap": [Message(start_time=None, total_elapsed_time=5)],
            "record": [Message(timestamp=None, heart_rate=80)],
        })
        report = REPORT_FIT.collect(fit)
        self.assertEqual(report["summary"]["equipment"], "Clubs: 2 x 4 kg")
        self.assertEqual(report["summary"]["date"], "16 Aug 2026")
        self.assertEqual(report["laps"], [])
        self.assertEqual(report["records"], [])

    def test_collect_requires_a_session(self):
        with self.assertRaisesRegex(ValueError, "contains no session"):
            REPORT_FIT.collect(Fit({}))

    def test_render_is_self_contained_and_marks_anomalies(self):
        report = {
            "summary": {"elapsed": 30, "timer": 30, "avg_hr": 80,
                        "max_hr": 110, "sets": 1, "movement": "Flow / other",
                        "side": "Two-handed", "work_seconds": 3,
                        "rest_seconds": 27, "valid_sets": 0},
            "laps": [{"phase": "work", "set": 1, "elapsed": 3,
                      "start": 0, "end": 3, "smoothness": 50,
                      "motion_peak": None, "swings": None}],
            "records": [{"t": 1, "hr": 80, "rms": 1000,
                         "peak": 2000, "zc": 4}],
        }
        rendered = REPORT_FIT.render(report, "Example <activity>")
        self.assertIn("<!doctype html>", rendered)
        self.assertNotIn("fetch(", rendered)
        self.assertIn("Set ${anomalies", rendered)
        self.assertIn("Example &lt;activity&gt;", rendered)
        self.assertIn("Work</span>", rendered)
        self.assertIn("Recording quality", rendered)
        self.assertIn('id="quality-score"', rendered)
        self.assertIn("set-1", rendered)
        self.assertIn('"status":"usable_with_gaps"', rendered)
        self.assertIn('"code":"sets.short"', rendered)
        self.assertIn('"target":"set-1"', rendered)

    def test_main_writes_report(self):
        start = datetime(2026, 8, 16, tzinfo=timezone.utc)
        fake_fit = Fit({
            "session": [Message(start_time=start, total_elapsed_time=10,
                                total_timer_time=10, avg_heart_rate=80,
                                max_heart_rate=90, total_sets=1)],
            "lap": [Message(start_time=start, total_elapsed_time=10,
                            phase=1, set_number=1, movement_type=0,
                            working_side=3, set_smoothness=60)],
            "record": [Message(timestamp=start, heart_rate=80,
                               accel_rms=1000, accel_peak=2000, accel_zc=4)],
        })
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "activity.fit"
            output = root / "report.html"
            source.write_bytes(b"placeholder")
            stdout = StringIO()
            with patch.object(REPORT_FIT, "FitFile", return_value=fake_fit), redirect_stdout(stdout):
                result = REPORT_FIT.main([str(source), "-o", str(output)])
            self.assertEqual(result, 0)
            self.assertIn("Mace &amp; Clubs", output.read_text())
            self.assertIn(str(output), stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
