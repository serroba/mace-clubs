import Toybox.Lang;
import Toybox.Test;

// Timer.start resolves callbacks dynamically. A private callback compiles but
// fails with Invalid Value when SELECT starts the countdown in the simulator.
(:test)
function testWorkoutCountdownCallbackIsRuntimeResolvable(logger as Test.Logger) as Boolean {
    var view = new MaceClubsView();
    var callback = view.method(:beginWorkout);
    Test.assertMessage(callback != null, "countdown timer callback resolves as a public method");
    return true;
}
