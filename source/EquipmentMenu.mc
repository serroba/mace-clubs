import Toybox.Lang;
import Toybox.WatchUi;

module EquipmentMenu {
    function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Choose equipment"});
        var maceWeight = Equipment.defaultWeightGrams(Equipment.TYPE_MACE);
        var clubWeight = Equipment.defaultWeightGrams(Equipment.TYPE_CLUBS);
        menu.addItem(
            new WatchUi.MenuItem(Equipment.labelFor(Equipment.TYPE_MACE, 1, maceWeight), null, "mace", null)
        );
        menu.addItem(
            new WatchUi.MenuItem(
                Equipment.labelFor(Equipment.TYPE_CLUBS, 1, clubWeight),
                null,
                "oneClub",
                null
            )
        );
        menu.addItem(
            new WatchUi.MenuItem(
                Equipment.labelFor(Equipment.TYPE_CLUBS, 2, clubWeight),
                null,
                "twoClubs",
                null
            )
        );
        return menu;
    }
}

class EquipmentMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _view as MaceClubsView;

    function initialize(view as MaceClubsView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        var kind = Equipment.TYPE_CLUBS;
        var quantity = 2;
        if (id.equals("mace")) {
            kind = Equipment.TYPE_MACE;
            quantity = 1;
        } else if (id.equals("oneClub")) {
            quantity = 1;
        }
        _view.chooseEquipment(kind, quantity);
        // Movement follows equipment: replace this menu with the movement
        // picker, which starts the workout once a movement is chosen.
        WatchUi.switchToView(
            MovementMenu.build(kind),
            new MovementMenuDelegate(_view, true),
            WatchUi.SLIDE_LEFT
        );
    }
}
