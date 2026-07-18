import Toybox.Lang;
import Toybox.WatchUi;

// Confirms the destructive "discard workout" before returning to the app's
// home screen; any response other than an explicit Yes leaves it intact.
class DiscardConfirmationDelegate extends WatchUi.ConfirmationDelegate {
    private var _view as MaceClubsView;

    function initialize(view as MaceClubsView) {
        ConfirmationDelegate.initialize();
        _view = view;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            _view.discardWorkout();
        }
        return true;
    }
}
