import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Dev/CI-only grid search for SwingCounter's gyro parameters, run directly
// against the real production Counter (SwingCounter.maceCounterWithGyroParams)
// and the recorded replay fixtures - not a second reimplementation of the
// algorithm. Excluded from every normal build and test run (see the
// swingTuning exclusion in monkey.jungle and monkey.local.jungle); run
// explicitly with `make tuning-search`.
//
// Uses the *Tuning fixtures (RecordedFixtureRecBTuning/RecCTuning), not the
// small committed RecordedFixtureRecB/RecC - those stay at the recorded
// ~12.5Hz decimated rate, which is fine for regression testing but WRONG
// for tuning: GYRO_SMOOTHING_SAMPLES/GYRO_MIN_GAP_SAMPLES are sample counts
// meant for true 25Hz input, so decimated data makes any window/refractory
// setting look like it spans double the real time it would in production.
// The *Tuning fixtures are gitignored and dev-local; regenerate before
// running this (see Makefile's tuning-search target).
//
// This optimizes against only two labelled gyro recordings (recB, recC) - a
// real overfitting risk on N=2. Treat its output as a starting point for
// physical validation on more recordings, not a settled answer.
(:test, :swingTuning)
module SwingTuningSearch {
    const REC_B_REAL = [5, 5, 10, 10];
    const REC_C_REAL = [60, 60];

    function absError(detected as Array<Number>, real as Array<Number>) as Number {
        var error = 0;
        var n = detected.size() < real.size() ? detected.size() : real.size();
        for (var i = 0; i < n; i += 1) {
            var diff = detected[i] - real[i];
            error += diff < 0 ? -diff : diff;
        }
        // A mismatched set count means the replay's own work/rest
        // segmentation broke, not that the tuning is bad - penalize hard so
        // it never looks competitive.
        var sizeDiff = detected.size() - real.size();
        error += (sizeDiff < 0 ? -sizeDiff : sizeDiff) * 1000;
        return error;
    }

    function printCombo(
        label as String,
        thresholdDps as Float,
        smoothingSamples as Number,
        minGapSamples as Number
    ) as Void {
        var recB = RecordedSwingReplay.replayWithCounter(
            RecordedFixtureRecBTuning.seconds(),
            SwingCounter.maceCounterWithGyroParams(thresholdDps, smoothingSamples, minGapSamples)
        );
        var recC = RecordedSwingReplay.replayWithCounter(
            RecordedFixtureRecCTuning.seconds(),
            SwingCounter.maceCounterWithGyroParams(thresholdDps, smoothingSamples, minGapSamples)
        );
        var recBPerSet = recB.get(:perSet) as Array<Number>;
        var recCPerSet = recC.get(:perSet) as Array<Number>;
        var recBError = absError(recBPerSet, REC_B_REAL);
        var recCError = absError(recCPerSet, REC_C_REAL);
        System.println(
            Lang.format(
                "$1$,$2$,$3$,$4$,$5$,$6$,$7$,$8$,$9$",
                [
                    label,
                    thresholdDps,
                    smoothingSamples,
                    minGapSamples,
                    recBError,
                    recCError,
                    recBError + recCError,
                    recBPerSet,
                    recCPerSet
                ]
            )
        );
    }

    (:test)
    function testSwingTuningGridSearch(logger as Test.Logger) as Boolean {
        System.println(
            "label,thresholdDps,smoothingSamples,minGapSamples,recBError,recCError,combinedError,recBPerSet,recCPerSet"
        );
        printCombo(
            "current",
            SwingCounter.GYRO_THRESHOLD_DPS,
            SwingCounter.GYRO_SMOOTHING_SAMPLES,
            SwingCounter.GYRO_MIN_GAP_SAMPLES
        );

        var thresholds = [150.0, 175.0, 200.0, 225.0, 250.0, 275.0, 300.0] as Array<Float>;
        var smoothingOptions = [11, 15, 19, 22, 26, 30] as Array<Number>;
        var gapOptions = [12, 19, 25, 31, 38, 50] as Array<Number>;

        for (var ti = 0; ti < thresholds.size(); ti += 1) {
            for (var si = 0; si < smoothingOptions.size(); si += 1) {
                for (var gi = 0; gi < gapOptions.size(); gi += 1) {
                    printCombo("grid", thresholds[ti], smoothingOptions[si], gapOptions[gi]);
                }
            }
        }
        return true;
    }
}
