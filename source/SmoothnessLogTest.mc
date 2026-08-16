import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;

(:test)
function testSmoothnessLogRecordRoundTrips(logger as Test.Logger) as Boolean {
    var rec = SmoothnessLog.record(
        1700000000,
        Equipment.TYPE_CLUBS,
        2,
        4000,
        Movement.TYPE_MILL,
        Movement.SIDE_TWO_HANDED,
        84,
        [80, 88, -1]
    );
    Test.assertEqualMessage(SmoothnessLog.epochOf(rec), 1700000000, "epoch");
    Test.assertEqualMessage(SmoothnessLog.eqTypeOf(rec), Equipment.TYPE_CLUBS, "equipment");
    Test.assertEqualMessage(SmoothnessLog.eqCountOf(rec), 2, "count");
    Test.assertEqualMessage(SmoothnessLog.weightOf(rec), 4000, "weight");
    Test.assertEqualMessage(SmoothnessLog.moveOf(rec), Movement.TYPE_MILL, "movement");
    Test.assertEqualMessage(SmoothnessLog.sideOf(rec), Movement.SIDE_TWO_HANDED, "side");
    Test.assertEqualMessage(SmoothnessLog.scoreOf(rec), 84, "session score");
    Test.assertEqualMessage(SmoothnessLog.setCountOf(rec), 3, "set count");
    Test.assertEqualMessage(SmoothnessLog.setScoreOf(rec, 0), 80, "set 0 score");
    Test.assertEqualMessage(SmoothnessLog.setScoreOf(rec, 2), -1, "unscored set");
    Test.assertEqualMessage(SmoothnessLog.setScoreOf(rec, 3), -1, "out of range set");
    return true;
}

(:test)
function testSmoothnessLogAppendIsBounded(logger as Test.Logger) as Boolean {
    var log = [] as Array<Storage.ValueType>;
    for (var i = 0; i < SmoothnessLog.MAX_SESSIONS + 5; i++) {
        var rec = SmoothnessLog.record(
            1700000000 + i,
            Equipment.TYPE_MACE,
            1,
            4000,
            Movement.TYPE_360,
            Movement.SIDE_ALTERNATING,
            i,
            [] as Array<Number>
        );
        log = SmoothnessLog.append(log, rec);
    }
    Test.assertEqualMessage(log.size(), SmoothnessLog.MAX_SESSIONS, "log capped at MAX_SESSIONS");
    // Sessions carried scores 0..MAX_SESSIONS+4; the five oldest are dropped.
    Test.assertEqualMessage(
        SmoothnessLog.scoreOf(log[0] as Array<Storage.ValueType>),
        5,
        "oldest surviving session"
    );
    Test.assertEqualMessage(
        SmoothnessLog.scoreOf(log[log.size() - 1] as Array<Storage.ValueType>),
        SmoothnessLog.MAX_SESSIONS + 4,
        "newest session kept"
    );
    return true;
}

(:test)
function testSmoothnessLogTruncatesSets(logger as Test.Logger) as Boolean {
    var many = [] as Array<Number>;
    for (var i = 0; i < SmoothnessLog.MAX_SETS + 10; i++) {
        many.add(i);
    }
    var rec = SmoothnessLog.record(
        1,
        Equipment.TYPE_MACE,
        1,
        4000,
        Movement.TYPE_360,
        Movement.SIDE_LEFT,
        50,
        many
    );
    Test.assertEqualMessage(SmoothnessLog.setCountOf(rec), SmoothnessLog.MAX_SETS, "sets truncated to cap");
    Test.assertEqualMessage(SmoothnessLog.setScoreOf(rec, SmoothnessLog.MAX_SETS), -1, "beyond cap unscored");
    return true;
}

(:test)
function testDetailedHistoryKeepsWorkoutAndBlockMetrics(logger as Test.Logger) as Boolean {
    var first = new WorkBlockSummary(
        1,
        180,
        Movement.TYPE_FLOW_OTHER,
        Movement.SIDE_TWO_HANDED,
        Equipment.TYPE_CLUBS,
        2,
        4000,
        0,
        60
    );
    first.setRestSeconds(90);
    first.setSwings(42);
    first.setLoadExposure(12345, 2800, 120);
    var rec = SmoothnessLog.record(
        1700000000,
        Equipment.TYPE_CLUBS,
        2,
        4000,
        Movement.TYPE_FLOW_OTHER,
        Movement.SIDE_TWO_HANDED,
        60,
        [60]
    );
    rec = SmoothnessLog.withDetails(rec, 180, 90, [first]);
    Test.assertMessage(SmoothnessLog.hasDetails(rec), "new record has detail marker");
    Test.assertEqualMessage(SmoothnessLog.totalWorkOf(rec), 180, "total work");
    Test.assertEqualMessage(SmoothnessLog.totalRestOf(rec), 90, "total rest");
    Test.assertEqualMessage(SmoothnessLog.blockCountOf(rec), 1, "one detailed block");
    Test.assertEqualMessage(SmoothnessLog.blockWorkOf(rec, 0), 180, "block work");
    Test.assertEqualMessage(SmoothnessLog.blockRestOf(rec, 0), 90, "block rest");
    Test.assertEqualMessage(SmoothnessLog.blockMoveOf(rec, 0), Movement.TYPE_FLOW_OTHER, "block movement");
    Test.assertEqualMessage(SmoothnessLog.blockSideOf(rec, 0), Movement.SIDE_TWO_HANDED, "block side");
    Test.assertEqualMessage(SmoothnessLog.blockSwingsOf(rec, 0), 42, "block swings");
    Test.assertEqualMessage(SmoothnessLog.blockExposureOf(rec, 0), 12345, "block exposure");
    Test.assertEqualMessage(SmoothnessLog.blockPeakOf(rec, 0), 2800, "block peak");
    Test.assertEqualMessage(SmoothnessLog.blockActiveOf(rec, 0), 120, "block active seconds");
    return true;
}

(:test)
function testLegacyHistoryHasSafeDetailFallbacks(logger as Test.Logger) as Boolean {
    var rec = SmoothnessLog.record(
        1,
        Equipment.TYPE_MACE,
        1,
        4000,
        Movement.TYPE_360,
        Movement.SIDE_LEFT,
        70,
        [70]
    );
    Test.assertMessage(!SmoothnessLog.hasDetails(rec), "legacy record has no detail marker");
    Test.assertEqualMessage(SmoothnessLog.totalWorkOf(rec), 0, "legacy total work fallback");
    Test.assertEqualMessage(SmoothnessLog.blockCountOf(rec), 0, "legacy block count fallback");
    Test.assertEqualMessage(SmoothnessLog.blockMoveOf(rec, 0), Movement.TYPE_360, "legacy movement fallback");
    Test.assertEqualMessage(SmoothnessLog.blockSideOf(rec, 0), Movement.SIDE_LEFT, "legacy side fallback");
    Test.assertEqualMessage(SmoothnessLog.blockSwingsOf(rec, 0), -1, "legacy swings unavailable");
    return true;
}
