import Toybox.Lang;
import Toybox.Test;

// WorkoutSession tests cover the pre-recording state and pure logic.
// start()/save() need a live FIT session and System.exit(), so the
// recording lifecycle itself is verified in the simulator instead.

(:test)
function testWorkoutSessionStartsIdle(logger as Test.Logger) as Boolean {
    var ws = new WorkoutSession();
    Test.assertMessage(!ws.isStarted(), "not started before start()");
    Test.assertMessage(!ws.isRecording(), "not recording before start()");
    Test.assertEqualMessage(ws.getSets(), 0, "no sets before the workout");
    return true;
}

(:test)
function testAddSetCounts(logger as Test.Logger) as Boolean {
    var ws = new WorkoutSession();
    ws.addSet();
    ws.addSet();
    ws.addSet();
    Test.assertEqualMessage(ws.getSets(), 3, "three marks count three sets");
    return true;
}

(:test)
function testSetSummaryTracksWorkAndRestDurations(logger as Test.Logger) as Boolean {
    var ws = new WorkoutSession();
    ws.addSetWithDuration(120);
    ws.endRestLapWithDuration(60);
    ws.addSetWithDuration(90);
    Test.assertEqualMessage(ws.getSetWorkSeconds(0), 120, "first work duration");
    Test.assertEqualMessage(ws.getSetRestSeconds(0), 60, "first rest duration");
    Test.assertEqualMessage(ws.getSetWorkSeconds(1), 90, "second work duration");
    Test.assertEqualMessage(ws.getSetRestSeconds(1), 0, "unfinished rest defaults to zero");
    Test.assertEqualMessage(ws.getTotalWorkSeconds(), 210, "work durations sum");
    Test.assertEqualMessage(ws.getTotalRestSeconds(), 60, "rest durations sum");
    return true;
}

(:test)
function testEquipmentSelectionPreparesChosenSessionProfile(logger as Test.Logger) as Boolean {
    var session = new WorkoutSession();
    session.selectEquipment(Equipment.TYPE_CLUBS, 2);
    Test.assertEqualMessage(session.getEquipmentType(), Equipment.TYPE_CLUBS, "clubs selected");
    Test.assertEqualMessage(session.getEquipmentCount(), 2, "pair selected");
    Test.assertEqualMessage(
        session.getEquipmentWeightGrams(),
        Equipment.defaultWeightGrams(Equipment.TYPE_CLUBS),
        "selection uses the configured club default"
    );
    session.selectEquipment(Equipment.TYPE_MACE, 2);
    Test.assertEqualMessage(session.getEquipmentCount(), 1, "mace quantity is always one");
    return true;
}

(:test)
function testMovementSelectionResolvesAgainstEquipment(logger as Test.Logger) as Boolean {
    var session = new WorkoutSession();
    session.selectEquipment(Equipment.TYPE_MACE, 1);
    session.selectMovement(Movement.TYPE_10_TO_2);
    Test.assertEqualMessage(session.getMovementType(), Movement.TYPE_10_TO_2, "mace accepts the 10-to-2");
    session.selectMovement(Movement.TYPE_SHIELD_CAST);
    Test.assertEqualMessage(
        session.getMovementType(),
        Movement.TYPE_360,
        "a club movement falls back to the mace default"
    );
    session.selectEquipment(Equipment.TYPE_CLUBS, 2);
    Test.assertEqualMessage(
        session.getMovementType(),
        Movement.TYPE_MILL,
        "equipment change re-resolves the movement"
    );
    return true;
}

(:test)
function testWorkBlocksRecordTheMovementActiveAtCompletion(logger as Test.Logger) as Boolean {
    var session = new WorkoutSession();
    session.selectEquipment(Equipment.TYPE_MACE, 1);
    session.selectMovement(Movement.TYPE_360);
    session.addSetWithDuration(120);
    session.selectMovement(Movement.TYPE_10_TO_2);
    session.addSetWithDuration(90);
    var first = session.getBlock(0) as WorkBlockSummary;
    var second = session.getBlock(1) as WorkBlockSummary;
    Test.assertEqualMessage(first.getMovementType(), Movement.TYPE_360, "first block keeps the 360");
    Test.assertEqualMessage(
        second.getMovementType(),
        Movement.TYPE_10_TO_2,
        "a switch between sets applies to the next block"
    );
    return true;
}

