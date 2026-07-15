import Toybox.Lang;
import Toybox.WatchUi;

// Instinct 3 controls:
//   SELECT (top right)  - start workout / mark a set / (paused) save & exit
//   BACK (bottom right) - pause / (paused) resume / (idle) quit
//   UP / DOWN (left)    - adjust tempo in 5 bpm steps
class MaceClubsDelegate extends WatchUi.BehaviorDelegate {

    private var _view as MaceClubsView;

    function initialize(view as MaceClubsView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        if (_view.paused) {
            _view.metronome.stop();
            _view.workout.saveAndExit();
        } else if (!_view.workout.isStarted()) {
            _view.workout.start();
            _view.metronome.start();
        } else {
            _view.workout.addSet();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        if (_view.paused) {
            _view.paused = false;
            _view.workout.resume();
            _view.metronome.start();
            WatchUi.requestUpdate();
            return true;
        }
        if (_view.workout.isStarted()) {
            _view.paused = true;
            _view.workout.pause();
            _view.metronome.stop();
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function onPreviousPage() as Boolean {
        _view.metronome.adjustBpm(1);
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {
        _view.metronome.adjustBpm(-1);
        WatchUi.requestUpdate();
        return true;
    }
}
