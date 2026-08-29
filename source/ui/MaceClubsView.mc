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
    // Free-flow rest repurposes UP/DOWN (otherwise idle mid-rest) to page
    // through extra info screens: 0 is the normal rest countup, 1 adds
    // wall-clock time + last-set swings, 2 adds last-set smoothness + load.
    const REST_PAGE_COUNT = 3;
    // How long the post-workout summary waits for a look before the app
    // exits on its own.
    const SUMMARY_EXIT_DELAY_MS = 60000;

    var metronome as Metronome;
    var workout as WorkoutSession;
    var paused as Boolean = false;
    var done as Boolean = false;
    var presetIndex as Number = 0;
    var plan as Intervals.Plan?;
    var freePhase as Number = FreeTraining.PHASE_WORK;

    private var _refreshTimer as Timer.Timer;
    private var _startTimer as Timer.Timer;
    private var _exitTimer as Timer.Timer;
    private var _starting as Boolean = false;
    private var _startDeadline as Number = 0;
    private var _lastPhase as Number?;
    private var _lastSet as Number = 0;
    private var _warnedSet as Number = 0;
    private var _icon as WatchUi.BitmapResource;
    private var _subwindow as Boolean = false;
    private var _circleRounds as Boolean = true;
    private var _freePhaseStartMs as Number = 0;
    private var _summarySet as Number = 0;
    private var _trainingMode as Number = TrainingMode.INTERVAL;
    private var _repTarget as Number = TrainingMode.DEFAULT_TARGET;
    private var _lastRepCount as Number = 0;
    private var _targetAlerted as Boolean = false;
    private var _restPage as Number = 0;

    function initialize() {
        View.initialize();
        metronome = new Metronome();
        workout = new WorkoutSession();
        _refreshTimer = new Timer.Timer();
        _startTimer = new Timer.Timer();
        _exitTimer = new Timer.Timer();
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
        workout.reloadEquipment();
        // metronome.loadSettings re-applies the phone pattern; a running
        // workout keeps its own preset or combo pattern, so restore it.
        if (workout.isStarted()) {
            applyMetronomePattern();
        }
        try {
            var c = Application.Properties.getValue("circleShows");
            if (c instanceof Number) {
                _circleRounds = c == 0;
            }
        } catch (e) {}
        _trainingMode = TrainingMode.normalize(SettingsMenu.numProp("trainingMode", TrainingMode.INTERVAL));
        _repTarget = SettingsMenu.numProp("repTarget", TrainingMode.DEFAULT_TARGET);
    }

    function onShow() as Void {
        _refreshTimer.start(method(:onRefresh), 1000, true);
    }

    function onHide() as Void {
        _refreshTimer.stop();
    }

    function onRefresh() as Void {
        checkPlan();
        checkRepTarget();
        WatchUi.requestUpdate();
    }

    private function checkRepTarget() as Void {
        if (!isRepMode() || paused || isFreeResting() || !workout.isStarted()) {
            return;
        }
        var current = workout.getCurrentSetSwings();
        if (!_targetAlerted && TrainingMode.crossedTarget(_lastRepCount, current, _repTarget)) {
            _targetAlerted = true;
            playTransitionCue(false);
        }
        _lastRepCount = current;
    }

    function isRepMode() as Boolean {
        return _trainingMode == TrainingMode.REPS;
    }

    function adjustRepCount(delta as Number) as Void {
        if (isRepMode() && !isFreeResting()) {
            workout.adjustCurrentSetSwings(delta);
            _lastRepCount = workout.getCurrentSetSwings();
        }
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
        if (!isRepMode() && sets > 0) {
            plan = new Intervals.Plan(sets, preset[:work] as Number, preset[:rest] as Number);
        } else {
            plan = null;
        }
        done = false;
        var challenge = false;
        var challengeFlag = preset[:challenge];
        if (challengeFlag instanceof Boolean) {
            challenge = challengeFlag;
        }
        workout.forceSwingCounting(challenge || isRepMode());
        _lastPhase = null;
        _lastSet = 0;
        _warnedSet = 0;
        freePhase = FreeTraining.PHASE_WORK;
        _lastRepCount = 0;
        _targetAlerted = false;
        _restPage = 0;
        metronome.resetBeatCount();
        applyMetronomePattern();
        _starting = true;
        _startDeadline = System.getTimer() + START_DELAY_MS;
        _startTimer.start(method(:beginWorkout), START_DELAY_MS, false);
    }

    function chooseEquipment(kind as Number, quantity as Number) as Void {
        workout.selectEquipment(kind, quantity);
    }

    function chooseMovement(movementType as Number) as Void {
        workout.selectMovement(movementType);
        applyMetronomePattern();
        // Remember the choice as the default for the next session.
        try {
            Application.Properties.setValue("movementType", workout.getMovementType());
        } catch (e) {}
    }

    // The combo drives its own metronome sequence (one cycle per hand,
    // segment accents on movement changes, double pulse on the hand
    // switch); everything else uses the preset's loop pattern.
    private function applyMetronomePattern() as Void {
        var comboActive = workout.getMovementType() == Movement.TYPE_COMBO;
        if (comboActive) {
            metronome.setPattern(Combo.beats());
        } else {
            var preset = selectedPreset();
            metronome.applyPattern(preset[:beatsA] as Number, preset[:beatsB] as Number);
        }
        metronome.setCycleTopEmphasis(comboActive);
    }

    function chooseWorkingSide(side as Number) as Void {
        workout.selectWorkingSide(side);
        try {
            Application.Properties.setValue("workingSide", workout.getWorkingSide());
        } catch (e) {}
    }

    // Timer callbacks must be public methods: resolving a private method via
    // method(:beginWorkout) compiles but raises Invalid Value at runtime.
    function beginWorkout() as Void {
        if (!_starting) {
            return;
        }
        _starting = false;
        workout.start();
        _freePhaseStartMs = 0;
        if (!isRepMode()) {
            metronome.start();
        }
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

    // Free training advances explicitly between work and rest. Unlike Pause,
    // rest keeps FIT recording and heart-rate capture running.
    function advanceFreeTraining() as Void {
        var elapsedMs = activityTimerMs();
        var duration = (elapsedMs - _freePhaseStartMs) / 1000;
        if (FreeTraining.completesSet(freePhase)) {
            workout.addSetWithDuration(duration);
            metronome.stop();
        } else {
            workout.endRestLapWithDuration(duration);
            workout.beginSmoothnessSet();
            metronome.resetBeatCount();
            if (!isRepMode()) {
                metronome.start();
            }
        }
        _freePhaseStartMs = elapsedMs;
        _summarySet = workout.getSets() - 1;
        freePhase = FreeTraining.nextPhase(freePhase);
        _lastRepCount = 0;
        _targetAlerted = false;
        _restPage = 0;
        playTransitionCue(false);
        WatchUi.requestUpdate();
    }

    function isFreeResting() as Boolean {
        return plan == null && freePhase == FreeTraining.PHASE_REST;
    }

    // UP/DOWN otherwise has nothing to do mid-rest (tempo is meaningless
    // while the metronome is stopped), so free-flow rest repurposes it to
    // page through the extra info screens instead.
    function cycleRestPage(direction as Number) as Void {
        _restPage = (_restPage + direction + REST_PAGE_COUNT) % REST_PAGE_COUNT;
    }

    function getRestPage() as Number {
        return _restPage;
    }

    // Persists the session, then shows the post-workout summary instead of
    // exiting immediately. The summary itself calls exitApp() on BACK or
    // SELECT; this timer is only the backstop for a watch left face-up.
    function finishWorkout() as Void {
        workout.save();
        var summary = new WorkoutSummaryView(workout);
        WatchUi.pushView(summary, new WorkoutSummaryDelegate(summary), WatchUi.SLIDE_UP);
        _exitTimer.start(method(:exitApp), SUMMARY_EXIT_DELAY_MS, false);
    }

    function exitApp() as Void {
        System.exit();
    }

    // Throw the session away without saving and reset to the app's initial
    // preset screen. Reached via MENU behind a confirmation.
    function discardWorkout() as Void {
        metronome.stop();
        workout.discard();
        paused = false;
        done = false;
        plan = null;
        _lastPhase = null;
        _lastSet = 0;
        _warnedSet = 0;
        freePhase = FreeTraining.PHASE_WORK;
        _restPage = 0;
        metronome.resetBeatCount();
        WatchUi.requestUpdate();
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
        var p = plan as Intervals.Plan;
        var actions = Intervals.actionsForTransition(oldPhase, oldSet, phase, set);
        var setsToAdd = actions[:setsToAdd] as Number;
        for (var i = 0; i < setsToAdd; i++) {
            workout.addSetWithDuration(p.getWorkSeconds());
        }
        if (actions[:stopMetronome] as Boolean) {
            metronome.stop();
        }
        if (actions[:resetBeatCount] as Boolean) {
            metronome.resetBeatCount();
        }
        if (actions[:startMetronome] as Boolean) {
            if (oldPhase == Intervals.PHASE_REST) {
                workout.endRestLapWithDuration(p.getRestSeconds());
            }
            workout.beginSmoothnessSet();
            metronome.start();
        }
        var finished = actions[:finished] as Boolean;
        playTransitionCue(finished);
        if (actions[:pauseWorkout] as Boolean) {
            workout.pause();
            paused = true;
            done = true;
            _summarySet = workout.getSets() - 1;
        }
    }

    private function activityTimerMs() as Number {
        var info = Activity.getActivityInfo();
        if (info != null && info.timerTime != null) {
            return info.timerTime as Number;
        }
        return 0;
    }

    // Seconds spent in the current free-training phase so far. Live, not the
    // final duration recorded at the phase boundary (see advanceFreeTraining).
    private function freePhaseElapsedSeconds() as Number {
        var elapsed = (activityTimerMs() - _freePhaseStartMs) / 1000;
        return elapsed < 0 ? 0 : elapsed;
    }

    function cycleSummary(direction as Number) as Void {
        var count = workout.getSets();
        if (count == 0) {
            _summarySet = 0;
            return;
        }
        _summarySet = (_summarySet + direction + count) % count;
        WatchUi.requestUpdate();
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

    private function clockTimeLabel() as String {
        var clock = System.getClockTime();
        var hour = clock.hour % 12;
        if (hour == 0) {
            hour = 12;
        }
        var suffix = clock.hour < 12 ? "am" : "pm";
        return Lang.format("$1$:$2$ $3$", [hour, clock.min.format("%02d"), suffix]);
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

    private function lastSetSmoothnessText() as String {
        var count = workout.getSetSmoothnessCount();
        if (count == 0) {
            return "";
        }
        var index = count - 1;
        var score = workout.getSetSmoothnessScore(index);
        if (score < 0) {
            return Lang.format("set $1$: not enough motion", [count]);
        }
        return Lang.format("set $1$: $2$ ($3$s)", [count, score, workout.getSetSmoothnessWindows(index)]);
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var cx = w / 2;
        var h = dc.getHeight();

        if (_starting) {
            dc.drawText(
                cx,
                h * 20 / 100,
                AppFont.get(Graphics.FONT_SMALL),
                "GET READY",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 38 / 100,
                AppFont.get(Graphics.FONT_NUMBER_HOT),
                getStartCountdownRemaining().toString(),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 74 / 100,
                AppFont.get(Graphics.FONT_TINY),
                workout.getEquipmentLabel(),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 85 / 100,
                AppFont.get(Graphics.FONT_TINY),
                Movement.typeLabel(workout.getMovementType()),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            return;
        }

        if (paused) {
            // The Instinct's circular subwindow occupies the upper-right of
            // the display. Shift the state heading into the clear left area.
            var pausedHeadingX = _subwindow ? w * 32 / 100 : cx;
            dc.drawText(
                pausedHeadingX,
                h * 22 / 100,
                AppFont.get(Graphics.FONT_MEDIUM),
                done ? "DONE!" : "PAUSED",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            var count = workout.getSets();
            var sideCounts = workout.getSideSetCounts();
            var balance = Movement.balanceLabel(sideCounts[0], sideCounts[1]);
            var setsLabel = count == 1 ? "1 set" : Lang.format("$1$ sets", [count]);
            // .equals(), not ==: Monkey C's == on Strings is reference
            // equality, not content equality.
            var headline = balance.equals("")
                ? Lang.format("$1$  $2$ work", [setsLabel, formatSecs(workout.getTotalWorkSeconds())])
                : Lang.format("$1$  $2$", [setsLabel, balance]);
            dc.drawText(
                cx,
                h * 35 / 100,
                AppFont.get(Graphics.FONT_TINY),
                headline,
                Graphics.TEXT_JUSTIFY_CENTER
            );
            if (count > 0) {
                var index = _summarySet;
                if (index < 0 || index >= count) {
                    index = count - 1;
                }
                dc.drawText(
                    cx,
                    h * 45 / 100,
                    AppFont.get(Graphics.FONT_TINY),
                    Lang.format(
                        "$1$ $2$/$3$ W$4$ R$5$",
                        [
                            SummaryText.side(workout, index),
                            index + 1,
                            count,
                            formatSecs(workout.getSetWorkSeconds(index)),
                            formatSecs(workout.getSetRestSeconds(index))
                        ]
                    ),
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                var detail = SummaryText.detail(workout, index);
                if (!detail.equals("")) {
                    dc.drawText(
                        cx,
                        h * 56 / 100,
                        AppFont.get(Graphics.FONT_TINY),
                        detail,
                        Graphics.TEXT_JUSTIFY_CENTER
                    );
                }
            }
            dc.drawText(
                cx,
                h * 69 / 100,
                AppFont.get(Graphics.FONT_XTINY),
                "SELECT save",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            if (!done) {
                dc.drawText(
                    cx,
                    h * 79 / 100,
                    AppFont.get(Graphics.FONT_XTINY),
                    "BACK resume",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
            dc.drawText(
                cx,
                h * (done ? 79 : 89) / 100,
                AppFont.get(Graphics.FONT_XTINY),
                count > 1 ? "UP/DOWN sets" : "MENU discard",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            return;
        }

        if (!workout.isStarted()) {
            // crossed mace-and-club art above the preset label; on subwindow
            // devices shifted left of the cut-out, elsewhere centered
            var preset = selectedPreset();
            var isFreeTraining = preset[:sets] as Number == 0;
            var iconY = h * 38 / 100 - 70;
            if (iconY < 2) {
                iconY = 2;
            }
            dc.drawBitmap(_subwindow ? cx - 45 : cx - 31, iconY, _icon);
            if (isRepMode()) {
                dc.drawText(
                    cx,
                    h * 35 / 100,
                    AppFont.get(Graphics.FONT_SMALL),
                    "REP MODE",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            } else if (!isFreeTraining) {
                dc.drawText(
                    cx,
                    h * 35 / 100,
                    AppFont.get(Graphics.FONT_SMALL),
                    preset[:label] as String,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
            dc.drawText(
                cx,
                h * (isFreeTraining ? 40 : 49) / 100,
                isFreeTraining ? AppFont.get(Graphics.FONT_SMALL) : AppFont.get(Graphics.FONT_TINY),
                isRepMode()
                    ? Lang.format("target $1$ swings", [TrainingMode.targetLabel(_repTarget)])
                    : Lang.format("$1$ bpm | $2$", [metronome.getBpm(), patternLabel(preset)]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * (isFreeTraining ? 55 : 62) / 100,
                isFreeTraining ? AppFont.get(Graphics.FONT_SMALL) : AppFont.get(Graphics.FONT_TINY),
                "SELECT to start",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * (isFreeTraining ? 70 : 75) / 100,
                AppFont.get(Graphics.FONT_TINY),
                "MENU opens settings",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            // Last comparable session's smoothness (with trend), so the score
            // is glanceable before starting. Blank until there's history for
            // the selected implement/movement/side; sits clear of the lines
            // above on both the interval and free-training idle layouts.
            var lastSmooth = smoothnessText(false);
            if (!lastSmooth.equals("")) {
                dc.drawText(
                    cx,
                    h * 88 / 100,
                    AppFont.get(Graphics.FONT_TINY),
                    lastSmooth,
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
        // With the swing counter running, detected swings replace metronome
        // rounds everywhere rounds would show: the count is the real reps.
        var counting = workout.isSwingCounting();
        var setSwings = counting ? workout.getCurrentSetSwings().toString() : metronome.getRounds().toString();
        var setSwingsLabel = counting ? "swng" : "rnds";
        var totalSwings = workout.getTotalSwings().toString();
        // The subwindow circle - the watch's literal top-right corner - always
        // shows the live, per-set count once counting is running, so it reads
        // zero right after every rest -> resume instead of a stale session
        // total; heart rate takes the corner the rest of the time.
        var circleValue = counting ? setSwings : (_circleRounds ? setSwings : hr);
        var otherValue = counting ? hr : (_circleRounds ? hr : setSwings);
        var otherLabel = counting ? "hr" : (_circleRounds ? "hr" : setSwingsLabel);
        // BPM is a fixed setting for the whole activity, rarely worth a slot
        // once swing counting is running - the session total takes its place.
        var bpmSlotValue = counting ? totalSwings : metronome.getBpm().toString();
        var bpmSlotLabel = counting ? "total" : "bpm";

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
                    AppFont.get(Graphics.FONT_TINY),
                    formatSecs(timerMs / 1000),
                    Graphics.TEXT_JUSTIFY_LEFT
                );
                drawSubwindowMetric(dc, circleValue);
            } else {
                dc.drawText(
                    cx,
                    h * 6 / 100,
                    AppFont.get(Graphics.FONT_TINY),
                    formatSecs(timerMs / 1000),
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
            dc.drawText(
                cx,
                h * 30 / 100,
                AppFont.get(Graphics.FONT_SMALL),
                Lang.format(
                    "SET $1$/$2$  $3$",
                    [s[:set], p.getSets(), phase == Intervals.PHASE_REST ? "REST" : "WORK"]
                ),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 40 / 100,
                AppFont.get(Graphics.FONT_NUMBER_HOT),
                formatSecs(s[:remaining] as Number),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            if (_subwindow) {
                dc.drawText(
                    cx - 35,
                    h * 72 / 100,
                    AppFont.get(Graphics.FONT_MEDIUM),
                    bpmSlotValue,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    cx - 35,
                    h * 87 / 100,
                    AppFont.get(Graphics.FONT_TINY),
                    bpmSlotLabel,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    cx + 35,
                    h * 72 / 100,
                    AppFont.get(Graphics.FONT_MEDIUM),
                    otherValue,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    cx + 35,
                    h * 87 / 100,
                    AppFont.get(Graphics.FONT_TINY),
                    otherLabel,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            } else {
                dc.drawText(
                    cx - 50,
                    h * 72 / 100,
                    AppFont.get(Graphics.FONT_MEDIUM),
                    bpmSlotValue,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    cx - 50,
                    h * 87 / 100,
                    AppFont.get(Graphics.FONT_TINY),
                    bpmSlotLabel,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    cx,
                    h * 72 / 100,
                    AppFont.get(Graphics.FONT_MEDIUM),
                    setSwings,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    cx,
                    h * 87 / 100,
                    AppFont.get(Graphics.FONT_TINY),
                    setSwingsLabel,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    cx + 50,
                    h * 72 / 100,
                    AppFont.get(Graphics.FONT_MEDIUM),
                    hr,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    cx + 50,
                    h * 87 / 100,
                    AppFont.get(Graphics.FONT_TINY),
                    "hr",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
            return;
        }

        // Free training: elapsed time front and center, with SELECT advancing
        // between WORK and REST while FIT recording continues. Unlike
        // Interval, there is no fixed duration to plan around, so both the
        // whole-session clock (row 1, unchanged position/format across every
        // mode) and a live this-phase clock (row 2) are always on screen -
        // "how long have I been resting" was previously unanswerable here.
        var freeResting = freePhase == FreeTraining.PHASE_REST;
        var phaseText = freeResting ? "REST" : "WORK";
        var phaseElapsed = formatSecs(freePhaseElapsedSeconds());
        // Resting already shows the rest countdown as the main value below,
        // so row 2 would otherwise repeat that same number - swap in the
        // wall clock there instead, which is otherwise only reachable by
        // paging (see restPageActive/_restPage == 1 below).
        var phaseLine = Lang.format("$1$  $2$", [phaseText, freeResting ? clockTimeLabel() : phaseElapsed]);
        var mainValue = freeResting ? phaseElapsed : bpmSlotValue;
        var mainLabel = freeResting ? "SELECT: work" : bpmSlotLabel;
        if (isRepMode()) {
            mainValue = freeResting ? phaseElapsed : workout.getCurrentSetSwings().toString();
            mainLabel = freeResting
                ? "SELECT: next set"
                : (_repTarget > 0 ? Lang.format("swings / $1$", [_repTarget]) : "swings");
        }
        // Working a combo, the glanceable value is the current hand and
        // movement (e.g. "L REV MILL"), not the tempo.
        var comboWorking = !isRepMode() && !freeResting && workout.getMovementType() == Movement.TYPE_COMBO;
        if (comboWorking) {
            mainValue = Combo.statusLabel(metronome.getBeatCount(), Combo.beats());
            mainLabel = Lang.format("$1$ bpm", [metronome.getBpm()]);
        }
        // Rest is otherwise idle for UP/DOWN (tempo doesn't matter with the
        // metronome stopped), so it repurposes those buttons to page through
        // extra info; row 2 and the main value swap content per page while
        // the elapsed clock, the SELECT hint, and the sets/rounds/hr row
        // underneath all stay put so the athlete never loses their place.
        var restPageActive = freeResting && _restPage != 0 && workout.getSets() > 0;
        if (restPageActive) {
            var lastIndex = workout.getSets() - 1;
            if (_restPage == 1) {
                phaseLine = clockTimeLabel();
                mainValue = SummaryText.swings(workout, lastIndex);
                if (mainValue.equals("")) {
                    mainValue = "-- sw";
                }
            } else {
                phaseLine = SummaryText.smoothness(workout, lastIndex);
                if (phaseLine.equals("")) {
                    phaseLine = "smooth --";
                }
                mainValue = SummaryText.load(workout, lastIndex);
                if (mainValue.equals("")) {
                    mainValue = "load --";
                }
            }
            mainLabel = "SELECT: work";
        }
        if (_subwindow) {
            drawSubwindowMetric(dc, circleValue);
            // Like the interval screen, the header sits left of the
            // subwindow cut-out; centered it loses its middle characters
            // to the circle. Row 2 stays in the same left column - the
            // cut-out only occupies the upper-right quadrant, so a narrow
            // left-justified line clears it at any height. The main value
            // starts below the cut-out (y > 62 on the 45mm) and its label
            // clears the medium font's 27px height - the old 48%/58% stack
            // drew them overlapping.
            dc.drawText(
                w * 10 / 100,
                h * 8 / 100,
                AppFont.get(Graphics.FONT_TINY),
                formatSecs(timerMs / 1000),
                Graphics.TEXT_JUSTIFY_LEFT
            );
            dc.drawText(
                w * 10 / 100,
                h * 20 / 100,
                AppFont.get(Graphics.FONT_TINY),
                phaseLine,
                Graphics.TEXT_JUSTIFY_LEFT
            );
            dc.drawText(
                cx,
                h * 36 / 100,
                AppFont.get(Graphics.FONT_MEDIUM),
                mainValue,
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 52 / 100,
                AppFont.get(Graphics.FONT_TINY),
                mainLabel,
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx - 30,
                h * 70 / 100,
                AppFont.get(Graphics.FONT_MEDIUM),
                workout.getSets().toString(),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx - 30,
                h * 84 / 100,
                AppFont.get(Graphics.FONT_TINY),
                "sets",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx + 30,
                h * 70 / 100,
                AppFont.get(Graphics.FONT_MEDIUM),
                otherValue,
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx + 30,
                h * 84 / 100,
                AppFont.get(Graphics.FONT_TINY),
                otherLabel,
                Graphics.TEXT_JUSTIFY_CENTER
            );
            return;
        }
        dc.drawText(
            cx,
            h * 6 / 100,
            AppFont.get(Graphics.FONT_TINY),
            formatSecs(timerMs / 1000),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            cx,
            h * 18 / 100,
            AppFont.get(Graphics.FONT_SMALL),
            phaseLine,
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            cx,
            h * 32 / 100,
            // Number fonts are digit-sized; combo text and rest-page labels
            // (e.g. "42 sw") need a text face.
            comboWorking || restPageActive
                ? AppFont.get(Graphics.FONT_LARGE)
                : AppFont.get(Graphics.FONT_NUMBER_HOT),
            mainValue,
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(cx, h * 56 / 100, AppFont.get(Graphics.FONT_TINY), mainLabel, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(
            cx - 50,
            h * 68 / 100,
            AppFont.get(Graphics.FONT_MEDIUM),
            workout.getSets().toString(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            cx - 50,
            h * 84 / 100,
            AppFont.get(Graphics.FONT_TINY),
            "sets",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            cx,
            h * 68 / 100,
            AppFont.get(Graphics.FONT_MEDIUM),
            setSwings,
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            cx,
            h * 84 / 100,
            AppFont.get(Graphics.FONT_TINY),
            setSwingsLabel,
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(cx + 50, h * 68 / 100, AppFont.get(Graphics.FONT_MEDIUM), hr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx + 50, h * 84 / 100, AppFont.get(Graphics.FONT_TINY), "hr", Graphics.TEXT_JUSTIFY_CENTER);
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
        var fonts = [
            AppFont.get(Graphics.FONT_LARGE),
            AppFont.get(Graphics.FONT_MEDIUM),
            AppFont.get(Graphics.FONT_SMALL),
            AppFont.get(Graphics.FONT_TINY)
        ] as Array<Graphics.FontDefinition>;
        var font = AppFont.get(Graphics.FONT_TINY);
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
