import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Shown once the session is saved, in place of exiting immediately. Pages
// through a handful of aggregate screens, then one page per completed set
// (the same detail line the pre-save paused/done browse already used).
class WorkoutSummaryView extends WatchUi.View {
    const FIXED_PAGES = 4;

    private var _workout as WorkoutSession;
    private var _page as Number = 0;
    private var _subwindow as Boolean = false;

    function initialize(workout as WorkoutSession) {
        View.initialize();
        _workout = workout;
        if (System has :SCREEN_SHAPE_SEMI_OCTAGON) {
            _subwindow = System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_SEMI_OCTAGON;
        }
    }

    function totalPages() as Number {
        var sets = _workout.getSets();
        return FIXED_PAGES + (sets > 0 ? sets : 0);
    }

    function cyclePage(direction as Number) as Void {
        var count = totalPages();
        _page = (_page + direction + count) % count;
    }

    private function formatSecs(total as Number) as String {
        return Lang.format("$1$:$2$", [total / 60, (total % 60).format("%02d")]);
    }

    // Weight-volume and load exposure are only tracked per set today, so the
    // session-wide figures are summed here rather than in WorkoutSession.
    private function totalWeightVolume() as Number {
        var total = 0;
        for (var i = 0; i < _workout.getSets(); i++) {
            var block = _workout.getBlock(i);
            if (block != null) {
                total += (block as WorkBlockSummary).getWeightVolume();
            }
        }
        return total;
    }

    private function totalMotionExposure() as Number {
        var total = 0;
        for (var i = 0; i < _workout.getSets(); i++) {
            var block = _workout.getBlock(i);
            if (block != null) {
                var exposure = (block as WorkBlockSummary).getMotionExposure();
                if (exposure > 0) {
                    total += exposure;
                }
            }
        }
        return total;
    }

    private function overviewLines() as Array<String> {
        var sets = _workout.getSets();
        var line1 = Lang.format("$1$ sets  $2$ work", [sets, formatSecs(_workout.getTotalWorkSeconds())]);
        var line2 = Lang.format(
            "$1$  $2$",
            [_workout.getEquipmentLabel(), Movement.typeLabel(_workout.getMovementType())]
        );
        var swings = _workout.getTotalSwings();
        var line3 = swings > 0 ? Lang.format("$1$ swings", [swings]) : "";
        return ["SUMMARY", line1, line2, line3];
    }

    private function smoothnessLines() as Array<String> {
        var smooth = SummaryText.sessionSmoothness(_workout);
        // .equals(), not ==: Monkey C's == on Strings is reference equality.
        var line1 = smooth.equals("") ? "not enough motion" : smooth;
        var windows = _workout.getSmoothnessWindows();
        var line2 = windows > 0 ? Lang.format("$1$s of motion", [windows]) : "";
        // Kept as short as "PAUSED"/"DONE!" so the subwindow layout's shifted
        // heading (see onUpdate) never runs into the physical cut-out.
        return ["SMOOTH", line1, line2, ""];
    }

    private function swingsAndLoadLines() as Array<String> {
        var line1 = Lang.format("$1$ swings", [_workout.getTotalSwings()]);
        var volume = totalWeightVolume();
        var line2 = volume > 0 ? Lang.format("$1$ kg volume", [volume]) : "";
        var exposure = totalMotionExposure();
        var line3 = exposure > 0 ? Lang.format("$1$ total load", [LoadExposure.compactLabel(exposure)]) : "";
        return ["LOAD", line1, line2, line3];
    }

    private function balanceLines() as Array<String> {
        var counts = _workout.getSideSetCounts();
        var balance = Movement.balanceLabel(counts[0], counts[1]);
        var line1 = balance.equals("") ? "n/a" : balance;
        var line2 = Lang.format("$1$ left  $2$ right", [counts[0], counts[1]]);
        return ["BALANCE", line1, line2, ""];
    }

    private function setLines(index as Number) as Array<String> {
        var heading = Lang.format("SET $1$/$2$", [index + 1, _workout.getSets()]);
        var line1 = Lang.format(
            "$1$ W$2$ R$3$",
            [
                SummaryText.side(_workout, index),
                formatSecs(_workout.getSetWorkSeconds(index)),
                formatSecs(_workout.getSetRestSeconds(index))
            ]
        );
        var line2 = SummaryText.detail(_workout, index);
        return [heading, line1, line2, ""];
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var cx = w / 2;
        var h = dc.getHeight();
        // The subwindow cut-out only reaches the top-right quadrant; shifting
        // just the heading left mirrors the paused screen's fix for the same
        // problem.
        var headingX = _subwindow ? w * 32 / 100 : cx;

        var lines = currentLines();

        dc.drawText(
            headingX,
            h * 18 / 100,
            AppFont.get(Graphics.FONT_MEDIUM),
            lines[0],
            Graphics.TEXT_JUSTIFY_CENTER
        );
        if (!lines[1].equals("")) {
            dc.drawText(
                cx,
                h * 38 / 100,
                AppFont.get(Graphics.FONT_SMALL),
                lines[1],
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
        if (!lines[2].equals("")) {
            dc.drawText(
                cx,
                h * 50 / 100,
                AppFont.get(Graphics.FONT_TINY),
                lines[2],
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
        if (!lines[3].equals("")) {
            dc.drawText(
                cx,
                h * 61 / 100,
                AppFont.get(Graphics.FONT_TINY),
                lines[3],
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
        dc.drawText(
            cx,
            h * 79 / 100,
            AppFont.get(Graphics.FONT_XTINY),
            Lang.format("UP/DOWN $1$/$2$", [_page + 1, totalPages()]),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            cx,
            h * 89 / 100,
            AppFont.get(Graphics.FONT_XTINY),
            "BACK exit",
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    // [heading, line1, line2, line3] for the current page; exposed (not just
    // used from onUpdate) so tests can assert on content, not just that
    // rendering doesn't crash.
    function currentLines() as Array<String> {
        return _page < FIXED_PAGES ? fixedPageLines(_page) : setLines(_page - FIXED_PAGES);
    }

    private function fixedPageLines(page as Number) as Array<String> {
        if (page == 0) {
            return overviewLines();
        }
        if (page == 1) {
            return smoothnessLines();
        }
        if (page == 2) {
            return swingsAndLoadLines();
        }
        return balanceLines();
    }
}
