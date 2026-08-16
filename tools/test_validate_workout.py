import json
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from tools import report_fit as REPORT_FIT
from tools import validate_workout as VALIDATOR


def healthy_report():
    return {
        "summary": {"elapsed": 20, "sets": 1, "movement": "Flow / other",
                    "side": "Two-handed", "equipment": "Clubs: 2 x 4 kg"},
        "laps": [{"lap": 1, "start": 0, "end": 20, "elapsed": 20,
                  "phase": "work", "set": 1, "smoothness": 80,
                  "motion_peak": 2200, "exposure": 1000,
                  "active_seconds": 18, "swings": 20}],
        "records": [{"t": second, "rms": 1000, "peak": 2000, "hr": 90}
                    for second in range(20)],
    }


class ValidateWorkoutTest(unittest.TestCase):
    def test_healthy_recording_scores_100(self):
        result = VALIDATOR.validate(healthy_report())
        self.assertEqual(result["status"], "healthy")
        self.assertEqual(result["score"], 100)
        self.assertEqual(result["counts"], {"errors": 0, "warnings": 0})
        self.assertEqual(result["observed"]["work_laps"], 1)

    def test_gaps_and_metadata_are_explained(self):
        report = healthy_report()
        report["summary"].update(sets=2, movement="Unknown", side="Unknown", equipment=None)
        report["records"] = report["records"][:5]
        result = VALIDATOR.validate(report)
        codes = {item["code"] for item in result["findings"]}
        self.assertEqual(result["status"], "usable_with_gaps")
        self.assertTrue({"sets.total_mismatch", "motion.coverage", "heart_rate.coverage",
                         "metadata.movement", "metadata.side", "metadata.equipment"} <= codes)

    def test_motion_is_optional_when_logging_is_off(self):
        report = healthy_report()
        report["records"] = [{"t": second, "rms": None, "peak": None, "hr": 90}
                             for second in range(20)]
        result = VALIDATOR.validate(report)
        self.assertEqual(result["status"], "healthy")
        self.assertIn("motion.unavailable", {item["code"] for item in result["findings"]})

    def test_structural_and_range_errors_fail(self):
        report = healthy_report()
        report["summary"]["elapsed"] = 0
        report["laps"] = [
            {"lap": 1, "start": 0, "end": 10, "elapsed": 9, "phase": "work",
             "set": 2, "smoothness": 101, "motion_peak": -1, "exposure": -2,
             "active_seconds": -3, "swings": -4},
            {"lap": 2, "start": 8.5, "end": 15, "elapsed": 6.5, "phase": "rest", "set": 0},
        ]
        report["records"] = [{"t": 1, "rms": -1, "peak": -2, "hr": None}]
        result = VALIDATOR.validate(report)
        codes = {item["code"] for item in result["findings"]}
        self.assertEqual(result["status"], "invalid")
        self.assertEqual(result["score"], 0)
        self.assertTrue({"session.duration", "sets.sequence", "laps.overlap",
                         "sets.short", "smoothness.range", "motion_peak.negative", "motion.negative",
                         "heart_rate.unavailable"} <= codes)

    def test_subsecond_lap_boundary_rounding_is_allowed(self):
        report = healthy_report()
        report["laps"] = [
            {"lap": 1, "start": 0, "end": 10.4, "elapsed": 10.4, "phase": "work",
             "set": 1, "smoothness": 80},
            {"lap": 2, "start": 10, "end": 20, "elapsed": 9.6, "phase": "rest", "set": 0},
        ]
        result = VALIDATOR.validate(report)
        self.assertNotIn("laps.overlap", {item["code"] for item in result["findings"]})

    def test_set_finding_links_to_affected_set(self):
        report = healthy_report()
        report["laps"][0]["elapsed"] = 3
        result = VALIDATOR.validate(report)
        short = next(item for item in result["findings"] if item["code"] == "sets.short")
        self.assertEqual(short["target"], "set-1")

    def test_missing_laps_is_invalid(self):
        report = healthy_report()
        report["laps"] = []
        result = VALIDATOR.validate(report)
        self.assertEqual(result["status"], "invalid")
        self.assertIn("laps.missing", {item["code"] for item in result["findings"]})

    def test_laps_without_numbered_work_are_invalid(self):
        report = healthy_report()
        report["summary"]["sets"] = 0
        report["laps"] = [{"lap": 1, "start": 0, "end": 20, "elapsed": 20,
                           "phase": "rest", "set": 0}]
        result = VALIDATOR.validate(report)
        self.assertEqual(result["status"], "invalid")
        self.assertIn("laps.no_work", {item["code"] for item in result["findings"]})

    def test_peak_below_rms_and_duration_mismatch_warn(self):
        report = healthy_report()
        report["summary"]["elapsed"] = 30
        report["records"] = [{"t": second, "rms": 2000, "peak": 1000, "hr": 90}
                             for second in range(30)]
        result = VALIDATOR.validate(report)
        codes = {item["code"] for item in result["findings"]}
        self.assertIn("motion.peak_below_rms", codes)
        self.assertIn("laps.duration_mismatch", codes)

    def test_text_and_json_cli(self):
        text = VALIDATOR.render_text(VALIDATOR.validate(healthy_report()))
        self.assertIn("healthy (100/100)", text)
        self.assertIn("No integrity", text)

        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "activity.fit"
            source.write_bytes(b"placeholder")
            stdout = StringIO()
            with patch.object(VALIDATOR, "load_report", return_value=healthy_report()), \
                 redirect_stdout(stdout):
                code = VALIDATOR.main([str(source), "--json"])
            self.assertEqual(code, 0)
            self.assertEqual(json.loads(stdout.getvalue())["score"], 100)

    def test_cli_fails_for_structural_errors(self):
        report = healthy_report()
        report["laps"] = []
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "activity.fit"
            source.write_bytes(b"placeholder")
            stdout = StringIO()
            with patch.object(VALIDATOR, "load_report", return_value=report), \
                 redirect_stdout(stdout):
                code = VALIDATOR.main([str(source)])
            self.assertEqual(code, 1)
            self.assertIn("ERROR", stdout.getvalue())

    def test_load_report_uses_shared_parser(self):
        source = Path("activity.fit")
        parsed = object()
        expected = healthy_report()
        with patch.object(REPORT_FIT, "fit_path", return_value=source), \
             patch.object(REPORT_FIT, "collect", return_value=expected), \
             patch.object(VALIDATOR, "FitFile", return_value=parsed) as fit_file:
            result = VALIDATOR.load_report(source)
        self.assertIs(result, expected)
        fit_file.assert_called_once_with(str(source))


if __name__ == "__main__":
    unittest.main()
