import Toybox.Lang;
import Toybox.Test;

(:test)
function testLoadExposureAccumulatesOnlyActiveWindows(logger as Test.Logger) as Boolean {
    var tracker = new LoadExposure.Tracker();
    Test.assertMessage(!tracker.add({:dynamicRms => 39, :dynamicPeak => 900}), "quiet window is ignored");
    Test.assertMessage(tracker.add({:dynamicRms => 400, :dynamicPeak => 1800}), "active window is kept");
    Test.assertMessage(tracker.add({:dynamicRms => 600, :dynamicPeak => 1500}), "second window is kept");
    Test.assertEqualMessage(tracker.getExposure(), 1000, "RMS sums to mg-seconds");
    Test.assertEqualMessage(tracker.getPeak(), 1800, "largest dynamic peak is retained");
    Test.assertEqualMessage(tracker.getActiveSeconds(), 2, "active seconds count valid windows");
    tracker.reset();
    Test.assertEqualMessage(tracker.getExposure(), 0, "reset clears exposure");
    Test.assertEqualMessage(tracker.getPeak(), 0, "reset clears peak");
    Test.assertEqualMessage(tracker.getActiveSeconds(), 0, "reset clears duration");
    return true;
}

(:test)
function testLoadExposureIncludesThresholdAndCanRaisePeak(logger as Test.Logger) as Boolean {
    var tracker = new LoadExposure.Tracker();
    Test.assertMessage(tracker.add({:dynamicRms => 40, :dynamicPeak => 1000}), "threshold is active");
    Test.assertMessage(tracker.add({:dynamicRms => 60, :dynamicPeak => 2200}), "later window is active");
    Test.assertEqualMessage(tracker.getExposure(), 100, "threshold window contributes exposure");
    Test.assertEqualMessage(tracker.getPeak(), 2200, "a later higher peak replaces the first");
    Test.assertEqualMessage(tracker.getActiveSeconds(), 2, "both active windows count");
    return true;
}

(:test)
function testWeightVolumeAccountsForImplementQuantity(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(
        LoadExposure.weightVolumeKgSwings(4000, 1, 30),
        120,
        "single 4 kg mace over 30 swings"
    );
    Test.assertEqualMessage(
        LoadExposure.weightVolumeKgSwings(2500, 2, 20),
        100,
        "pair of clubs uses both implements"
    );
    Test.assertEqualMessage(LoadExposure.weightVolumeKgSwings(4000, 1, -1), 0, "unknown swings have no volume");
    Test.assertEqualMessage(LoadExposure.weightVolumeKgSwings(0, 1, 20), 0, "zero weight has no volume");
    Test.assertEqualMessage(
        LoadExposure.weightVolumeKgSwings(4000, 0, 20),
        0,
        "zero implements have no volume"
    );
    return true;
}

(:test)
function testLoadExposureCompactLabels(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(LoadExposure.compactLabel(-1), "", "missing exposure stays hidden");
    Test.assertEqualMessage(LoadExposure.compactLabel(850), "L850", "small exposure is exact");
    Test.assertEqualMessage(LoadExposure.compactLabel(1000), "L1.0k", "thousands boundary keeps one decimal");
    Test.assertEqualMessage(LoadExposure.compactLabel(1234), "L1.2k", "large exposure uses compact thousands");
    return true;
}
