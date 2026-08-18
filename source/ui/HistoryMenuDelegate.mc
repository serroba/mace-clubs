import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.WatchUi;

// Opens the per-set detail view for the chosen session. Item ids are the
// record's index in the stored log; the "No sessions yet" placeholder carries a
// String id and is ignored.
class HistoryMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (!(id instanceof Number)) {
            return;
        }
        var log = HistoryMenu.read();
        if (id < 0 || id >= log.size()) {
            return;
        }
        var view = new HistoryDetailView(log[id] as Array<Storage.ValueType>);
        WatchUi.pushView(view, new HistoryDetailDelegate(view), WatchUi.SLIDE_UP);
    }
}
