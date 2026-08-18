import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fitparse import FitFile


SPEC = importlib.util.spec_from_file_location(
    "synthetic_workout", Path(__file__).with_name("synthetic_workout.py")
)
SYNTHETIC = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = SYNTHETIC
SPEC.loader.exec_module(SYNTHETIC)


class SyntheticWorkoutTest(unittest.TestCase):
    def test_scenario_has_expected_phases_and_deliberate_spike(self):
        windows = SYNTHETIC.workout()
        self.assertEqual(50, len(windows))
        self.assertEqual(10, sum(item.phase == "rest" for item in windows))
        self.assertEqual(40, sum(item.phase == "work" for item in windows))
        self.assertEqual("spike", windows[42].style)
        self.assertGreater(windows[42].peak, max(item.peak for item in windows[:42]))

    def test_still_window_preserves_gravity_but_has_no_dynamic_motion(self):
        still = SYNTHETIC.workout()[0]
        self.assertEqual((1000, 1000, 0, 0, 0), (
            still.rms, still.peak, still.crossings,
            still.dynamic_rms, still.dynamic_peak,
        ))

    def test_unknown_motion_style_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "unknown motion style"):
            SYNTHETIC.samples("teleporting", 0)

    def test_generated_fit_round_trips_developer_fields(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "synthetic.fit"
            SYNTHETIC.build_fit(SYNTHETIC.workout(), path)
            fit = FitFile(str(path))
            records = list(fit.get_messages("record"))
            self.assertEqual(50, len(records))
            self.assertEqual(1000, records[0].get_value("accel_rms"))
            self.assertEqual(SYNTHETIC.workout()[42].peak, records[42].get_value("accel_peak"))
            events = [record.get_value("swing_event") for record in records]
            self.assertGreater(sum(events), 0)
            self.assertEqual(sum(events), records[-1].get_value("swing_total"))
            self.assertTrue(all(record.get_value("swing_cadence") is not None for record in records))
            smoothness = [record.get_value("smoothness_score") for record in records]
            self.assertTrue(all(score is not None for score in smoothness))
            self.assertTrue(any(score > 0 for score in smoothness))
            self.assertTrue(all(0 <= score <= 100 for score in smoothness))
            sessions = list(fit.get_messages("session"))
            self.assertEqual(2, sessions[0].get_value("total_sets"))
            self.assertEqual(40, sessions[0].get_value("work_time"))
            laps = list(fit.get_messages("lap"))
            self.assertEqual([0, 1, 0, 2], [lap.get_value("set_number") for lap in laps])
            self.assertEqual([0, 1, 0, 1], [lap.get_value("phase") for lap in laps])

    def test_visual_is_deterministic(self):
        windows = SYNTHETIC.workout()
        svg = SYNTHETIC.render_svg(windows)
        self.assertEqual(SYNTHETIC.BASELINE.read_text(), svg)
        self.assertIn("deliberate spike", svg)

    def test_cli_generates_all_review_artifacts(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "artifacts"
            self.assertEqual(0, SYNTHETIC.main(["--output-dir", str(output)]))
            self.assertEqual(
                {"synthetic-workout.fit", "synthetic-workout.svg"},
                {path.name for path in output.iterdir()},
            )

    def test_check_mode_accepts_reviewed_outputs_and_rejects_drift(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline = root / "baseline.svg"
            baseline.write_text(SYNTHETIC.render_svg(SYNTHETIC.workout()))
            with patch.object(SYNTHETIC, "BASELINE", baseline):
                self.assertEqual(0, SYNTHETIC.main(["--check", "--output-dir", str(root / "ok")]))
                baseline.write_text("changed")
                with self.assertRaisesRegex(SystemExit, "visual baseline differs"):
                    SYNTHETIC.main(["--check", "--output-dir", str(root / "bad")])


if __name__ == "__main__":
    unittest.main()
