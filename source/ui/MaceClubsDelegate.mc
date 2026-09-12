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

    // Taps at or below this share of a running screen go to the menu; above
    // it they do what SELECT does. Both screens that use it draw their menu
    // hint in that band and nothing else there - the paused screen stacks
    // "SELECT save", "BACK resume" and the discard line at 69/79/89%, and
    // the free-rest screen puts its options hint at 92%, clear of the metric
    // row above.
    const HINT_BAND_TOP_PERCENT = 84;

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
        if (tapRoutingActive()) {
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
        // Paused, on a watch with no MENU key: the screen says "TAP discard"
        // - DeviceInput.menuLabel has no better word for the gesture there -
        // and a tap has to mean it. It did not. onTap declined, the framework
        // turned the unhandled tap into a select, and the gesture advertised
        // as discard saved the workout and opened the summary: the opposite
        // of what the user was told, on the seven devices where it is the
        // only gesture they have.
        //
        // This is not the stray tap the idle-only rule below guards against.
        // Reaching a paused screen takes a deliberate BACK, and discard is
        // behind its own "Discard & go home?" confirmation. A finished
        // interval workout is excluded because it can only be saved, which
        // is what its own screen says.
        var height = System.getDeviceSettings().screenHeight;
        if (DeviceInput.needsMenuTapTarget() && !_view.done && (_view.paused || _view.isFreeResting())) {
            // Routed by position, like the idle screen below, because a tap
            // and the physical SELECT key are the same event to the
            // simulator and both screens offer both: "SELECT save" beside
            // "TAP discard" when paused, "SELECT: work" beside "TAP options"
            // while resting. Sending every tap to the menu made SELECT do it
            // too. Only the band the menu hint sits in reaches the menu, and
            // onMenu already knows which menu that is - rest options while
            // free-resting, the discard confirmation when paused.
            if (event.getCoordinates()[1] >= height * HINT_BAND_TOP_PERCENT / 100) {
                return onMenu();
            }
            return handleSelect();
        }
        if (!tapMenuActive()) {
            return false;
        }
        if (event.getCoordinates()[1] >= height * MENU_TAP_TOP_PERCENT / 100) {
            return onMenu();
        }
        return handleSelect();
    }

    // onSelect() declines on these devices so taps can be routed by position,
    // which would otherwise leave the physical SELECT key doing nothing -
    // vivoactive6 and the venu 4 family both have one.
    function onKey(event as WatchUi.KeyEvent) as Boolean {
        if (tapRoutingActive() && event.getKey() == WatchUi.KEY_ENTER) {
            return handleSelect();
        }
        return false;
    }

    // Where a tap must be routed by position or by hint rather than taken as
    // a select, on the devices whose only gesture is a tap.
    //
    // Both screens that route taps have to be here together, because onSelect
    // declining is what lets a tap reach onTap at all - a BehaviorDelegate
    // offers the behaviour first. Listing only the idle screen is what left
    // the paused screen saying "TAP discard" while a tap saved the workout:
    // onSelect took the tap, and onTap never ran.
    //
    // onKey below reads the same predicate, so the physical SELECT key keeps
    // working on the screens where onSelect has stepped aside.
    private function tapRoutingActive() as Boolean {
        if (!DeviceInput.needsMenuTapTarget() || _view.isStarting() || _view.done) {
            return false;
        }
        return !_view.workout.isStarted() || _view.paused || _view.isFreeResting();
    }

    // The idle screen on a device that has no other way into the menu.
    private function tapMenuActive() as Boolean {
        return DeviceInput.needsMenuTapTarget() && !_view.workout.isStarted() && !_view.isStarting();
    }

    private function showHomeConfirmation() as Void {
        WatchUi.pushView(
            new WatchUi.Confirmation(RestOptionsMenu.discardPrompt()),
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
