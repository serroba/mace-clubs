import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

// Timer.start resolves callbacks dynamically. A private callback compiles but
// fails with Invalid Value when SELECT starts the countdown in the simulator.
(:test)
function testWorkoutCountdownCallbackIsRuntimeResolvable(logger as Test.Logger) as Boolean {
    var view = new MaceClubsView();
    var callback = view.method(:beginWorkout);
    Test.assertMessage(callback != null, "countdown timer callback resolves as a public method");

    // What the three pickers do when they close. Driven by the e2e suite and
    // by nothing here, so the wiring between a menu selection and the session
    // it configures was only ever checked through a screenshot.
    //
    // Two of them remember the choice in Application.Properties as the next
    // session's default, and that outlives the test: written and left alone,
    // the workingSide below leaked into
    // testWorkoutSummaryFallbackTextRendersWithNoData, which builds a fresh
    // session expecting no side data and got "L". The unit suite shares one
    // property store with no teardown between tests, so a test that writes to
    // it has to put it back.
    //
    // Back to the value properties.xml ships, not to whatever was there when
    // this test started. The simulator persists an app's properties between
    // runs, so reading-then-restoring preserves the pollution from a previous
    // run rather than clearing it - the first version of this restored what
    // it read and the summary test stayed red across rebuilds until the
    // simulator's stored data was cleared by hand.
    view.chooseEquipment(Equipment.TYPE_CLUBS, 2);
    Test.assertEqualMessage(
        view.workout.getEquipmentType(),
        Equipment.TYPE_CLUBS,
        "choosing clubs configures the session"
    );
    Test.assertEqualMessage(view.workout.getEquipmentCount(), 2, "two clubs are two clubs");

    view.chooseMovement(Movement.TYPE_MILL);
    var movementAfter = view.workout.getMovementType();
    Application.Properties.setValue("movementType", Movement.TYPE_360);
    Test.assertEqualMessage(movementAfter, Movement.TYPE_MILL, "movement selection sticks");

    view.chooseWorkingSide(Movement.SIDE_LEFT);
    var sideAfter = view.workout.getWorkingSide();
    Application.Properties.setValue("workingSide", Movement.SIDE_TWO_HANDED);
    Test.assertEqualMessage(sideAfter, Movement.SIDE_LEFT, "side selection sticks");
    return true;
}
