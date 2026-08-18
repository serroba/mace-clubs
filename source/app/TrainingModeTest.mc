import Toybox.Lang;
import Toybox.Test;

(:test)
function testTrainingModeNormalizesAndLabels(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrainingMode.normalize(99), TrainingMode.INTERVAL, "unknown mode is safe");
    Test.assertEqualMessage(TrainingMode.label(TrainingMode.REPS), "reps", "rep label");
    Test.assertEqualMessage(TrainingMode.targetLabel(0), "off", "zero disables target");
    return true;
}

(:test)
function testRepTargetCycleAndCrossing(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrainingMode.nextTarget(0), 10, "target cycle begins at ten");
    Test.assertEqualMessage(TrainingMode.nextTarget(200), 0, "target cycle can disable target");
    Test.assertEqualMessage(TrainingMode.nextTarget(37), 50, "custom value returns to default");
    Test.assertMessage(TrainingMode.crossedTarget(49, 50, 50), "crossing target alerts");
    Test.assertMessage(!TrainingMode.crossedTarget(50, 51, 50), "target alerts once");
    Test.assertMessage(!TrainingMode.crossedTarget(0, 10, 0), "disabled target never alerts");
    return true;
}
