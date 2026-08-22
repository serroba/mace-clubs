import Toybox.Lang;
import Toybox.Test;

// Builds one axis of a synthetic 25Hz second: baseline samples with a
// spike of the given magnitude at the given index. The other axes stay 0
// so the sample magnitude equals the axis value.
function swingTestSecond(spikeAt as Number, spikeMg as Number, baselineMg as Number) as Array<Number> {
    var samples = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
    for (var i = 0; i < samples.size(); i++) {
        samples[i] = i == spikeAt ? spikeMg : baselineMg;
    }
    return samples;
}

function swingTestZeros() as Array<Number> {
    var samples = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
    for (var i = 0; i < samples.size(); i++) {
        samples[i] = 0;
    }
    return samples;
}

(:test)
function testSwingCounterCountsSpacedPeaks(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    for (var second = 0; second < 3; second++) {
        counter.addSamples(swingTestSecond(12, 2500, 1000), swingTestZeros(), swingTestZeros());
    }
    Test.assertEqualMessage(counter.getCount(), 3, "one peak per second counts one swing per second");
    return true;
}

(:test)
function testSwingCounterIgnoresRestingBaseline(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    for (var second = 0; second < 5; second++) {
        counter.addSamples(swingTestSecond(12, 1050, 980), swingTestZeros(), swingTestZeros());
    }
    Test.assertEqualMessage(counter.getCount(), 0, "gravity plus noise never crosses the swing threshold");
    return true;
}

(:test)
function testSwingCounterNeedsReArmBelowLowThreshold(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    // A sustained above-threshold plateau is one swing, not one per sample.
    var plateau = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
    for (var i = 0; i < plateau.size(); i++) {
        plateau[i] = 2200;
    }
    counter.addSamples(plateau, swingTestZeros(), swingTestZeros());
    counter.addSamples(plateau, swingTestZeros(), swingTestZeros());
    Test.assertEqualMessage(counter.getCount(), 1, "staying above threshold counts once");
    counter.addSamples(swingTestSecond(12, 2500, 1000), swingTestZeros(), swingTestZeros());
    Test.assertEqualMessage(counter.getCount(), 2, "dropping to baseline re-arms the counter");
    return true;
}

(:test)
function testSwingCounterEnforcesRefractoryGap(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    // Two sharp peaks 8 samples (~0.3s) apart within one second: the second
    // is armed (magnitude dipped) but inside the refractory window.
    var samples = swingTestSecond(4, 2500, 1000);
    samples[12] = 2500;
    counter.addSamples(samples, swingTestZeros(), swingTestZeros());
    Test.assertEqualMessage(counter.getCount(), 1, "peaks closer than the refractory gap count once");
    return true;
}

(:test)
function testSwingCounterUsesAllAxes(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    // 1560mg on two axes combines to ~2206mg magnitude, above threshold.
    counter.addSamples(swingTestSecond(12, 1560, 700), swingTestSecond(12, 1560, 700), swingTestZeros());
    Test.assertEqualMessage(counter.getCount(), 1, "magnitude combines the axes");
    return true;
}

(:test)
function testSwingCounterResets(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    counter.addSamples(swingTestSecond(12, 2500, 1000), swingTestZeros(), swingTestZeros());
    Test.assertEqualMessage(counter.getCount(), 1, "counted before reset");
    counter.reset();
    Test.assertEqualMessage(counter.getCount(), 0, "reset clears the count");
    counter.addSamples(swingTestSecond(12, 2500, 1000), swingTestZeros(), swingTestZeros());
    Test.assertEqualMessage(counter.getCount(), 1, "counting resumes after reset");
    return true;
}

(:test)
function testSwingCounterManualCorrectionNeverGoesNegative(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    counter.adjust(-1);
    Test.assertEqualMessage(counter.getCount(), 0, "correction floors at zero");
    counter.adjust(1);
    Test.assertEqualMessage(counter.getCount(), 1, "positive correction adds one");
    return true;
}

(:test)
function testMaceCounterIgnoresABriefDipThatDefaultTreatsAsANewSwing(logger as Test.Logger) as Boolean {
    var defaultCounter = SwingCounter.defaultCounter();
    var maceCounter = SwingCounter.maceCounter(SwingCounter.MACE_HIGH_MG);

    var swing = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
    for (var i = 0; i < swing.size(); i++) {
        swing[i] = 2200;
    }
    defaultCounter.addSamples(swing, swingTestZeros(), swingTestZeros());
    maceCounter.addSamples(swing, swingTestZeros(), swingTestZeros());

    // A 2-sample dip (~80ms) below LOW_MG followed by a rise back past
    // HIGH_MG: real in-swing noise, not a return to baseline.
    var brieflyDips = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
    for (var j = 0; j < brieflyDips.size(); j++) {
        brieflyDips[j] = j < 2 ? 1000 : 2200;
    }
    defaultCounter.addSamples(brieflyDips, swingTestZeros(), swingTestZeros());
    maceCounter.addSamples(brieflyDips, swingTestZeros(), swingTestZeros());

    Test.assertEqualMessage(defaultCounter.getCount(), 2, "a single-sample re-arm double-counts the brief dip");
    Test.assertEqualMessage(maceCounter.getCount(), 1, "debounced re-arm holds through the brief dip");
    return true;
}

