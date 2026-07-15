import Toybox.Lang;
import Toybox.WatchUi;

// Instinct 3 controls:
//   SELECT (top right)  - start/stop the metronome
//   UP / DOWN (left)    - adjust tempo in 5 bpm steps
class MaceClubsDelegate extends WatchUi.BehaviorDelegate {

    private var _view as MaceClubsView;

    function initialize(view as MaceClubsView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        if (_view.metronome.isRunning()) {
            _view.metronome.stop();
        } else {
            _view.metronome.start();
        }
        WatchUi.requestUpdate();
        return true;
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
