import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// One saved session, beginning with a compact workout overview. DOWN opens the
// first set and UP/DOWN then wrap through every set and back to the overview.
// Legacy smoothness-only records keep their original per-set presentation.
class HistoryDetailView extends WatchUi.View {
    private var _rec as Array<Storage.ValueType>;
    private var _count as Number;
    private var _index as Number = -1;

    function initialize(rec as Array<Storage.ValueType>) {
        View.initialize();
        _rec = rec;
        _count = SmoothnessLog.hasDetails(rec)
            ? SmoothnessLog.blockCountOf(rec)
            : SmoothnessLog.setCountOf(rec);
    }

    function scroll(direction as Number) as Void {
        if (_count == 0) {
            return;
        }
        var pages = _count + 1;
        _index = (_index + 1 + direction + pages) % pages - 1;
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
            AppFont.get(Graphics.FONT_TINY),
            HistoryMenu.stamp(SmoothnessLog.epochOf(_rec)),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(cx, h * 22 / 100, AppFont.get(Graphics.FONT_TINY), equipment, Graphics.TEXT_JUSTIFY_CENTER);

        var movement = Lang.format(
            "$1$ | $2$",
            [Movement.typeLabel(SmoothnessLog.moveOf(_rec)), Movement.sideLabel(SmoothnessLog.sideOf(_rec))]
        );
        dc.drawText(cx, h * 31 / 100, AppFont.get(Graphics.FONT_XTINY), movement, Graphics.TEXT_JUSTIFY_CENTER);

        if (_index < 0) {
            drawOverview(dc, cx, h);
        } else {
            drawSet(dc, cx, h);
        }
    }

    private function drawOverview(dc as Dc, cx as Number, h as Number) as Void {
        var score = SmoothnessLog.scoreOf(_rec);
        dc.drawText(
            cx,
            h * 43 / 100,
            AppFont.get(Graphics.FONT_SMALL),
            score < 0 ? "smooth --" : Lang.format("smooth $1$", [score]),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        if (SmoothnessLog.hasDetails(_rec)) {
            dc.drawText(
                cx,
                h * 58 / 100,
                AppFont.get(Graphics.FONT_TINY),
                Lang.format("$1$ sets | $2$ work", [_count, formatSecs(SmoothnessLog.totalWorkOf(_rec))]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 69 / 100,
                AppFont.get(Graphics.FONT_TINY),
                Lang.format("$1$ rest", [formatSecs(SmoothnessLog.totalRestOf(_rec))]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
        } else {
            dc.drawText(
                cx,
                h * 62 / 100,
                AppFont.get(Graphics.FONT_TINY),
                Lang.format("$1$ saved sets", [_count]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
        dc.drawText(
            cx,
            h * 86 / 100,
            AppFont.get(Graphics.FONT_XTINY),
            _count > 0 ? "DOWN: set details" : "BACK: exit",
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    private function drawSet(dc as Dc, cx as Number, h as Number) as Void {
        var score = SmoothnessLog.setScoreOf(_rec, _index);
        dc.drawText(
            cx,
            h * 41 / 100,
            AppFont.get(Graphics.FONT_TINY),
            Lang.format(
                "SET $1$/$2$ | $3$",
                [_index + 1, _count, Movement.sideLabel(SmoothnessLog.blockSideOf(_rec, _index))]
            ),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            cx,
            h * 53 / 100,
            AppFont.get(Graphics.FONT_TINY),
            Lang.format(
                "W$1$  R$2$",
                [
                    formatSecs(SmoothnessLog.blockWorkOf(_rec, _index)),
                    formatSecs(SmoothnessLog.blockRestOf(_rec, _index))
                ]
            ),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            cx,
            h * 65 / 100,
            AppFont.get(Graphics.FONT_TINY),
            score < 0 ? "smooth --" : Lang.format("smooth $1$", [score]),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        var swings = SmoothnessLog.blockSwingsOf(_rec, _index);
        var exposure = SmoothnessLog.blockExposureOf(_rec, _index);
        var load = swings < 0 ? "sw --" : Lang.format("$1$ sw", [swings]);
        if (exposure >= 0) {
            load = Lang.format("$1$ | L$2$", [load, LoadExposure.compactLabel(exposure)]);
        }
        dc.drawText(cx, h * 76 / 100, AppFont.get(Graphics.FONT_XTINY), load, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(
            cx,
            h * 88 / 100,
            AppFont.get(Graphics.FONT_XTINY),
            "UP/DOWN: pages",
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    private function formatSecs(total as Number) as String {
        return Lang.format("$1$:$2$", [total / 60, (total % 60).format("%02d")]);
    }

    // -1 marks a set (or session) without enough motion to score.
}
