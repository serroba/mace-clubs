import Toybox.Lang;
import Toybox.WatchUi;

// UP/DOWN scroll the sets (matching the end-of-workout summary), BACK returns to
// the session list.
class HistoryDetailDelegate extends WatchUi.BehaviorDelegate {
    private var _view as HistoryDetailView;

    function initialize(view as HistoryDetailView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onPreviousPage() as Boolean {
        _view.scroll(-1);
        return true;
    }

    function onNextPage() as Boolean {
        _view.scroll(1);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
