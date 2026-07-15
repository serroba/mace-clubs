import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class MaceClubsApp extends Application.AppBase {
    private var _view as MaceClubsView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {}

    function onStop(state as Dictionary?) as Void {}

    // Called when settings are changed from the Garmin Connect phone app
    // while this app is running.
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.metronome.loadSettings();
        }
        WatchUi.requestUpdate();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new MaceClubsView();
        _view = view;
        return [view, new MaceClubsDelegate(view)];
    }
}
