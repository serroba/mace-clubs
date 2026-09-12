import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Shown once the session is saved, in place of exiting immediately. Pages
// through a handful of aggregate screens, then one page per completed set
// (the same detail line the pre-save paused/done browse already used).
class WorkoutSummaryView extends WatchUi.View {
    // The aggregate pages, in order. Two of them are conditional: a session
    // has to have something to say before it costs a page.
    //
    // The balance page in particular. It reports left/right set counts, and a
    // two-handed session has none - a real 12-set club workout showed
    // "BALANCE / n/a / 0 left 0 right" as page 4 of 16, between the athlete
    // and the per-set pages, and it will read that way for every session they
    // ever record. A page that is always empty for a whole way of training is
    // worse than one page fewer.
    const PAGE_OVERVIEW = 0;
    const PAGE_SET_CHART = 1;
    const PAGE_RHYTHM = 2;
    const PAGE_LOAD = 3;
    const PAGE_BALANCE = 4;
    const PAGE_SET = 5;

    // The bars live between these, clear of the heading above and the paging
    // hint below.
    const CHART_TOP_PERCENT = 34;
    const CHART_BASE_PERCENT = 62;

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

    /** Swings recorded for a set, or -1 where nothing counted them. */
    (:setChart)
    private function setSwings(index as Number) as Number {
        var block = _workout.getBlock(index);
        return block == null ? -1 : (block as WorkBlockSummary).getSwings();
    }

    /** The highest per-set swing count, or 0 when none were counted. */
    (:setChart)
    private function peakSetSwings() as Number {
        var peak = 0;
        for (var i = 0; i < _workout.getSets(); i++) {
            var swings = setSwings(i);
            if (swings > peak) {
                peak = swings;
            }
        }
        return peak;
    }

    /**
     * Whether the per-set chart has anything to draw.
     *
     * Two sets at least - one bar is not a comparison - and a counted swing
     * somewhere, since a session with counting off would draw twelve bars of
     * nothing.
     *
     * Paired with a twin that is always false, because the chart is the first
     * thing to give way where the app will not otherwise fit. Measured on
     * instinct2: drawing it costs 1,864 bytes, taking the peak headroom on a
     * 96KB watch from 4,832 bytes to 2,968 - 39% of everything those watches
     * have left, for a picture of numbers already on the set pages. Those
     * five give it up, the way they give up history and the custom-workout
     * editor. See the jungles and tools/reduced-devices.ts.
    */
    (:setChart)
    private function hasSetChart() as Boolean {
        return _workout.getSets() >= 2 && peakSetSwings() > 0;
    }

    (:noSetChart)
    private function hasSetChart() as Boolean {
        return false;
    }

    /** Whether any set was worked on a named side. */
    private function hasBalance() as Boolean {
        var counts = _workout.getSideSetCounts();
        return counts[0] > 0 || counts[1] > 0;
    }

    private function aggregatePages() as Number {
        return 3 + (hasSetChart() ? 1 : 0) + (hasBalance() ? 1 : 0);
    }

    /** What sits at this page index, given which aggregates this session earned. */
    private function kindAt(page as Number) as Number {
        if (page == 0) {
            return PAGE_OVERVIEW;
        }
        var index = page;
        if (hasSetChart()) {
            if (index == 1) {
                return PAGE_SET_CHART;
            }
            index--;
        }
        if (index == 1) {
            return PAGE_RHYTHM;
        }
        if (index == 2) {
            return PAGE_LOAD;
        }
        if (index == 3 && hasBalance()) {
            return PAGE_BALANCE;
        }
        return PAGE_SET;
    }

