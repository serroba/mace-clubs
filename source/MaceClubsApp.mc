import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class MaceClubsApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new MaceClubsView();
        return [view, new MaceClubsDelegate(view)];
    }
}
