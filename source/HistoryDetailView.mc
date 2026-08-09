import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// One saved session's smoothness, mirroring the end-of-workout summary screen:
// UP/DOWN scroll through the per-set scores, with the session average and the
// implement shown for context. Sessions with a score but no per-set breakdown
// (e.g. a single continuous challenge block) fall back to the average alone.
class HistoryDetailView extends WatchUi.View {
    private var _rec as Array<Storage.ValueType>;
    private var _count as Number;
    private var _index as Number = 0;

    function initialize(rec as Array<Storage.ValueType>) {
        View.initialize();
        _rec = rec;
        _count = SmoothnessLog.setCountOf(rec);
    }

    function scroll(direction as Number) as Void {
        if (_count <= 1) {
            return;
        }
        _index = (_index + direction + _count) % _count;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();
        var equipment = Equipment.labelFor(
            SmoothnessLog.eqTypeOf(_rec),
            SmoothnessLog.eqCountOf(_rec),
            SmoothnessLog.weightOf(_rec)
        );
        dc.drawText(
            cx,
            h * 12 / 100,
            Graphics.FONT_TINY,
            HistoryMenu.stamp(SmoothnessLog.epochOf(_rec)),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(cx, h * 22 / 100, Graphics.FONT_TINY, equipment, Graphics.TEXT_JUSTIFY_CENTER);

        if (_count == 0) {
            dc.drawText(
                cx,
                h * 45 / 100,
                Graphics.FONT_NUMBER_MEDIUM,
                scoreText(SmoothnessLog.scoreOf(_rec)),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(cx, h * 67 / 100, Graphics.FONT_TINY, "session avg", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(
                cx,
                h * 42 / 100,
                Graphics.FONT_NUMBER_MEDIUM,
                scoreText(SmoothnessLog.setScoreOf(_rec, _index)),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 63 / 100,
                Graphics.FONT_TINY,
                Lang.format("set $1$/$2$", [_index + 1, _count]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 72 / 100,
                Graphics.FONT_TINY,
                Lang.format("avg $1$", [SmoothnessLog.scoreOf(_rec)]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }

        dc.drawText(
            cx,
            h * 86 / 100,
            Graphics.FONT_TINY,
            _count > 1 ? "UP/DOWN: sets" : "BACK: exit",
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    // -1 marks a set (or session) without enough motion to score.
    private function scoreText(score as Number) as String {
        return score < 0 ? "--" : score.toString();
    }
}
