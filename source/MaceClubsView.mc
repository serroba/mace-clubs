import Toybox.Activity;
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
    var metronome as Metronome;
    var workout as WorkoutSession;
    var paused as Boolean = false;
    var done as Boolean = false;
    var presetIndex as Number = 0;
    var plan as Intervals.Plan?;

    private var _refreshTimer as Timer.Timer;
    private var _lastPhase as Number?;
    private var _lastSet as Number = 0;
    private var _icon as WatchUi.BitmapResource;
    private var _subwindow as Boolean = false;

    function initialize() {
        View.initialize();
        metronome = new Metronome();
        workout = new WorkoutSession();
        _refreshTimer = new Timer.Timer();
        _icon = WatchUi.loadResource(Rez.Drawables.LauncherIcon) as WatchUi.BitmapResource;
        if (System has :SCREEN_SHAPE_SEMI_OCTAGON) {
            _subwindow = System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_SEMI_OCTAGON;
        }
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

    function cyclePreset(dir as Number) as Void {
        var n = Presets.count();
        presetIndex = (presetIndex + dir + n) % n;
    }

    // Start recording with the currently selected preset. Presets with
    // :sets == 0 are free training (no interval plan).
    function startWorkout() as Void {
        var preset = selectedPreset();
        var sets = preset[:sets] as Number;
        if (sets > 0) {
            plan = new Intervals.Plan(sets, preset[:work] as Number, preset[:rest] as Number);
        } else {
            plan = null;
        }
        done = false;
        _lastPhase = null;
        workout.start();
        metronome.start();
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
        var oldPhase = _lastPhase;
        var oldSet = _lastSet;
        _lastPhase = phase;
        _lastSet = set;
        if (oldPhase == null || phase == oldPhase && set == oldSet) {
            return;
        }
        onPlanTransition(oldPhase as Number, phase);
    }

    private function onPlanTransition(oldPhase as Number, phase as Number) as Void {
        if (phase == Intervals.PHASE_DONE) {
            workout.addSet();
            metronome.stop();
            playTransitionCue(true);
            workout.pause();
            paused = true;
            done = true;
        } else if (phase == Intervals.PHASE_REST) {
            workout.addSet();
            metronome.stop();
            playTransitionCue(false);
        } else {
            // WORK begins; WORK -> WORK is a set rollover on zero-rest plans
            if (oldPhase == Intervals.PHASE_WORK) {
                workout.addSet();
            }
            metronome.start();
            playTransitionCue(false);
        }
    }

    private function playTransitionCue(finished as Boolean) as Void {
        if (Attention has :playTone) {
            Attention.playTone(finished ? Attention.TONE_SUCCESS : Attention.TONE_INTERVAL_ALERT);
        }
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, 400)]);
        }
    }

    private function formatSecs(total as Number) as String {
        return Lang.format("$1$:$2$", [total / 60, (total % 60).format("%02d")]);
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var cx = w / 2;
        var h = dc.getHeight();

        if (paused) {
            dc.drawText(
                cx,
                h * 38 / 100,
                Graphics.FONT_MEDIUM,
                done ? "DONE!" : "PAUSED",
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(cx, h * 56 / 100, Graphics.FONT_SMALL, "SELECT: save", Graphics.TEXT_JUSTIFY_CENTER);
            if (!done) {
                dc.drawText(
                    cx,
                    h * 71 / 100,
                    Graphics.FONT_SMALL,
                    "BACK: resume",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
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
            var isCustom = selectedPreset()[:custom] as Boolean?;
            var hint = isCustom != null ? "custom - edit on phone" : "UP/DOWN: workout";
            dc.drawText(cx, h * 54 / 100, Graphics.FONT_TINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(
                cx,
                h * 66 / 100,
                Graphics.FONT_TINY,
                Lang.format("$1$ bpm", [metronome.getBpm()]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(cx, h * 78 / 100, Graphics.FONT_SMALL, "SELECT to start", Graphics.TEXT_JUSTIFY_CENTER);
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
                drawSubwindowHr(dc, hr);
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
                    cx,
                    h * 72 / 100,
                    Graphics.FONT_MEDIUM,
                    metronome.getBpm().toString(),
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(cx, h * 87 / 100, Graphics.FONT_TINY, "bpm", Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                dc.drawText(
                    cx - 35,
                    h * 72 / 100,
                    Graphics.FONT_MEDIUM,
                    metronome.getBpm().toString(),
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(cx - 35, h * 87 / 100, Graphics.FONT_TINY, "bpm", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(cx + 35, h * 72 / 100, Graphics.FONT_MEDIUM, hr, Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(cx + 35, h * 87 / 100, Graphics.FONT_TINY, "hr", Graphics.TEXT_JUSTIFY_CENTER);
            }
            return;
        }

        // Free training: elapsed time front and center, tempo and manual
        // set counter below; HR in the subwindow where the screen has one
        if (_subwindow) {
            drawSubwindowHr(dc, hr);
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
                cx,
                h * 64 / 100,
                Graphics.FONT_MEDIUM,
                workout.getSets().toString(),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(cx, h * 80 / 100, Graphics.FONT_TINY, "sets", Graphics.TEXT_JUSTIFY_CENTER);
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
            cx - 30,
            h * 68 / 100,
            Graphics.FONT_MEDIUM,
            workout.getSets().toString(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(cx - 30, h * 84 / 100, Graphics.FONT_TINY, "sets", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx + 30, h * 68 / 100, Graphics.FONT_MEDIUM, hr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx + 30, h * 84 / 100, Graphics.FONT_TINY, "hr", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Draw the heart rate inside the Instinct's circular subwindow.
    // getSubscreen gives exact bounds on CIQ 4.2+; older Instincts fall
    // back to the family's typical top-right placement.
    private function drawSubwindowHr(dc as Dc, hr as String) as Void {
        var sx = dc.getWidth() * 82 / 100;
        var sy = dc.getHeight() * 17 / 100;
        if (WatchUi has :getSubscreen) {
            var sub = WatchUi.getSubscreen();
            if (sub != null) {
                sx = (sub.x as Number) + (sub.width as Number) / 2;
                sy = (sub.y as Number) + (sub.height as Number) / 2;
            }
        }
        dc.drawText(
            sx,
            sy,
            Graphics.FONT_SMALL,
            hr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}
