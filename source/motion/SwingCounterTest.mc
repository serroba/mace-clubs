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

function gyroTestAxis(rate as Float) as Array<Float> {
    var samples = new Array<Float>[SwingCounter.SAMPLE_RATE_HZ];
    for (var i = 0; i < samples.size(); i++) {
        samples[i] = rate;
    }
    return samples;
}

(:test)
function testMaceCounterUsesGyroNotAcceleration(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.maceCounter();
    counter.addSamples(swingTestSecond(12, 4000, 1000), swingTestZeros(), swingTestZeros());
    Test.assertEqualMessage(counter.getCount(), 0, "acceleration spikes do not drive mace counting");

    var quiet = gyroTestAxis(20.0);
    var rotating = gyroTestAxis(420.0);
    var zero = gyroTestAxis(0.0);
    counter.addGyroSamples(quiet, zero, zero, true);
    counter.addGyroSamples(rotating, zero, zero, true);
    counter.addGyroSamples(quiet, zero, zero, true);
    Test.assertEqualMessage(counter.getCount(), 1, "a broad rotation-rate peak counts one mace swing");
    return true;
}

(:test)
function testMaceCounterCountsSeparatedGyroPeaks(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.maceCounter();
    var zero = gyroTestAxis(0.0);
    var quiet = gyroTestAxis(40.0);
    var rotating = gyroTestAxis(420.0);
    for (var cycle = 0; cycle < 3; cycle++) {
        counter.addGyroSamples(quiet, zero, zero, true);
        counter.addGyroSamples(rotating, zero, zero, true);
        counter.addGyroSamples(quiet, zero, zero, true);
    }
    Test.assertEqualMessage(counter.getCount(), 3, "three separated rotation peaks count three swings");
    return true;
}

(:test)
function testMaceCounterRejectsGyroTremorAndResets(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.maceCounter();
    var zero = gyroTestAxis(0.0);
    for (var second = 0; second < 5; second++) {
        counter.addGyroSamples(gyroTestAxis(120.0), zero, zero, true);
    }
    Test.assertEqualMessage(counter.getCount(), 0, "sub-threshold rotation does not count");
    counter.addGyroSamples(gyroTestAxis(420.0), zero, zero, true);
    counter.addGyroSamples(gyroTestAxis(40.0), zero, zero, true);
    Test.assertEqualMessage(counter.getCount(), 1, "a real peak counts before reset");
    counter.reset();
    Test.assertEqualMessage(counter.getCount(), 0, "reset clears gyro count and filter state");
    return true;
}

(:test)
function testMaceCounterUpdatesDuringRestWithoutCounting(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.maceCounter();
    var zero = gyroTestAxis(0.0);
    counter.addGyroSamples(gyroTestAxis(420.0), zero, zero, false);
    counter.addGyroSamples(gyroTestAxis(40.0), zero, zero, false);
    Test.assertEqualMessage(counter.getCount(), 0, "rest rotation updates the filter but never counts");
    counter.addGyroSamples(gyroTestAxis(420.0), zero, zero, true);
    counter.addGyroSamples(gyroTestAxis(40.0), zero, zero, true);
    Test.assertEqualMessage(counter.getCount(), 1, "the next work rotation peak counts normally");
    return true;
}
