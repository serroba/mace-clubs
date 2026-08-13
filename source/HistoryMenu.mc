import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// Idle-only session browser for the local smoothness history, reached from
// Settings. Lists saved sessions newest-first; selecting one opens the per-set
// scroll view. Instinct's circular safe area is too short for Menu2 secondary
// labels (see SettingsMenu), so each row keeps its date and score in one
// compact primary label and the implement is shown on the detail screen.
module HistoryMenu {
    function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "History"});
        var log = read();
        if (log.size() == 0) {
            menu.addItem(new WatchUi.MenuItem("No sessions yet", null, "none", null));
            return menu;
        }
        for (var i = log.size() - 1; i >= 0; i--) {
            var rec = log[i] as Array<Storage.ValueType>;
            menu.addItem(
                new WatchUi.MenuItem(
                    Lang.format("$1$  $2$", [stamp(SmoothnessLog.epochOf(rec)), SmoothnessLog.scoreOf(rec)]),
                    null,
                    i,
                    null
                )
            );
        }
        return menu;
    }

    // The persisted log, or an empty array when nothing has been saved yet or
    // the stored value is not the shape we wrote.
    function read() as Array<Storage.ValueType> {
        try {
            var stored = Storage.getValue(SmoothnessLog.STORAGE_KEY);
            if (stored instanceof Array) {
                return stored as Array<Storage.ValueType>;
            }
        } catch (e) {}
        return [] as Array<Storage.ValueType>;
    }

    // Compact local timestamp, e.g. "8 Aug 10:03". Shared by the detail view.
    function stamp(epoch as Number) as String {
        var info = Time.Gregorian.info(new Time.Moment(epoch), Time.FORMAT_MEDIUM);
        return Lang.format("$1$ $2$ $3$:$4$", [info.day, info.month, info.hour, info.min.format("%02d")]);
    }
}
