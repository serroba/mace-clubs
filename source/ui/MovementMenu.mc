import Toybox.Lang;
import Toybox.WatchUi;

// Movement picker shown after the equipment choice when starting a workout,
// and from the free-training rest menu to change the next set's movement
// without leaving the session. Items carry the movement constant as their id.
module MovementMenu {
    function build(equipmentType as Number) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Choose movement"});
        var options = Movement.optionsFor(equipmentType);
        for (var i = 0; i < options.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(Movement.typeLabel(options[i]), null, options[i], null));
        }
        return menu;
    }
}

class MovementMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _view as MaceClubsView;
    private var _startOnSelect as Boolean;

    function initialize(view as MaceClubsView, startOnSelect as Boolean) {
        Menu2InputDelegate.initialize();
        _view = view;
        _startOnSelect = startOnSelect;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        _view.chooseMovement(item.getId() as Number);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (_startOnSelect) {
            _view.startWorkout();
        }
    }
}
