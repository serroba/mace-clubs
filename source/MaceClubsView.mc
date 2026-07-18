import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Layout notes: the Instinct family (semi-octagon screens) has a physical
// subwindow cut-out in the top-right corner (x >= 114, y <= 62 on the 45mm
// per personality.mss) - top text is left-aligned to avoid it. All other
// shapes (round, rectangle) get centered top anchors, which stay inside a
// round screen's visible chord.
class MaceClubsView extends WatchUi.View {
    const START_DELAY_MS = 5000;

    var metronome as Metronome;
    var workout as WorkoutSession;
    var paused as Boolean = false;
    var done as Boolean = false;
    var presetIndex as Number = 0;
    var plan as Intervals.Plan?;

    private var _refreshTimer as Timer.Timer;
    private var _startTimer as Timer.Timer;
    private var _starting as Boolean = false;
    private var _startDeadline as Number = 0;
    private var _lastPhase as Number?;
    private var _lastSet as Number = 0;
    private var _warnedSet as Number = 0;
    private var _icon as WatchUi.BitmapResource;
    private var _subwindow as Boolean = false;
    private var _circleRounds as Boolean = true;

    function initialize() {
        View.initialize();
        metronome = new Metronome();
        workout = new WorkoutSession();
        _refreshTimer = new Timer.Timer();
        _startTimer = new Timer.Timer();
        _icon = WatchUi.loadResource(Rez.Drawables.LauncherIcon) as WatchUi.BitmapResource;
        if (System has :SCREEN_SHAPE_SEMI_OCTAGON) {
            _subwindow = System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_SEMI_OCTAGON;
        }
        loadSettings();
    }

    // Applies phone-editable settings; called at startup and from
    // AppBase.onSettingsChanged when edited mid-session.
    function loadSettings() as Void {
        metronome.loadSettings();
        // metronome.loadSettings re-applies the phone pattern; a running
        // workout keeps its own preset pattern, so restore it.
        if (workout.isStarted()) {
            var preset = selectedPreset();
            metronome.applyPattern(preset[:beatsA] as Number, preset[:beatsB] as Number);
        }
        try {
            var c = Application.Properties.getValue("circleShows");
            if (c instanceof Number) {
                _circleRounds = c == 0;
            }
        } catch (e) {}
    }

    function onShow() as Void {
        _refreshTimer.start(method(:onRefresh), 1000, true);
    }

    function onHide() as Void {
        _refreshTimer.stop();
    }

    function onRefresh() as Void {
        checkPlan();
        WatchUi.requestUpdate();
    }

    function selectedPreset() as Dictionary {
        return Presets.get(presetIndex);
    }

    // Short pattern tag for the idle screen: "4-2" for a varying club
    // pattern, "fixed 4" for a single uniform loop.
    private function patternLabel(preset as Dictionary) as String {
        var a = preset[:beatsA] as Number;
        var b = preset[:beatsB] as Number;
        return b > 0 ? Lang.format("$1$-$2$", [a, b]) : Lang.format("fixed $1$", [a]);
    }

    function cyclePreset(dir as Number) as Void {
        var n = Presets.count();
        presetIndex = (presetIndex + dir + n) % n;
    }

    function isStarting() as Boolean {
        return _starting;
    }

    function getStartCountdownRemaining() as Number {
        return _starting ? Intervals.countdownSeconds(System.getTimer(), _startDeadline) : 0;
    }

    // Prepare the selected preset, then wait five seconds before recording
    // or starting the metronome so the athlete can get into position.
    function startWorkout() as Void {
        if (_starting || workout.isStarted()) {
            return;
        }
        var preset = selectedPreset();
        var sets = preset[:sets] as Number;
        if (sets > 0) {
            plan = new Intervals.Plan(sets, preset[:work] as Number, preset[:rest] as Number);
        } else {
            plan = null;
        }
        done = false;
        _lastPhase = null;
        _lastSet = 0;
        _warnedSet = 0;
        metronome.resetBeatCount();
        metronome.applyPattern(preset[:beatsA] as Number, preset[:beatsB] as Number);
        _starting = true;
        _startDeadline = System.getTimer() + START_DELAY_MS;
        _startTimer.start(method(:beginWorkout), START_DELAY_MS, false);
    }

    private function beginWorkout() as Void {
        if (!_starting) {
            return;
        }
        _starting = false;
        workout.start();
        metronome.start();
        playTransitionCue(false);
        WatchUi.requestUpdate();
    }

