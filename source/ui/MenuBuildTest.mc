import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
function testEquipmentMenuOffersEveryImplement(logger as Test.Logger) as Boolean {
    var menu = EquipmentMenu.build();
    Test.assertMessage(menu instanceof WatchUi.Menu2, "equipment picker builds a Menu2");
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

(:test)
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
