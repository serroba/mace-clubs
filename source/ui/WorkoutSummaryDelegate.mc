import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// BACK or SELECT exits right away, matching the paused/done screen's SELECT
// convention; MaceClubsView.finishWorkout also arms a timeout so the app
// still exits if the watch is left face-up after a save.
class WorkoutSummaryDelegate extends WatchUi.BehaviorDelegate {
    private var _view as WorkoutSummaryView;

    function initialize(view as WorkoutSummaryView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.cyclePage(1);
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.cyclePage(-1);
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        System.exit();
        return true;
    }

    function onSelect() as Boolean {
        System.exit();
        return true;
    }
}
