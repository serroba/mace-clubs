import Toybox.Lang;
import Toybox.Test;

(:test)
function testPausedUpNavigatesHome(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(
        Navigation.previousPageAction(false, true, true),
        Navigation.PREVIOUS_HOME,
        "short UP opens home confirmation while paused"
    );
    return true;
}

(:test)
function testActiveAndIdleUpKeepExistingActions(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(
        Navigation.previousPageAction(false, true, false),
        Navigation.PREVIOUS_TEMPO_UP,
        "short UP adjusts tempo in an active workout"
    );
    Test.assertEqualMessage(
        Navigation.previousPageAction(false, false, false),
        Navigation.PREVIOUS_PRESET,
        "short UP changes preset on the home screen"
    );
    Test.assertEqualMessage(
        Navigation.previousPageAction(true, false, false),
        Navigation.PREVIOUS_IGNORE,
        "short UP is ignored during the start countdown"
    );
    return true;
}
