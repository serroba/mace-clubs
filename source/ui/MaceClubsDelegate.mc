import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Instinct 3 controls:
//   SELECT (top right)  - start workout / mark a set / (paused) save & show summary
//   BACK (bottom right) - pause / (paused) resume / (idle) quit
//   UP / DOWN (left)    - idle: choose workout preset; in workout: tempo +-5 bpm
//                         (free-flow rest: page through extra info screens instead)
//   MENU (hold CTRL)    - idle: settings menu; in workout: discard & go home
//
// Other hardware raises the same behaviours differently, and this delegate
// only ever sees the behaviour - except for MENU, which seven touch devices
// cannot raise at all. See onTap() and DeviceInput for that gap; the on-screen
// hints name whichever affordance the running device actually has.
class MaceClubsDelegate extends WatchUi.BehaviorDelegate {
    // Taps at or below this share of the screen open the menu on devices with
    // no MENU key; it sits just above the idle screen's hint line.
    const MENU_TAP_TOP_PERCENT = 62;

    private var _view as MaceClubsView;

    function initialize(view as MaceClubsView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Declining here on the tap-target devices is what lets a tap reach
    // onTap(): a BehaviorDelegate offers the behaviour first and only falls
    // back to the raw input event if the behaviour goes unhandled - verified
    // in the simulator on vivoactive6, where returning true from onSelect
    // swallowed every tap into "start workout". Declining also silences the
    // physical SELECT key, so onKey() picks that back up below.
    function onSelect() as Boolean {
        if (tapMenuActive()) {
            return false;
        }
        return handleSelect();
    }

    private function handleSelect() as Boolean {
        if (_view.paused) {
            _view.metronome.stop();
            _view.finishWorkout();
        } else if (_view.isStarting()) {
            return true;
        } else if (!_view.workout.isStarted()) {
            WatchUi.pushView(EquipmentMenu.build(), new EquipmentMenuDelegate(_view), WatchUi.SLIDE_UP);
        } else if (_view.plan == null) {
            // Free training alternates explicit work and rest phases.
            _view.advanceFreeTraining();
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
            if (!_view.isFreeResting() && !_view.isRepMode()) {
                _view.metronome.start();
            }
            WatchUi.requestUpdate();
            return true;
        }
        if (_view.workout.isStarted()) {
            if (_view.isFreeResting()) {
                _view.workout.endRestLap();
            }
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
            if (_view.isFreeResting() && !_view.paused) {
                // Rest is the natural moment to change movement for the next
                // set; discard stays reachable inside the same menu.
                WatchUi.pushView(
                    RestOptionsMenu.build(_view.workout),
                    new RestOptionsDelegate(_view),
                    WatchUi.SLIDE_UP
                );
            } else {
                showHomeConfirmation();
            }
        } else {
            WatchUi.pushView(SettingsMenu.build(), new SettingsMenuDelegate(_view), WatchUi.SLIDE_UP);
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_view.paused) {
            _view.cycleSummary(-1);
            return true;
        }
        if (_view.isFreeResting()) {
            _view.cycleRestPage(-1);
            WatchUi.requestUpdate();
            return true;
        }
        var action = Navigation.previousPageAction(_view.isStarting(), _view.workout.isStarted(), _view.paused);
        if (action == Navigation.PREVIOUS_IGNORE) {
            return true;
        } else if (action == Navigation.PREVIOUS_HOME) {
            showHomeConfirmation();
        } else if (action == Navigation.PREVIOUS_TEMPO_UP) {
            if (_view.isRepMode()) {
                _view.adjustRepCount(1);
            } else {
                _view.metronome.adjustBpm(1);
            }
        } else {
            _view.cyclePreset(-1);
        }
        WatchUi.requestUpdate();
        return true;
    }

    // Seven shipped devices have no MENU key - venu441mm, venu445mm, venux1,
    // vivoactive6 and the three vivoactive3 variants - so onMenu() can never
    // fire on them, and settings, history and the custom-workout editor were
    // unreachable. Confirmed in the simulator on vivoactive6: a long-press on
    // the screen does nothing and a long-press of BACK exits the app. They are
    // all touch devices, so on the idle screen the lower part of the display -
    // where the "TAP opens settings" hint sits - opens the menu, and the rest
    // of the screen still starts a workout.
    //
    // Only while idle: once a workout is running a stray tap must not be able
    // to reach the discard path.
    function onTap(event as WatchUi.ClickEvent) as Boolean {
        if (!tapMenuActive()) {
            return false;
        }
        var coords = event.getCoordinates();
        if (coords[1] >= System.getDeviceSettings().screenHeight * MENU_TAP_TOP_PERCENT / 100) {
            return onMenu();
        }
        return handleSelect();
    }

    // onSelect() declines on these devices so taps can be routed by position,
    // which would otherwise leave the physical SELECT key doing nothing -
    // vivoactive6 and the venu 4 family both have one.
    function onKey(event as WatchUi.KeyEvent) as Boolean {
        if (tapMenuActive() && event.getKey() == WatchUi.KEY_ENTER) {
            return handleSelect();
        }
        return false;
    }

    // The idle screen on a device that has no other way into the menu.
    private function tapMenuActive() as Boolean {
        return DeviceInput.needsMenuTapTarget() && !_view.workout.isStarted() && !_view.isStarting();
    }

    private function showHomeConfirmation() as Void {
        WatchUi.pushView(
            new WatchUi.Confirmation("Discard & go home?"),
            new DiscardConfirmationDelegate(_view),
            WatchUi.SLIDE_IMMEDIATE
        );
    }

    function onNextPage() as Boolean {
        if (_view.isStarting()) {
            return true;
        } else if (_view.paused) {
            _view.cycleSummary(1);
        } else if (_view.isFreeResting()) {
            _view.cycleRestPage(1);
        } else if (_view.workout.isStarted()) {
            if (_view.isRepMode()) {
                _view.adjustRepCount(-1);
            } else {
                _view.metronome.adjustBpm(-1);
            }
        } else {
            _view.cyclePreset(1);
        }
        WatchUi.requestUpdate();
        return true;
    }
}