    function totalPages() as Number {
        var sets = _workout.getSets();
        return aggregatePages() + (sets > 0 ? sets : 0);
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
        // "not enough swings", not "not enough motion": the score is the
        // evenness of the gaps between swings now, so what is missing when
        // there is no score is swings to time, not movement.
        var line1 = smooth.equals("") ? "not enough swings" : smooth;
        var windows = _workout.getSmoothnessWindows();
        // The count is gaps between swings, which is one fewer than the
        // swings it timed - said as swings because that is what the athlete
        // counted.
        var line2 = windows > 0 ? Lang.format("$1$ swings timed", [windows + 1]) : "";
        // Kept as short as "PAUSED"/"DONE!" so the subwindow layout's shifted
        // heading (see onUpdate) never runs into the physical cut-out.
        // "RHYTHM" is the same six characters "SMOOTH" was, so the fit holds.
        return ["RHYTHM", line1, line2, ""];
    }

    private function swingsAndLoadLines() as Array<String> {
        var line1 = Lang.format("$1$ swings", [_workout.getTotalSwings()]);
        var volume = totalWeightVolume();
        var line2 = volume > 0 ? Lang.format("$1$ kg volume", [volume]) : "";
        var exposure = totalMotionExposure();
        var line3 = exposure > 0 ? Lang.format("$1$ total load", [LoadExposure.compactLabel(exposure)]) : "";
        return ["LOAD", line1, line2, line3];
    }

