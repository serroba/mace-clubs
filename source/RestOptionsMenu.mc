import Toybox.Lang;
import Toybox.WatchUi;

// MENU during a free-training rest: change the next set's movement without
// abandoning the session, or reach the discard confirmation as before.
module RestOptionsMenu {
    function build(workout as WorkoutSession) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Rest options"});
        menu.addItem(new WatchUi.MenuItem(movementLabel(workout.getMovementType()), null, "movement", null));
        menu.addItem(new WatchUi.MenuItem("Discard & go home", null, "discard", null));
        return menu;
    }

    function movementLabel(movementType as Number) as String {
        return Lang.format("Move: $1$", [Movement.typeLabel(movementType)]);
    }
}

class RestOptionsDelegate extends WatchUi.Menu2InputDelegate {
    private var _view as MaceClubsView;

    function initialize(view as MaceClubsView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (id.equals("movement")) {
            WatchUi.switchToView(
                MovementMenu.build(_view.workout.getEquipmentType()),
                new MovementMenuDelegate(_view, false),
                WatchUi.SLIDE_LEFT
            );
        } else {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.pushView(
                new WatchUi.Confirmation("Discard & go home?"),
                new DiscardConfirmationDelegate(_view),
                WatchUi.SLIDE_IMMEDIATE
            );
        }
    }
}
