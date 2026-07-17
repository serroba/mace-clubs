import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Applies settings-menu changes to the persisted app properties, then
// reloads the view so a change takes effect the moment the menu closes
// (or immediately, for the live display settings).
class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _view as MaceClubsView;

    function initialize(view as MaceClubsView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (item instanceof WatchUi.ToggleMenuItem) {
            // Toggle items flip their own state; persist the new value.
            Application.Properties.setValue(id, (item as WatchUi.ToggleMenuItem).isEnabled());
        } else if (id.equals("circleShows")) {
            Application.Properties.setValue("circleShows", SettingsMenu.numProp("circleShows", 0) == 0 ? 1 : 0);
            item.setSubLabel(SettingsMenu.cornerLabel());
        } else if (id.equals("cueMode")) {
            Application.Properties.setValue("cueMode", (SettingsMenu.numProp("cueMode", 0) + 1) % 3);
            item.setSubLabel(SettingsMenu.cueLabel());
        }
        _view.loadSettings();
        WatchUi.requestUpdate();
    }
}
