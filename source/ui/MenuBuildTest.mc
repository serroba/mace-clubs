import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
function testEquipmentMenuOffersEveryImplement(logger as Test.Logger) as Boolean {
    var menu = EquipmentMenu.build();
    Test.assertMessage(menu instanceof WatchUi.Menu2, "equipment picker builds a Menu2");

    // The settings menu and the rest-options menu, which nothing built until
    // now: the e2e suite opens both on thirteen devices, but no unit test
    // constructed either, so a row whose label helper threw would fail in the
    // simulator rather than here. Building them also runs the annotated rows
    // (history, custom workout) on whichever side of the pair this build
    // compiled.
    Test.assertMessage(SettingsMenu.build() instanceof WatchUi.Menu2, "settings menu builds a Menu2");

    var workout = new WorkoutSession();
    Test.assertMessage(
        RestOptionsMenu.build(workout) instanceof WatchUi.Menu2,
        "rest options menu builds a Menu2"
    );
    // Not reached by build(): the confirmation text is raised separately, by
    // the discard row and by a mid-workout MENU.
    Test.assertMessage(RestOptionsMenu.discardPrompt().length() > 0, "the discard prompt says something");
    return true;
}

(:test)
function testMovementMenuFollowsTheImplement(logger as Test.Logger) as Boolean {
    Test.assertMessage(
        MovementMenu.build(Equipment.TYPE_MACE) instanceof WatchUi.Menu2,
        "mace movements build"
    );
    Test.assertMessage(
        MovementMenu.build(Equipment.TYPE_CLUBS) instanceof WatchUi.Menu2,
        "club movements build"
    );
    Test.assertMessage(
        MovementMenu.build(Equipment.TYPE_BULAVA) instanceof WatchUi.Menu2,
        "bulava movements build"
    );
    return true;
}

(:test, :history)
function testHistoryMenuBuildsWithAnEmptyLog(logger as Test.Logger) as Boolean {
    Test.assertMessage(HistoryMenu.build() instanceof WatchUi.Menu2, "empty history still builds");
    Test.assertMessage(HistoryMenu.stamp(1700000000) != null, "epochs format into a menu stamp");
    return true;
}

(:test)
function testDiscardConfirmationOnlyActsOnYes(logger as Test.Logger) as Boolean {
    var view = new MaceClubsView();
    view.workout.addSetWithDuration(60);
    var delegate = new DiscardConfirmationDelegate(view);
    Test.assertMessage(delegate.onResponse(WatchUi.CONFIRM_NO), "No is consumed");
    Test.assertEqualMessage(view.workout.getSets(), 1, "No keeps the workout");
    Test.assertMessage(delegate.onResponse(WatchUi.CONFIRM_YES), "Yes is consumed");
    Test.assertEqualMessage(view.workout.getSets(), 0, "Yes discards the workout");
    return true;
}