    function cancelStartCountdown() as Void {
        if (_starting) {
            _startTimer.stop();
            _starting = false;
            plan = null;
            WatchUi.requestUpdate();
        }
    }

    // Free-training set mark: log the set and start a fresh round count.
    function markSet() as Void {
        workout.addSet();
        metronome.resetBeatCount();
    }

    // Throw the session away without saving and leave the app. Reached
    // from the paused/done screen via MENU (behind a confirmation).
    function discardWorkout() as Void {
        metronome.stop();
        workout.discardAndExit();
    }

    // Detect work/rest/done transitions once per refresh tick and fire
    // the matching cues. Plan state comes from the FIT timer, so a
    // paused session holds its phase automatically.
    private function checkPlan() as Void {
        var p = plan;
        if (p == null || !workout.isStarted() || paused) {
            return;
        }
        var info = Activity.getActivityInfo();
        if (info == null || info.timerTime == null) {
            return;
        }
        var s = p.stateAt(info.timerTime as Number);
        var phase = s[:phase] as Number;
        var set = s[:set] as Number;
        var remaining = s[:remaining] as Number;
        if (Intervals.shouldWarnNextWork(phase, remaining, set, p.getSets(), _warnedSet)) {
            _warnedSet = set;
            playAdvanceWarningCue();
        }
        var oldPhase = _lastPhase;
        var oldSet = _lastSet;
        _lastPhase = phase;
        _lastSet = set;
        if (oldPhase == null || phase == oldPhase && set == oldSet) {
            return;
        }
        onPlanTransition(oldPhase as Number, oldSet, phase, set);
    }

    private function onPlanTransition(oldPhase as Number, oldSet as Number, phase as Number, set as Number) as Void {
        var actions = Intervals.actionsForTransition(oldPhase, oldSet, phase, set);
        var setsToAdd = actions[:setsToAdd] as Number;
        for (var i = 0; i < setsToAdd; i++) {
            workout.addSet();
        }
        if (actions[:stopMetronome] as Boolean) {
            metronome.stop();
        }
        if (actions[:resetBeatCount] as Boolean) {
            metronome.resetBeatCount();
        }
        if (actions[:startMetronome] as Boolean) {
            metronome.start();
        }
        var finished = actions[:finished] as Boolean;
        playTransitionCue(finished);
        if (actions[:pauseWorkout] as Boolean) {
            workout.pause();
            paused = true;
            done = true;
        }
    }

