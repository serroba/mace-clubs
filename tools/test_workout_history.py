import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.workout_history import comparisons, import_source, load, main, metric, summarize


def workout(value, identifier):
    metrics = {name: value for name in ("duration", "work_seconds", "sets", "motion_exposure", "active_seconds", "weight_volume", "motion_peak", "smoothness")}
    return {"id": identifier, "metrics": metrics}


class WorkoutHistoryTest(unittest.TestCase):
    def test_metric_aggregation(self):
        laps = [{"motion_exposure": 10, "motion_peak": 20, "smoothness": 60},
                {"motion_exposure": 15, "motion_peak": 18, "smoothness": 80}]
        self.assertEqual(metric(laps, "motion_exposure"), 25)
        self.assertEqual(metric(laps, "motion_peak"), 20)
        self.assertEqual(metric(laps, "smoothness"), 70)
        self.assertIsNone(metric(laps, "active_seconds"))

    def test_summary_excludes_time_series(self):
        report = {"summary": {"date": "16 Aug 2026", "movement": "Flow", "side": "Both", "elapsed": 60, "work_seconds": 20},
                  "laps": [{"phase": "work", "set": 1, "motion_exposure": 100}],
                  "records": [{"rms": 999}]}
        item = summarize(report, "abc", "now")
        self.assertEqual(item["metrics"]["motion_exposure"], 100)
        self.assertEqual(item["metrics"]["duration"], 60)
        self.assertNotIn("records", item)

    def test_comparison_uses_recent_personal_median(self):
        entries = [workout(value, str(value)) for value in (90, 100, 110, 150)]
        result = comparisons(entries)[0]
        self.assertEqual(result["baseline"], 100)
        self.assertEqual(result["change_percent"], 50)
        self.assertEqual(result["direction"], "higher")
        self.assertTrue(result["review"])

    def test_comparison_requires_three_prior_values(self):
        self.assertEqual(comparisons([workout(100, "a")])[0]["status"], "unavailable")

    def test_comparison_excludes_sessions_without_work_sets(self):
        entries = [workout(value, str(value)) for value in (90, 100, 110, 150)]
        entries[1]["metrics"]["sets"] = 0
        self.assertEqual(comparisons(entries)[0]["status"], "unavailable")

    def test_import_deduplicates_and_cli_deletes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / "a.fit"; source.write_bytes(b"fit")
            report = {"summary": {"elapsed": 10, "date": "16 Aug 2026"}, "laps": [], "records": []}
            history = {"version": 1, "privacy": "local-summary-only", "workouts": []}
            with patch("tools.workout_history.load_report", return_value=report):
                import_source(history, source); import_source(history, source)
            self.assertEqual(len(history["workouts"]), 1)
            database = root / "history.json"; database.write_text(json.dumps(history))
            identifier = history["workouts"][0]["id"]
            main(["--database", str(database), "delete", identifier])
            self.assertEqual(load(database)["workouts"], [])


if __name__ == "__main__":
    unittest.main()
