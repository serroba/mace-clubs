import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Layout note: the Instinct 3 Solar has a physical subwindow cut-out in
// the top-right corner (x >= 114, y <= 62 on the 45mm per personality.mss).
// Pixels drawn there are not visible, so top-of-screen text is kept
// left-aligned or pushed below it.
class MaceClubsView extends WatchUi.View {

    var metronome as Metronome;
    var workout as WorkoutSession;
    var paused as Boolean = false;

    private var _refreshTimer as Timer.Timer;

    function initialize() {
        View.initialize();
        metronome = new Metronome();
        workout = new WorkoutSession();
        _refreshTimer = new Timer.Timer();
    }

    function onShow() as Void {
        _refreshTimer.start(method(:onRefresh), 1000, true);
    }

    function onHide() as Void {
        _refreshTimer.stop();
    }

    function onRefresh() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var cx = w / 2;
        var h = dc.getHeight();

        if (paused) {
            dc.drawText(cx, h * 38 / 100, Graphics.FONT_MEDIUM, "PAUSED",
                Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, h * 56 / 100, Graphics.FONT_SMALL, "SELECT: save",
                Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, h * 71 / 100, Graphics.FONT_SMALL, "BACK: resume",
                Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        if (!workout.isStarted()) {
            dc.drawText(w * 5 / 100, h * 6 / 100, Graphics.FONT_XTINY, "MACE & CLUBS",
                Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(cx, h * 38 / 100, Graphics.FONT_NUMBER_HOT,
                metronome.getBpm().toString(), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, h * 62 / 100, Graphics.FONT_TINY, "bpm  (UP/DOWN)",
                Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, h * 76 / 100, Graphics.FONT_SMALL, "SELECT to start",
                Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var info = Activity.getActivityInfo();

        var elapsed = "0:00";
        if (info != null && info.timerTime != null) {
            var totalSec = (info.timerTime as Number) / 1000;
            elapsed = Lang.format("$1$:$2$",
                [totalSec / 60, (totalSec % 60).format("%02d")]);
        }
        dc.drawText(w * 5 / 100, h * 6 / 100, Graphics.FONT_MEDIUM, elapsed,
            Graphics.TEXT_JUSTIFY_LEFT);

        dc.drawText(cx, h * 32 / 100, Graphics.FONT_NUMBER_HOT,
            metronome.getBpm().toString(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 56 / 100, Graphics.FONT_TINY, "bpm",
            Graphics.TEXT_JUSTIFY_CENTER);

        var hr = "--";
        if (info != null && info.currentHeartRate != null) {
            hr = (info.currentHeartRate as Number).toString();
        }
        dc.drawText(cx - 30, h * 68 / 100, Graphics.FONT_MEDIUM,
            workout.getSets().toString(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx - 30, h * 84 / 100, Graphics.FONT_TINY, "sets",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx + 30, h * 68 / 100, Graphics.FONT_MEDIUM, hr,
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx + 30, h * 84 / 100, Graphics.FONT_TINY, "hr",
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}