    // Honours the same beep/vibrate toggles as the beat cue, so turning a
    // channel off silences it at set boundaries too, not just on beats.
    private function playTransitionCue(finished as Boolean) as Void {
        if (metronome.isToneEnabled() && Attention has :playTone) {
            Attention.playTone(finished ? Attention.TONE_SUCCESS : Attention.TONE_INTERVAL_ALERT);
        }
        if (metronome.isVibeEnabled() && Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, 400)]);
        }
    }

    // A double pulse distinguishes the five-second warning from the longer
    // transition pulse that announces the actual start of work.
    private function playAdvanceWarningCue() as Void {
        if (metronome.isToneEnabled() && Attention has :playTone) {
            Attention.playTone(Attention.TONE_INTERVAL_ALERT);
        }
        if (metronome.isVibeEnabled() && Attention has :vibrate) {
            Attention.vibrate(
                [
                    new Attention.VibeProfile(100, 120),
                    new Attention.VibeProfile(0, 80),
                    new Attention.VibeProfile(100, 120)
                ]
            );
        }
    }

    private function formatSecs(total as Number) as String {
        return Lang.format("$1$:$2$", [total / 60, (total % 60).format("%02d")]);
    }

    private function smoothnessText(useCurrent as Boolean) as String {
        var score = useCurrent ? workout.getSmoothnessScore() : workout.getLastSmoothnessScore();
        if (score < 0) {
            return "";
        }
        if (!workout.hasSmoothnessDelta()) {
            return Lang.format("smooth $1$", [score]);
        }
        var delta = workout.getSmoothnessDelta();
        var change = delta > 0 ? Lang.format("+$1$", [delta]) : delta.toString();
        return Lang.format("smooth $1$ ($2$)", [score, change]);
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var cx = w / 2;
        var h = dc.getHeight();

        if (_starting) {
            dc.drawText(cx, h * 20 / 100, Graphics.FONT_SMALL, "GET READY", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(
                cx,
                h * 38 / 100,
                Graphics.FONT_NUMBER_HOT,
                getStartCountdownRemaining().toString(),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 74 / 100,
                Graphics.FONT_TINY,
                selectedPreset()[:label] as String,
                Graphics.TEXT_JUSTIFY_CENTER
            );
            return;
        }

        if (paused) {
            dc.drawText(
                cx,
                h * 22 / 100,
                Graphics.FONT_MEDIUM,
                done ? "DONE!" : "PAUSED",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            var smoothness = smoothnessText(true);
            if (smoothness != "") {
                dc.drawText(cx, h * 39 / 100, Graphics.FONT_TINY, smoothness, Graphics.TEXT_JUSTIFY_CENTER);
            }
            dc.drawText(cx, h * 53 / 100, Graphics.FONT_SMALL, "SELECT: save", Graphics.TEXT_JUSTIFY_CENTER);
            if (!done) {
                dc.drawText(
                    cx,
                    h * 67 / 100,
                    Graphics.FONT_SMALL,
                    "BACK: resume",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
            dc.drawText(
                cx,
                h * (done ? 68 : 81) / 100,
                Graphics.FONT_SMALL,
                "MENU: discard",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            return;
        }

        if (!workout.isStarted()) {
            // crossed mace-and-club art above the preset label; on subwindow
            // devices shifted left of the cut-out, elsewhere centered
            var iconY = h * 38 / 100 - 70;
            if (iconY < 2) {
                iconY = 2;
            }
            dc.drawBitmap(_subwindow ? cx - 45 : cx - 31, iconY, _icon);
            dc.drawText(
                cx,
                h * 38 / 100,
                Graphics.FONT_MEDIUM,
                selectedPreset()[:label] as String,
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 54 / 100,
                Graphics.FONT_TINY,
                Lang.format("$1$ bpm | $2$", [metronome.getBpm(), patternLabel(selectedPreset())]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(cx, h * 68 / 100, Graphics.FONT_SMALL, "SELECT to start", Graphics.TEXT_JUSTIFY_CENTER);
            var previousSmoothness = smoothnessText(false);
            if (previousSmoothness == "") {
                dc.drawText(
                    cx,
                    h * 82 / 100,
                    Graphics.FONT_TINY,
                    "MENU: settings",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            } else {
                dc.drawText(
                    cx,
                    h * 80 / 100,
                    Graphics.FONT_TINY,
                    previousSmoothness,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    cx,
                    h * 90 / 100,
                    Graphics.FONT_TINY,
                    "MENU: settings",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
            return;
        }

        var info = Activity.getActivityInfo();
        var timerMs = 0;
        if (info != null && info.timerTime != null) {
            timerMs = info.timerTime as Number;
        }

        var hr = "--";
        if (info != null && info.currentHeartRate != null) {
            hr = (info.currentHeartRate as Number).toString();
        }
        var rounds = metronome.getRounds().toString();
        var circleValue = _circleRounds ? rounds : hr;
        var otherValue = _circleRounds ? hr : rounds;
        var otherLabel = _circleRounds ? "hr" : "rnds";

        var p = plan;
        if (p != null) {
            // Interval workout: phase + countdown drive the screen
            var s = p.stateAt(timerMs);
            var phase = s[:phase] as Number;
            if (_subwindow) {
                // elapsed sits inside the semi-octagon's diagonal corner cut,
                // so it is nudged inward; live HR gets the subwindow itself
                dc.drawText(
                    w * 14 / 100,
                    h * 8 / 100,
                    Graphics.FONT_TINY,
                    formatSecs(timerMs / 1000),
                    Graphics.TEXT_JUSTIFY_LEFT
                );
                drawSubwindowMetric(dc, circleValue);
            } else {
                dc.drawText(
                    cx,
                    h * 6 / 100,
                    Graphics.FONT_TINY,
                    formatSecs(timerMs / 1000),
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
            dc.drawText(
                cx,
                h * 30 / 100,
                Graphics.FONT_SMALL,
                Lang.format(
                    "SET $1$/$2$  $3$",
                    [s[:set], p.getSets(), phase == Intervals.PHASE_REST ? "REST" : "WORK"]
                ),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 40 / 100,
                Graphics.FONT_NUMBER_HOT,
                formatSecs(s[:remaining] as Number),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            if (_subwindow) {
                dc.drawText(
                    cx - 35,
                    h * 72 / 100,
                    Graphics.FONT_MEDIUM,
                    metronome.getBpm().toString(),
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(cx - 35, h * 87 / 100, Graphics.FONT_TINY, "bpm", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(
                    cx + 35,
                    h * 72 / 100,
                    Graphics.FONT_MEDIUM,
                    otherValue,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    cx + 35,
                    h * 87 / 100,
                    Graphics.FONT_TINY,
                    otherLabel,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            } else {
                dc.drawText(
                    cx - 50,
                    h * 72 / 100,
                    Graphics.FONT_MEDIUM,
                    metronome.getBpm().toString(),
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(cx - 50, h * 87 / 100, Graphics.FONT_TINY, "bpm", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(cx, h * 72 / 100, Graphics.FONT_MEDIUM, rounds, Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(cx, h * 87 / 100, Graphics.FONT_TINY, "rnds", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(cx + 50, h * 72 / 100, Graphics.FONT_MEDIUM, hr, Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(cx + 50, h * 87 / 100, Graphics.FONT_TINY, "hr", Graphics.TEXT_JUSTIFY_CENTER);
            }
            return;
        }

        // Free training: elapsed time front and center, tempo and manual
        // set counter below; HR in the subwindow where the screen has one
        if (_subwindow) {
            drawSubwindowMetric(dc, circleValue);
            dc.drawText(
                cx,
                h * 22 / 100,
                Graphics.FONT_NUMBER_MILD,
                formatSecs(timerMs / 1000),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 48 / 100,
                Graphics.FONT_MEDIUM,
                Lang.format("$1$ bpm", [metronome.getBpm()]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx - 30,
                h * 64 / 100,
                Graphics.FONT_MEDIUM,
                workout.getSets().toString(),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(cx - 30, h * 80 / 100, Graphics.FONT_TINY, "sets", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx + 30, h * 64 / 100, Graphics.FONT_MEDIUM, otherValue, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx + 30, h * 80 / 100, Graphics.FONT_TINY, otherLabel, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        dc.drawText(
            cx,
            h * 6 / 100,
            Graphics.FONT_MEDIUM,
            formatSecs(timerMs / 1000),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            cx,
            h * 32 / 100,
            Graphics.FONT_NUMBER_HOT,
            metronome.getBpm().toString(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(cx, h * 56 / 100, Graphics.FONT_TINY, "bpm", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(
            cx - 50,
            h * 68 / 100,
            Graphics.FONT_MEDIUM,
            workout.getSets().toString(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(cx - 50, h * 84 / 100, Graphics.FONT_TINY, "sets", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 68 / 100, Graphics.FONT_MEDIUM, rounds, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 84 / 100, Graphics.FONT_TINY, "rnds", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx + 50, h * 68 / 100, Graphics.FONT_MEDIUM, hr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx + 50, h * 84 / 100, Graphics.FONT_TINY, "hr", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Draw a metric (rounds or heart rate, per the circleShows setting)
    // inside the Instinct's circular subwindow. getSubscreen gives exact
    // bounds on CIQ 4.2+; older Instincts fall back to the family's
    // typical top-right placement.
    private function drawSubwindowMetric(dc as Dc, value as String) as Void {
        var sx = dc.getWidth() * 82 / 100;
        var sy = dc.getHeight() * 17 / 100;
        var sw = dc.getWidth() * 20 / 100;
        var sh = dc.getHeight() * 20 / 100;
        if (WatchUi has :getSubscreen) {
            var sub = WatchUi.getSubscreen();
            if (sub != null) {
                sx = (sub.x as Number) + (sub.width as Number) / 2;
                sy = (sub.y as Number) + (sub.height as Number) / 2;
                sw = sub.width as Number;
                sh = sub.height as Number;
            }
        }
        // Fill the circle: pick the largest font whose text fits the
        // subwindow, rather than a fixed small one floating in the middle.
        var fonts = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY] as Array<Graphics.FontDefinition>;
        var font = Graphics.FONT_TINY;
        for (var i = 0; i < fonts.size(); i++) {
            var dims = dc.getTextDimensions(value, fonts[i]);
            if (dims[0] <= sw * 90 / 100 && dims[1] <= sh * 95 / 100) {
                font = fonts[i];
                break;
            }
        }
        dc.drawText(sx, sy, font, value, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
