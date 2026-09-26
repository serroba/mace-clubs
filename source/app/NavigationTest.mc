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

// The regression this exists to prevent: a finished workout used to be
// excluded from tap routing, which on the seven watches with no MENU key
// meant there was no way at all to leave one without saving it. A finished
// workout is a paused one - MaceClubsView sets both flags together - so it is
// spelled out here as the paused-and-started combination.
(:test)
function testAFinishedWorkoutStillRoutesTapsToTheMenu(logger as Test.Logger) as Boolean {
    Test.assertMessage(
        Navigation.routesTapsByPosition(true, false, true, true, false),
        "a finished or paused workout routes taps, so its discard hint means something"
    );
    Test.assertMessage(
        Navigation.routesTapsByPosition(true, false, true, false, true),
        "free-training rest routes taps to the rest options menu"
    );
    Test.assertMessage(
        Navigation.routesTapsByPosition(true, false, false, false, false),
        "the idle screen routes taps to the settings menu"
    );
    return true;
}

(:test)
function testTapRoutingStaysOffWhereItWouldStealAPress(logger as Test.Logger) as Boolean {
    Test.assertMessage(
        !Navigation.routesTapsByPosition(false, false, true, true, false),
        "a watch with a MENU key takes taps as a select"
    );
    Test.assertMessage(
        !Navigation.routesTapsByPosition(true, true, false, false, false),
        "the start countdown is not a screen to tap through"
    );
    Test.assertMessage(
        !Navigation.routesTapsByPosition(true, false, true, false, false),
        "a running work interval is not routed - a stray tap must not reach discard"
    );
    return true;
}
