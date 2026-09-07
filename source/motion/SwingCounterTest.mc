import Toybox.Lang;
import Toybox.Test;
(:test)
function testSwingCounterCountsSpacedPeaks(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    for (var second = 0; second < 3; second++) {
        counter.addSamples(
            MotionTestFixtures.swingTestSecond(12, 2500, 1000),
            MotionTestFixtures.swingTestZeros(),
            MotionTestFixtures.swingTestZeros()
        );
    }
    Test.assertEqualMessage(counter.getCount(), 3, "one peak per second counts one swing per second");
    return true;
}

(:test)
function testSwingCounterIgnoresRestingBaseline(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    for (var second = 0; second < 5; second++) {
        counter.addSamples(
            MotionTestFixtures.swingTestSecond(12, 1050, 980),
            MotionTestFixtures.swingTestZeros(),
            MotionTestFixtures.swingTestZeros()
        );
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
    counter.addSamples(plateau, MotionTestFixtures.swingTestZeros(), MotionTestFixtures.swingTestZeros());
    counter.addSamples(plateau, MotionTestFixtures.swingTestZeros(), MotionTestFixtures.swingTestZeros());
    Test.assertEqualMessage(counter.getCount(), 1, "staying above threshold counts once");
    counter.addSamples(
        MotionTestFixtures.swingTestSecond(12, 2500, 1000),
        MotionTestFixtures.swingTestZeros(),
        MotionTestFixtures.swingTestZeros()
    );
    Test.assertEqualMessage(counter.getCount(), 2, "dropping to baseline re-arms the counter");
    return true;
}

(:test)
function testSwingCounterEnforcesRefractoryGap(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    // Two sharp peaks 8 samples (~0.3s) apart within one second: the second
    // is armed (magnitude dipped) but inside the refractory window.
    var samples = MotionTestFixtures.swingTestSecond(4, 2500, 1000);
    samples[12] = 2500;
    counter.addSamples(samples, MotionTestFixtures.swingTestZeros(), MotionTestFixtures.swingTestZeros());
    Test.assertEqualMessage(counter.getCount(), 1, "peaks closer than the refractory gap count once");
    return true;
}

(:test)
function testSwingCounterUsesAllAxes(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    // 1560mg on two axes combines to ~2206mg magnitude, above threshold.
    counter.addSamples(
        MotionTestFixtures.swingTestSecond(12, 1560, 700),
        MotionTestFixtures.swingTestSecond(12, 1560, 700),
        MotionTestFixtures.swingTestZeros()
    );
    Test.assertEqualMessage(counter.getCount(), 1, "magnitude combines the axes");
    return true;
}

(:test)
function testSwingCounterResets(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.defaultCounter();
    counter.addSamples(
        MotionTestFixtures.swingTestSecond(12, 2500, 1000),
        MotionTestFixtures.swingTestZeros(),
        MotionTestFixtures.swingTestZeros()
    );
    Test.assertEqualMessage(counter.getCount(), 1, "counted before reset");
    counter.reset();
    Test.assertEqualMessage(counter.getCount(), 0, "reset clears the count");
    counter.addSamples(
        MotionTestFixtures.swingTestSecond(12, 2500, 1000),
        MotionTestFixtures.swingTestZeros(),
        MotionTestFixtures.swingTestZeros()
    );
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
function testMaceCounterUsesGyroNotAcceleration(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.maceCounter();
    counter.addSamples(
        MotionTestFixtures.swingTestSecond(12, 4000, 1000),
        MotionTestFixtures.swingTestZeros(),
        MotionTestFixtures.swingTestZeros()
    );
    Test.assertEqualMessage(counter.getCount(), 0, "acceleration spikes do not drive mace counting");

    var quiet = MotionTestFixtures.gyroTestAxis(20.0);
    var rotating = MotionTestFixtures.gyroTestAxis(420.0);
    var zero = MotionTestFixtures.gyroTestAxis(0.0);
    counter.addGyroSamples(quiet, zero, zero, true);
    counter.addGyroSamples(rotating, zero, zero, true);
    counter.addGyroSamples(quiet, zero, zero, true);
    Test.assertEqualMessage(counter.getCount(), 1, "a broad rotation-rate peak counts one mace swing");
    return true;
}

(:test)
function testMaceCounterCountsSeparatedGyroPeaks(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.maceCounter();
    var zero = MotionTestFixtures.gyroTestAxis(0.0);
    var quiet = MotionTestFixtures.gyroTestAxis(40.0);
    var rotating = MotionTestFixtures.gyroTestAxis(420.0);
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
    var zero = MotionTestFixtures.gyroTestAxis(0.0);
    for (var second = 0; second < 5; second++) {
        counter.addGyroSamples(MotionTestFixtures.gyroTestAxis(120.0), zero, zero, true);
    }
    Test.assertEqualMessage(counter.getCount(), 0, "sub-threshold rotation does not count");
    counter.addGyroSamples(MotionTestFixtures.gyroTestAxis(420.0), zero, zero, true);
    counter.addGyroSamples(MotionTestFixtures.gyroTestAxis(40.0), zero, zero, true);
    Test.assertEqualMessage(counter.getCount(), 1, "a real peak counts before reset");
    counter.reset();
    Test.assertEqualMessage(counter.getCount(), 0, "reset clears gyro count and filter state");
    return true;
}

(:test)
function testMaceCounterUpdatesDuringRestWithoutCounting(logger as Test.Logger) as Boolean {
    var counter = SwingCounter.maceCounter();
    var zero = MotionTestFixtures.gyroTestAxis(0.0);
    counter.addGyroSamples(MotionTestFixtures.gyroTestAxis(420.0), zero, zero, false);
    counter.addGyroSamples(MotionTestFixtures.gyroTestAxis(40.0), zero, zero, false);
    Test.assertEqualMessage(counter.getCount(), 0, "rest rotation updates the filter but never counts");
    counter.addGyroSamples(MotionTestFixtures.gyroTestAxis(420.0), zero, zero, true);
    counter.addGyroSamples(MotionTestFixtures.gyroTestAxis(40.0), zero, zero, true);
    Test.assertEqualMessage(counter.getCount(), 1, "the next work rotation peak counts normally");
    return true;
}
