import unittest

from tools.analyze_workout import analyze, confidence


def report(laps, records=None, elapsed=60):
    return {"summary": {"elapsed": elapsed}, "laps": laps, "records": records or []}


def work(number, smoothness, peak, side="Two-handed", exposure=100):
    return {"phase": "work", "set": number, "elapsed": 20, "smoothness": smoothness,
            "motion_peak": peak, "side": side, "exposure": exposure}


class AnalyzeWorkoutTest(unittest.TestCase):
    def test_confidence_thresholds(self):
        self.assertEqual([confidence(n) for n in (0, 2, 4, 8)],
                         ["insufficient", "low", "medium", "high"])

    def test_detects_smoothness_decline_and_peak_increase(self):
        laps = [work(i + 1, score, peak) for i, (score, peak) in enumerate([
            (90, 1000), (88, 1050), (86, 1100), (84, 1150),
            (72, 1400), (70, 1450), (68, 1500), (66, 1550),
        ])]
        result = analyze(report(laps))
        smooth, peak = result["signals"][:2]
        self.assertEqual((smooth["direction"], smooth["confidence"]), ("lower", "high"))
        self.assertEqual((peak["direction"], peak["confidence"]), ("higher", "high"))
        self.assertLess(smooth["value"], -15)
        self.assertGreater(peak["value"], 30)

    def test_small_sample_is_unavailable(self):
        result = analyze(report([work(1, 80, 1000), work(2, 70, 1200)]))
        self.assertEqual(result["signals"][0]["status"], "unavailable")
        self.assertEqual(result["signals"][0]["samples"], 2)

    def test_left_right_balance_uses_exposure(self):
        laps = [work(1, 80, 1000, "Left", 200), work(2, 80, 1000, "Right", 100),
                work(3, 80, 1000, "Left", 200), work(4, 80, 1000, "Right", 100)]
        signal = analyze(report(laps))["signals"][2]
        self.assertEqual(signal["direction"], "left")
        self.assertAlmostEqual(signal["left"], 66.7)

    def test_two_handed_sets_do_not_claim_balance(self):
        laps = [work(i, 80, 1000) for i in range(1, 9)]
        self.assertEqual(analyze(report(laps))["signals"][2]["status"], "unavailable")

    def test_dropout_detects_missing_interval(self):
        records = [{"t": second, "rms": 1000} for second in [0, 1, 2, 8, 9]]
        signal = analyze(report([], records, elapsed=10))["signals"][3]
        self.assertEqual(signal["direction"], "gap")
        self.assertEqual(signal["value"], 5.0)
        self.assertEqual(signal["coverage"], 50.0)

    def test_no_motion_reports_unavailable(self):
        result = analyze(report([]))
        self.assertEqual(result["signals"][3]["status"], "unavailable")
        self.assertIn("not tendon force", result["disclaimer"])


if __name__ == "__main__":
    unittest.main()