    // No "n/a" fallback any more: Movement.balanceLabel returns an empty
    // string only when both counts are zero, and that session no longer gets
    // this page at all - see hasBalance(). The fallback and the page that
    // showed it were the same mistake.
    private function balanceLines() as Array<String> {
        var counts = _workout.getSideSetCounts();
        return [
            "BALANCE",
            Movement.balanceLabel(counts[0], counts[1]),
            Lang.format("$1$ left  $2$ right", [counts[0], counts[1]]),
            ""
        ];
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

    // The Instinct Crossover wears physical hands over its display, and they
    // rest across the middle of it - exactly where this screen puts the set
    // count, the work time and the equipment row. A full-window capture of
    // the simulator shows them lying over "0 sets  0 work"; the text is
    // drawn in the same white as the heading above it and is simply
    // covered. Where they sit depends on the time of day, so on some
    // afternoons the numbers a workout ends on are unreadable.
    //
    // Parking them for the duration of the summary is what the API is for.
    // They go back to telling the time when it closes - leaving them parked
    // would be worse than the problem, since this is still a watch.
    //
    // Guarded rather than assumed: setClockHandPosition is @since 3.3.0 and
    // the manifest declares 3.1.0, so twelve devices do not have the symbol
    // at all, and of the rest only the two Crossovers have hands to move.
    // Everything else returns false and carries on.
    function onShow() as Void {
        parkHands(true);
    }

    function onHide() as Void {
        parkHands(false);
    }

    private function parkHands(resting as Boolean) as Void {
        if (!(WatchUi has :ANALOG_CLOCK_STATE_RESTING) || !(self has :setClockHandPosition)) {
            return;
        }
        setClockHandPosition(
            {
                :clockState => resting
                    ? WatchUi.ANALOG_CLOCK_STATE_RESTING
                    : WatchUi.ANALOG_CLOCK_STATE_SYSTEM_TIME
            }
        );
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

        dc.drawText(headingX, h * 18 / 100, Graphics.FONT_MEDIUM, lines[0], Graphics.TEXT_JUSTIFY_CENTER);
        if (kindAt(_page) == PAGE_SET_CHART) {
            drawSetChart(dc, w, h);
        }
        if (!lines[1].equals("")) {
            dc.drawText(cx, h * 38 / 100, Graphics.FONT_SMALL, lines[1], Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (!lines[2].equals("")) {
            dc.drawText(cx, h * 50 / 100, Graphics.FONT_TINY, lines[2], Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (!lines[3].equals("")) {
            dc.drawText(cx, h * 61 / 100, Graphics.FONT_TINY, lines[3], Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.drawText(
            cx,
            h * 79 / 100,
            Graphics.FONT_XTINY,
            // The same hint fix as CustomWorkoutEditor's: this said "UP/DOWN"
            // on watches with no UP/DOWN keys, where paging is a swipe.
            Lang.format("$1$ $2$/$3$", [DeviceInput.pageLabel(), _page + 1, totalPages()]),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(cx, h * 89 / 100, Graphics.FONT_XTINY, "BACK exit", Graphics.TEXT_JUSTIFY_CENTER);
    }

    /**
     * One bar per set, scaled to the busiest.
     *
     * The per-set pages already carry every number; what they cannot show is
     * the shape. A real 12-set session ran 67, 79, 85, 56, 64, 64, 69, 71,
     * 77, 49, 45, 46 - and the athlete confirmed the last three were genuine
     * fatigue. Read one page at a time that is twelve numbers to hold in your
     * head; read as bars it is one glance, and it is the glance worth having
     * while deciding whether there is another set in you.
     *
     * Deliberately unlabelled. At 176px twelve bars leave about ten pixels
     * each, which is a shape and not a table - the caption under it gives the
     * range, and the exact figures are a few presses away on the set pages.
     *
     * Drawn between the chord at the chart's own height rather than the full
     * width: on a round screen the widest row is the middle, and these bars
     * sit just below it.
    */
    (:setChart)
    private function drawSetChart(dc as Dc, w as Number, h as Number) as Void {
        var sets = _workout.getSets();
        var peak = peakSetSwings();
        if (sets <= 0 || peak <= 0) {
            return;
        }
        var base = h * CHART_BASE_PERCENT / 100;
        var top = h * CHART_TOP_PERCENT / 100;
        var full = base - top;
        var half = Layout.usableHalfWidth(w, h, base);
        var span = half * 2 * 84 / 100;
        var left = w / 2 - span / 2;
        var slot = span / sets;
        // A gap between bars until there is no room for one; past about
        // twenty sets they become a single block, which still reads as a
        // shape.
        var barWidth = slot > 3 ? slot - 2 : slot;
        if (barWidth < 1) {
            barWidth = 1;
        }
        dc.setColor(Palette.ACCENT, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < sets; i++) {
            var swings = setSwings(i);
            // An uncounted set is a floor-height stub rather than a gap, so
            // the run of sets stays readable as a run.
            var barHeight = swings <= 0 ? 1 : full * swings / peak;
            if (barHeight < 1) {
                barHeight = 1;
            }
            dc.fillRectangle(left + i * slot, base - barHeight, barWidth, barHeight);
        }
        dc.setColor(Palette.TEXT, Graphics.COLOR_TRANSPARENT);
    }

    (:noSetChart)
    private function drawSetChart(dc as Dc, w as Number, h as Number) as Void {}

    // [heading, line1, line2, line3] for the current page; exposed (not just
    // used from onUpdate) so tests can assert on content, not just that
    // rendering doesn't crash.
    function currentLines() as Array<String> {
        var kind = kindAt(_page);
        if (kind == PAGE_OVERVIEW) {
            return overviewLines();
        }
        if (kind == PAGE_SET_CHART) {
            return setChartLines();
        }
        if (kind == PAGE_RHYTHM) {
            return smoothnessLines();
        }
        if (kind == PAGE_LOAD) {
            return swingsAndLoadLines();
        }
        if (kind == PAGE_BALANCE) {
            return balanceLines();
        }
        return setLines(_page - aggregatePages());
    }

    // Heading and caption only: the middle of this page is drawn, not
    // written. The caption gives the bars a scale, since a shape with no
    // numbers on it could be any range at all.
    (:setChart)
    private function setChartLines() as Array<String> {
        var peak = peakSetSwings();
        var low = peak;
        for (var i = 0; i < _workout.getSets(); i++) {
            var swings = setSwings(i);
            if (swings >= 0 && swings < low) {
                low = swings;
            }
        }
        return ["SETS", "", "", Lang.format("$1$-$2$ per set", [low, peak])];
    }

    // Never reached - kindAt() cannot return PAGE_SET_CHART where hasSetChart
    // is the always-false twin - but currentLines() is compiled on every
    // device and refers to this by name.
    (:noSetChart)
    private function setChartLines() as Array<String> {
        return ["", "", "", ""];
    }
}
