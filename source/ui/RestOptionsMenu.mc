import Toybox.Lang;
import Toybox.WatchUi;

// MENU during a free-training rest: change the next set's movement without
// abandoning the session, or reach the discard confirmation as before.
module RestOptionsMenu {
    function build(workout as WorkoutSession) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => title()});
        menu.addItem(new WatchUi.MenuItem(movementLabel(workout.getMovementType()), null, "movement", null));
        menu.addItem(new WatchUi.MenuItem(sideLabel(workout.getWorkingSide()), null, "side", null));
        menu.addItem(new WatchUi.MenuItem(discardLabel(), null, "discard", null));
        return menu;
    }

    // "Move: 360" fits everywhere; the rows below it do not.
    //
    // Menu2 is drawn by the system, not by us - we hand it strings and it
    // decides the font. On the Instinct 2 family that font is wide enough
    // that a 176px screen clips these rows at their left edge: "Side:
    // Two-handed" renders as "de: Two-handed", and the title's second line
    // loses its start the same way. Confirmed against a full-window capture
    // of the simulator, so it is the device rather than the screenshot crop,
    // and the same three watches already ship a reduced build for memory.
    // Shortening the strings is the only lever we have over a system menu,
    // so those three get terse rows and everything else keeps its labels.
    (:menuLabelPrefix)
    function title() as String {
        return "Rest options";
    }

    (:noMenuLabelPrefix)
    function title() as String {
        return "Options";
    }

    function movementLabel(movementType as Number) as String {
        return Lang.format("Move: $1$", [Movement.typeLabel(movementType)]);
    }

    (:menuLabelPrefix)
    function sideLabel(side as Number) as String {
        return Lang.format("Side: $1$", [Movement.sideLabel(side)]);
    }

    (:noMenuLabelPrefix)
    function sideLabel(side as Number) as String {
        return Movement.sideLabel(side);
    }

    (:menuLabelPrefix)
    function discardLabel() as String {
        return "Discard & go home";
    }

    (:noMenuLabelPrefix)
    function discardLabel() as String {
        return "Discard";
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
        if (id.equals("side")) {
            // Cycle in place, like the settings menu, so a left-set /
            // right-set ladder only needs one press per rest.
            _view.chooseWorkingSide((_view.workout.getWorkingSide() + 1) % Movement.SIDE_COUNT);
            item.setLabel(RestOptionsMenu.sideLabel(_view.workout.getWorkingSide()));
        } else if (id.equals("movement")) {
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
