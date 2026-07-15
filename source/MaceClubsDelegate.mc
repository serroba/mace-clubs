import Toybox.Lang;
import Toybox.WatchUi;

class MaceClubsDelegate extends WatchUi.BehaviorDelegate {

    private var _view as MaceClubsView;

    function initialize(view as MaceClubsView) {
        BehaviorDelegate.initialize();
        _view = view;
    }
}
