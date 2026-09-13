import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// One saved session, beginning with a compact workout overview. DOWN opens the
// first set and UP/DOWN then wrap through every set and back to the overview.
// Legacy smoothness-only records keep their original per-set presentation.
(:history)
class HistoryDetailView extends WatchUi.View {
    private var _rec as Array<Storage.ValueType>;
    private var _count as Number;
    private var _index as Number = -1;
    private var _subwindow as Boolean = false;

    function initialize(rec as Array<Storage.ValueType>) {
        View.initialize();
        _rec = rec;
        _count = SmoothnessLog.hasDetails(rec)
            ? SmoothnessLog.blockCountOf(rec)
            : SmoothnessLog.setCountOf(rec);
        if (System has :SCREEN_SHAPE_SEMI_OCTAGON) {
            _subwindow = System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_SEMI_OCTAGON;
        }
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
        var w = dc.getWidth();
        var cx = w / 2;
        var h = dc.getHeight();
        // The stamp and the equipment label sit wholly inside the subwindow's
        // band - the cut-out is 62px tall and these two are drawn at h*12 and
        // h*22 - so centred on the screen they ran underneath it. Centred in
        // the clear area beside it instead, the way the paused and summary
        // screens already place their headings.
        //
        // The movement line joins them, but only once it is short enough to.
        // Spelled out - "Mill | Two-handed" - it is wider than the clear area
        // at the smallest face there is, and centring that in a 113px box does
        // not tuck it beside the cut-out, it pushes its left end off the
        // screen. Measured, after trying it. The compact side tag the per-set
        // lines already use takes it to "Mill | Both", which fits with room to
        // spare.
        //
        // Moving it down instead, below the cut-out, was the other way out and
        // is worse: drawSet shares this header and starts at h*41, so the line
        // would land on top of it, and pushing the set pages down in turn runs
        // their last line into the paging hint. One string got shorter; five
        // positions did not have to move.
        var headerWidth = _subwindow ? Layout.clearWidthBesideSubwindow(w) : w;
        var headerX = headerWidth / 2;
        var equipment = Equipment.labelFor(
            SmoothnessLog.eqTypeOf(_rec),
            SmoothnessLog.eqCountOf(_rec),
            SmoothnessLog.weightOf(_rec)
        );
        dc.drawText(
            headerX,
            h * 12 / 100,
            Graphics.FONT_TINY,
            HistoryMenu.stamp(SmoothnessLog.epochOf(_rec)),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        // The equipment label is the one header line whose length varies:
        // "Mace: 8.8 lb" fits the clear area beside the cut-out and
        // "Clubs: 2 x 8.8 lb" does not, and centred in a narrower box a line
        // that does not fit runs off the left edge instead of under the ring.
        // Stepping down one face is what makes the move safe for both.
        // FONT_TINY leads the list, so every screen that fits today is
        // untouched.
        var equipmentFont = Layout.fitFont(
            dc,
            equipment,
            [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            headerWidth,
            h
        );
        dc.drawText(headerX, h * 22 / 100, equipmentFont, equipment, Graphics.TEXT_JUSTIFY_CENTER);

        // The side tag goes only where there is room for it. "Mill | Both"
        // fits the clear area beside the cut-out and "Flow / other | Both"
        // does not - three of the eight movement names are long enough to
        // push it past, and Flow / other is the one both validated recordings
        // in this repo actually used, so the likeliest case was the failing
        // one. Measured rather than guessed at: the first pass of this sized
        // the strings by character count and got two of the three wrong.
        //
        // Dropping the tag rather than clipping it loses nothing from the
        // screen. Every set page draws the side in full a press away, which
        // is also where it varies - the overview's is the session's, and a
        // session that switched hands has it per set anyway.
        var movementName = Movement.typeLabel(SmoothnessLog.moveOf(_rec));
        var movement = Lang.format(
            "$1$ | $2$",
            [movementName, Movement.sideShortLabel(SmoothnessLog.sideOf(_rec))]
        );
        if (dc.getTextDimensions(movement, Graphics.FONT_XTINY)[0] > headerWidth) {
            movement = movementName;
        }
        dc.drawText(headerX, h * 31 / 100, Graphics.FONT_XTINY, movement, Graphics.TEXT_JUSTIFY_CENTER);

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
            Graphics.FONT_SMALL,
            score < 0 ? "rhythm --" : Lang.format("rhythm $1$", [score]),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        if (SmoothnessLog.hasDetails(_rec)) {
            dc.drawText(
                cx,
                h * 58 / 100,
                Graphics.FONT_TINY,
                Lang.format("$1$ sets | $2$ work", [_count, formatSecs(SmoothnessLog.totalWorkOf(_rec))]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                cx,
                h * 69 / 100,
                Graphics.FONT_TINY,
                Lang.format("$1$ rest", [formatSecs(SmoothnessLog.totalRestOf(_rec))]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
        } else {
            dc.drawText(
                cx,
                h * 62 / 100,
                Graphics.FONT_TINY,
                Lang.format("$1$ saved sets", [_count]),
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
        dc.drawText(
            cx,
            h * 86 / 100,
            Graphics.FONT_XTINY,
            _count > 0 ? "DOWN: set details" : "BACK: exit",
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    private function drawSet(dc as Dc, cx as Number, h as Number) as Void {
        var score = SmoothnessLog.setScoreOf(_rec, _index);
        dc.drawText(
            cx,
            h * 41 / 100,
            Graphics.FONT_TINY,
            Lang.format(
                "SET $1$/$2$ | $3$",
                [_index + 1, _count, Movement.sideLabel(SmoothnessLog.blockSideOf(_rec, _index))]
            ),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            cx,
            h * 53 / 100,
            Graphics.FONT_TINY,
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
            Graphics.FONT_TINY,
            score < 0 ? "rhythm --" : Lang.format("rhythm $1$", [score]),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        var swings = SmoothnessLog.blockSwingsOf(_rec, _index);
        var exposure = SmoothnessLog.blockExposureOf(_rec, _index);
        var load = swings < 0 ? "sw --" : Lang.format("$1$ sw", [swings]);
        if (exposure >= 0) {
            load = Lang.format("$1$ | L$2$", [load, LoadExposure.compactLabel(exposure)]);
        }
        dc.drawText(cx, h * 76 / 100, Graphics.FONT_XTINY, load, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(
            cx,
            h * 88 / 100,
            Graphics.FONT_XTINY,
            Lang.format("$1$: pages", [DeviceInput.pageLabel()]),
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    private function formatSecs(total as Number) as String {
        return Lang.format("$1$:$2$", [total / 60, (total % 60).format("%02d")]);
    }

    // -1 marks a set (or session) without enough motion to score.
}
