import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;

const TRAINING_LOAD_TEST_DAY = 86400;

function trainingLoadTestRecord(epoch as Number, exposure as Number) as Array<Storage.ValueType> {
    var block = new WorkBlockSummary(
        1,
        180,
        Movement.TYPE_360,
        Movement.SIDE_TWO_HANDED,
        Equipment.TYPE_MACE,
        1,
        4000,
        0,
        60
    );
    block.setLoadExposure(exposure, 2000, 120);
    var rec = SmoothnessLog.record(
        epoch,
        Equipment.TYPE_MACE,
        1,
        4000,
        Movement.TYPE_360,
        Movement.SIDE_TWO_HANDED,
        60,
        [60]
    );
    return SmoothnessLog.withDetails(rec, 180, 60, [block]);
}

(:test)
function testTrainingLoadEmptyLogIsUnavailable(logger as Test.Logger) as Boolean {
    var log = [] as Array<Storage.ValueType>;
    Test.assertMessage(TrainingLoad.acuteChronicRatio(log, 2000000000) == null, "no history yields no ratio");
    Test.assertEqualMessage(TrainingLoad.label(null), "--", "unavailable ratio labels as --");
    return true;
}

(:test)
function testTrainingLoadIgnoresSessionsOutsideTheChronicWindow(logger as Test.Logger) as Boolean {
    var now = 2000000000;
    var log = [] as Array<Storage.ValueType>;
    log = SmoothnessLog.append(log, trainingLoadTestRecord(now - 40 * TRAINING_LOAD_TEST_DAY, 5000));
    Test.assertMessage(
        TrainingLoad.acuteChronicRatio(log, now) == null,
        "a session older than the chronic window contributes no baseline"
    );
    return true;
}

(:test)
function testTrainingLoadSteadyWeekMatchesBaseline(logger as Test.Logger) as Boolean {
    var now = 2000000000;
    var log = [] as Array<Storage.ValueType>;
    // One session every 8 days (0/8/16/24 days ago) all sit inside the
    // 28-day chronic window, but only "now" falls inside the 7-day acute
    // one - same exposure each time, so acute load should equal the
    // chronic weekly average almost exactly.
    for (var i = 0; i < 4; i++) {
        log = SmoothnessLog.append(log, trainingLoadTestRecord(now - i * 8 * TRAINING_LOAD_TEST_DAY, 10000));
    }
    var ratio = TrainingLoad.acuteChronicRatio(log, now) as Float;
    Test.assertMessage(ratio > 0.95 && ratio < 1.05, "a steady weekly pattern ratios close to 1.0");
    Test.assertEqualMessage(TrainingLoad.label(ratio), "Steady", "steady ratio labels as Steady");
    return true;
}

(:test)
function testTrainingLoadSpikeAboveBaselineReadsHigh(logger as Test.Logger) as Boolean {
    var now = 2000000000;
    var log = [] as Array<Storage.ValueType>;
    // A small baseline three and four weeks ago, then a big spike this week.
    log = SmoothnessLog.append(log, trainingLoadTestRecord(now - 21 * TRAINING_LOAD_TEST_DAY, 2000));
    log = SmoothnessLog.append(log, trainingLoadTestRecord(now - 28 * TRAINING_LOAD_TEST_DAY, 2000));
    log = SmoothnessLog.append(log, trainingLoadTestRecord(now, 40000));
    var ratio = TrainingLoad.acuteChronicRatio(log, now) as Float;
    Test.assertMessage(ratio > 1.5, "a large recent spike over a small baseline reads High");
    Test.assertEqualMessage(TrainingLoad.label(ratio), "High", "spike ratio labels as High");
    return true;
}

(:test)
function testTrainingLoadQuietWeekAfterABusyMonthReadsLow(logger as Test.Logger) as Boolean {
    var now = 2000000000;
    var log = [] as Array<Storage.ValueType>;
    // Busy three weeks ago, nothing acute (this week is quiet).
    log = SmoothnessLog.append(log, trainingLoadTestRecord(now - 14 * TRAINING_LOAD_TEST_DAY, 30000));
    var ratio = TrainingLoad.acuteChronicRatio(log, now) as Float;
    Test.assertEqualMessage(ratio, 0.0, "no acute-window sessions yields a zero ratio");
    Test.assertEqualMessage(TrainingLoad.label(ratio), "Low", "zero ratio labels as Low");
    return true;
}