(:test)
function testSideSetCountsFollowTheSideAtCompletion(logger as Test.Logger) as Boolean {
    var session = new WorkoutSession();
    session.selectWorkingSide(Movement.SIDE_LEFT);
    session.addSetWithDuration(60);
    session.selectWorkingSide(Movement.SIDE_RIGHT);
    session.addSetWithDuration(60);
    session.selectWorkingSide(Movement.SIDE_LEFT);
    session.addSetWithDuration(60);
    session.selectWorkingSide(Movement.SIDE_TWO_HANDED);
    session.addSetWithDuration(60);
    var counts = session.getSideSetCounts();
    Test.assertEqualMessage(counts[0], 2, "two left-hand sets");
    Test.assertEqualMessage(counts[1], 1, "one right-hand set");
    return true;
}

(:test)
function testComboForcesAlternatingSide(logger as Test.Logger) as Boolean {
    var session = new WorkoutSession();
    session.selectEquipment(Equipment.TYPE_BULAVA, 1);
    session.selectWorkingSide(Movement.SIDE_LEFT);
    session.selectMovement(Movement.TYPE_COMBO);
    Test.assertEqualMessage(session.getMovementType(), Movement.TYPE_COMBO, "combo selected");
    Test.assertEqualMessage(
        session.getWorkingSide(),
        Movement.SIDE_ALTERNATING,
        "one combo cycle works both hands, so the side is alternating"
    );
    return true;
}

(:test)
function testSelectWorkingSideRejectsUnknownValues(logger as Test.Logger) as Boolean {
    var session = new WorkoutSession();
    session.selectWorkingSide(Movement.SIDE_ALTERNATING);
    Test.assertEqualMessage(session.getWorkingSide(), Movement.SIDE_ALTERNATING, "valid side is kept");
    session.selectWorkingSide(99);
    Test.assertEqualMessage(
        session.getWorkingSide(),
        Movement.SIDE_TWO_HANDED,
        "out-of-range side falls back to two-handed"
    );
    return true;
}

(:test)
function testBlocksWithoutSwingCounterCarryNoCount(logger as Test.Logger) as Boolean {
    var session = new WorkoutSession();
    session.addSetWithDuration(60);
    Test.assertMessage(!session.isSwingCounting(), "counter is off outside a live session");
    Test.assertEqualMessage(session.getTotalSwings(), 0, "no swings detected");
    Test.assertEqualMessage(
        (session.getBlock(0) as WorkBlockSummary).getSwings(),
        -1,
        "a block without the counter records -1, not a fake zero"
    );
    return true;
}

(:test)
function testDiscardResetsSessionForAnotherWorkout(logger as Test.Logger) as Boolean {
    var session = new WorkoutSession();
    session.beginSmoothnessSet();
    session.addSet();
    Test.assertEqualMessage(
        session.getSetSmoothnessCount(),
        0,
        "disabled smoothness does not create an empty summary"
    );
    session.discard();
    Test.assertMessage(!session.isStarted(), "discard returns the session to idle");
    Test.assertEqualMessage(session.getSets(), 0, "discard clears the workout set count");
    Test.assertEqualMessage(
        session.getSmoothnessScore(),
        -1,
        "discard clears the in-progress smoothness score"
    );
    Test.assertEqualMessage(session.getSetSmoothnessCount(), 0, "discard clears per-set summaries");
    return true;
}

(:test)
function testBatteryDeltaMeasuresDrain(logger as Test.Logger) as Boolean {
    var ws = new WorkoutSession();
    Test.assertEqualMessage(ws.batteryDelta(80.0, 75.5), 4.5, "normal drain is start minus end");
    return true;
}

(:test)
function testBatteryDeltaFloorsSolarGains(logger as Test.Logger) as Boolean {
    var ws = new WorkoutSession();
    Test.assertEqualMessage(
        ws.batteryDelta(50.0, 60.0),
        0.0,
        "charging mid-session floors at zero rather than negative"
    );
    return true;
}
