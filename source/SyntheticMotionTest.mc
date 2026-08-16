import Toybox.Lang;
import Toybox.Test;

(:test)
function testSyntheticWorkoutUsesProductionMotionPipeline(logger as Test.Logger) as Boolean {
    var workout = SyntheticMotion.run();
    var records = workout[:records] as Array<Dictionary>;
    Test.assertEqualMessage(records.size(), 50, "one production feature record per second");
    Test.assertEqualMessage(workout[:workSeconds] as Number, 40, "work duration follows scenario");
    Test.assertEqualMessage(workout[:restSeconds] as Number, 10, "rest duration follows scenario");
    Test.assertEqualMessage(workout[:activeSeconds] as Number, 40, "only work contributes exposure");
    Test.assertMessage((workout[:exposure] as Number) > 0, "work contributes motion exposure");
    Test.assertMessage((workout[:swings] as Number) > 0, "production counter sees synthetic motion");
    return true;
}

(:test)
function testSyntheticWorkoutDistinguishesSmoothAndIrregularWork(logger as Test.Logger) as Boolean {
    var workout = SyntheticMotion.run();
    var smooth = workout[:smoothScore] as Number;
    var irregular = workout[:irregularScore] as Number;
    Test.assertMessage(smooth >= 90, "stable periodic work remains highly repeatable");
    Test.assertMessage(irregular >= 0, "irregular work produces a score");
    Test.assertMessage(smooth > irregular, "smooth work scores above irregular work");
    return true;
}

(:test)
function testSyntheticSpikeBecomesSessionPeak(logger as Test.Logger) as Boolean {
    var workout = SyntheticMotion.run();
    Test.assertEqualMessage(
        workout[:sessionPeak] as Number,
        workout[:spikePeak] as Number,
        "deliberate spike is retained as the session peak"
    );
    var records = workout[:records] as Array<Dictionary>;
    Test.assertMessage(
        (records[42][:dynamicPeak] as Number) > (records[41][:dynamicPeak] as Number),
        "spike is visible in the record stream"
    );
    return true;
}

(:test)
function testSyntheticRestPreservesGravityWithoutDynamicLoad(logger as Test.Logger) as Boolean {
    var workout = SyntheticMotion.run();
    var records = workout[:records] as Array<Dictionary>;
    Test.assertEqualMessage(records[0][:rms] as Number, 1000, "still wrist retains gravity");
    Test.assertEqualMessage(records[0][:dynamicRms] as Number, 0, "still wrist has no dynamic load");
    Test.assertEqualMessage(records[25][:dynamicPeak] as Number, 0, "second rest starts still");
    return true;
}