(:test)
function testMaceCounterRefractoryHoldsThroughASameRepDoublet(logger as Test.Logger) as Boolean {
    // Shape lifted from a real recording's per-second swing_event trace:
    // never more than one event per second, but consecutive events came in
    // pairs roughly 1s apart followed by a 4s gap to the next pair - a
    // spurious re-arm-and-cross late in the same physical rep, not two
    // real swings. The 1s legacy refractory (still used by
    // MACE_DEBOUNCE_SAMPLES alone) lets the second cross through; the
    // longer mace refractory should not.
    var counter = SwingCounter.maceCounter(SwingCounter.MACE_HIGH_MG);
    var high = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
    for (var i = 0; i < high.size(); i++) {
        high[i] = 2200;
    }
    var low = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
    for (var i = 0; i < low.size(); i++) {
        low[i] = 1000;
    }
    // A dip that briefly re-arms (4 samples), then rises again for the rest
    // of the second - exactly the spurious "second trigger" candidate.
    var dipThenRise = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
    for (var j = 0; j < dipThenRise.size(); j++) {
        dipThenRise[j] = j < 4 ? 1000 : 2200;
    }

    counter.addSamples(high, swingTestZeros(), swingTestZeros()); // real rep: counts
    Test.assertEqualMessage(counter.getCount(), 1, "the real rep counts");
    counter.addSamples(dipThenRise, swingTestZeros(), swingTestZeros()); // spurious candidate ~1s later
    Test.assertEqualMessage(counter.getCount(), 1, "the same-rep doublet does not count again");
    counter.addSamples(low, swingTestZeros(), swingTestZeros());
    counter.addSamples(low, swingTestZeros(), swingTestZeros());
    counter.addSamples(high, swingTestZeros(), swingTestZeros()); // next real rep, ~4s later
    Test.assertEqualMessage(counter.getCount(), 2, "the next genuine rep still counts");
    return true;
}

(:test)
function testMaceCounterStillCountsASustainedReturnToBaseline(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.maceCounter(SwingCounter.MACE_HIGH_MG);

    var swing = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
    for (var i = 0; i < swing.size(); i++) {
        swing[i] = 2200;
    }
    counter.addSamples(swing, swingTestZeros(), swingTestZeros());
    Test.assertEqualMessage(counter.getCount(), 1, "first swing counts");

    // MACE_MIN_GAP_SAMPLES (63, ~2.5s) needs more than one second at
    // baseline to clear - three quiet seconds comfortably covers it before
    // the next rise.
    var quiet = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
    for (var j = 0; j < quiet.size(); j++) {
        quiet[j] = 1000;
    }
    counter.addSamples(quiet, swingTestZeros(), swingTestZeros());
    counter.addSamples(quiet, swingTestZeros(), swingTestZeros());
    counter.addSamples(quiet, swingTestZeros(), swingTestZeros());
    counter.addSamples(swing, swingTestZeros(), swingTestZeros());
    Test.assertEqualMessage(
        counter.getCount(),
        2,
        "a sustained return to baseline re-arms and the next rise counts"
    );
    return true;
}

(:test)
function testMaceCounterHonorsACustomThreshold(logger as Test.Logger) as Boolean {
    // A swing that peaks at 1600mg - below the tuned MACE_HIGH_MG default,
    // but real for someone whose style/strength never reaches that (the
    // whole reason the swingThresholdMg setting exists).
    var moderate = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
    for (var i = 0; i < moderate.size(); i++) {
        moderate[i] = 1600;
    }
    var defaultSensitivity = SwingCounter.maceCounter(SwingCounter.MACE_HIGH_MG);
    defaultSensitivity.addSamples(moderate, swingTestZeros(), swingTestZeros());
    Test.assertEqualMessage(
        defaultSensitivity.getCount(),
        0,
        "1600mg never reaches the tuned default threshold"
    );

    var moreSensitive = SwingCounter.maceCounter(1500);
    moreSensitive.addSamples(moderate, swingTestZeros(), swingTestZeros());
    Test.assertEqualMessage(moreSensitive.getCount(), 1, "a lower custom threshold counts the same swing");
    return true;
}
