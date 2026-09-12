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
    // This scenario no longer scores rhythm, and cannot.
    //
    // It was built for the model the Rhythm Score used to use, which scored
    // every one-second acceleration window and so always had something to
    // report. The score now measures the gaps between *detected swings*, and
    // this fifty-second waveform produces fewer than the three gaps a score
    // needs - both spans come back -1. Asserting on that would be asserting
    // that the fixture is too short.
    //
    // The model itself is tested directly against controlled gap sequences in
    // SmoothnessTest, and against a real recording in docs/swing-counting.md.
    // What is missing, and worth building, is a synthetic waveform the swing
    // counter actually bites on: then this scenario could show an even train
    // scoring above a ragged one through the production pipeline.
    var records = workout[:records] as Array<Dictionary>;
    for (var i = 0; i < records.size(); i++) {
        var score = records[i][:smoothnessScore] as Number;
        Test.assertMessage(score <= 100, "live rhythm remains bounded");
        Test.assertMessage(score >= -1, "an unscored second reports -1, not a wrong number");
    }
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

(:test)
function testSyntheticWorkoutProducesSwingTimeSeries(logger as Test.Logger) as Boolean {
    var workout = SyntheticMotion.run();
    var records = workout[:records] as Array<Dictionary>;
    var events = 0;
    for (var i = 0; i < records.size(); i++) {
        events += records[i][:swingEvent] as Number;
    }
    Test.assertEqualMessage(events, workout[:swings] as Number, "events reconcile with total swings");
    Test.assertEqualMessage(
        records[records.size() - 1][:swingTotal] as Number,
        workout[:swings] as Number,
        "final cumulative point matches workout total"
    );
    return true;
}
