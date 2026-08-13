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
