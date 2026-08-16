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
    var counter = new SwingCounter.Counter();
    for (var second = 0; second < 3; second++) {
        counter.addSamples(swingTestSecond(12, 2500, 1000), swingTestZeros(), swingTestZeros());
    }
    Test.assertEqualMessage(counter.getCount(), 3, "one peak per second counts one swing per second");
    return true;
}

(:test)
function testSwingCounterIgnoresRestingBaseline(logger as Test.Logger) as Boolean {
    var counter = new SwingCounter.Counter();
    for (var second = 0; second < 5; second++) {
        counter.addSamples(swingTestSecond(12, 1050, 980), swingTestZeros(), swingTestZeros());
    }
    Test.assertEqualMessage(counter.getCount(), 0, "gravity plus noise never crosses the swing threshold");
    return true;
}

(:test)
function testSwingCounterNeedsReArmBelowLowThreshold(logger as Test.Logger) as Boolean {
    var counter = new SwingCounter.Counter();
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
    var counter = new SwingCounter.Counter();
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
    var counter = new SwingCounter.Counter();
    // 1560mg on two axes combines to ~2206mg magnitude, above threshold.
    counter.addSamples(swingTestSecond(12, 1560, 700), swingTestSecond(12, 1560, 700), swingTestZeros());
    Test.assertEqualMessage(counter.getCount(), 1, "magnitude combines the axes");
    return true;
}

(:test)
function testSwingCounterResets(logger as Test.Logger) as Boolean {
    var counter = new SwingCounter.Counter();
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
    var counter = new SwingCounter.Counter();
    counter.adjust(-1);
    Test.assertEqualMessage(counter.getCount(), 0, "correction floors at zero");
    counter.adjust(1);
    Test.assertEqualMessage(counter.getCount(), 1, "positive correction adds one");
    return true;
}
