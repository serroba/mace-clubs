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
function testDiscardResetsSessionForAnotherWorkout(logger as Test.Logger) as Boolean {
    var session = new WorkoutSession();
    session.addSet();
    session.discard();
    Test.assertMessage(!session.isStarted(), "discard returns the session to idle");
    Test.assertEqualMessage(session.getSets(), 0, "discard clears the workout set count");
    Test.assertEqualMessage(
        session.getSmoothnessScore(),
        -1,
        "discard clears the in-progress smoothness score"
    );
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
