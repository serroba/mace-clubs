import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class MaceClubsView extends WatchUi.View {

    var metronome as Metronome;

    function initialize() {
        View.initialize();
        metronome = new Metronome();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();

        dc.drawText(cx, h * 20 / 100, Graphics.FONT_SMALL, "MACE & CLUBS",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 38 / 100, Graphics.FONT_NUMBER_HOT,
            metronome.getBpm().toString(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 62 / 100, Graphics.FONT_TINY, "bpm  (UP/DOWN)",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 76 / 100, Graphics.FONT_SMALL,
            metronome.isRunning() ? "SELECT to stop" : "SELECT to start",
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}
