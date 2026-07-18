import Toybox.Lang;
import Toybox.WatchUi;

// Instinct 3 controls:
//   SELECT (top right)  - start workout / mark a set / (paused) save & exit
//   BACK (bottom right) - pause / (paused) resume / (idle) quit
//   UP / DOWN (left)    - idle: choose workout preset; in workout: tempo +-5 bpm
//   MENU (hold CTRL)    - idle: settings menu; in workout: discard & go home
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
        } else if (_view.isStarting()) {
            return true;
        } else if (!_view.workout.isStarted()) {
            _view.startWorkout();
        } else if (_view.plan == null) {
            // manual set marking is free-training only; presets count sets
            _view.markSet();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        if (_view.isStarting()) {
            _view.cancelStartCountdown();
            return true;
        }
        if (_view.done) {
            // a finished interval workout can only be saved
            return true;
        }
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

    // MENU (hold the CTRL / up-left button): opens the settings menu when
    // idle, or discard-and-return-home (behind a confirmation, so a stray
    // press cannot bin a real session) once a workout is running.
    function onMenu() as Boolean {
        if (_view.isStarting()) {
            return true;
        }
        if (_view.workout.isStarted()) {
            WatchUi.pushView(
                new WatchUi.Confirmation("Discard & go home?"),
                new DiscardConfirmationDelegate(_view),
                WatchUi.SLIDE_IMMEDIATE
            );
        } else {
            WatchUi.pushView(SettingsMenu.build(), new SettingsMenuDelegate(_view), WatchUi.SLIDE_UP);
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_view.isStarting()) {
            return true;
        } else if (_view.workout.isStarted()) {
            _view.metronome.adjustBpm(1);
        } else {
            _view.cyclePreset(-1);
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {
        if (_view.isStarting()) {
            return true;
        } else if (_view.workout.isStarted()) {
            _view.metronome.adjustBpm(-1);
        } else {
            _view.cyclePreset(1);
        }
        WatchUi.requestUpdate();
        return true;
    }
}
