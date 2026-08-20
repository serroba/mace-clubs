import Toybox.Lang;

// Formatted summary strings shared by the pre-save paused/done browse and
// the post-save workout summary, so both show identical set detail.
module SummaryText {
    function side(workout as WorkoutSession, index as Number) as String {
        var block = workout.getBlock(index);
        return block == null ? "" : Movement.sideShortLabel((block as WorkBlockSummary).getWorkingSide());
    }

    function swings(workout as WorkoutSession, index as Number) as String {
        var block = workout.getBlock(index);
        if (block == null) {
            return "";
        }
        var count = (block as WorkBlockSummary).getSwings();
        return count < 0 ? "" : Lang.format("$1$ sw", [count]);
    }

    function smoothness(workout as WorkoutSession, index as Number) as String {
        if (index >= workout.getSetSmoothnessCount()) {
            return "";
        }
        var score = workout.getSetSmoothnessScore(index);
        return score < 0 ? "smooth --" : Lang.format("smooth $1$", [score]);
    }

    function load(workout as WorkoutSession, index as Number) as String {
        var block = workout.getBlock(index);
        if (block == null) {
            return "";
        }
        var exposure = (block as WorkBlockSummary).getMotionExposure();
        // A zero means the sensor saw no active window, not a meaningful
        // exposure measurement. Keep the readable smoothness label instead.
        return exposure <= 0 ? "" : LoadExposure.compactLabel(exposure);
    }

    // One compact line joining whatever per-set detail exists: detected
    // swings and the set's smoothness score.
    //
    // String equality here MUST use .equals(): Monkey C's == on Strings is
    // reference equality, not content equality, so `x == ""` is always
    // false even when x is genuinely empty.
    function detail(workout as WorkoutSession, index as Number) as String {
        var sw = swings(workout, index);
        var smooth = smoothness(workout, index);
        var ld = load(workout, index);
        if (!ld.equals("")) {
            // Compact tokens keep all enabled measures visible on 176 px
            // devices: e.g. "48sw S87 L12.4k".
            var block = workout.getBlock(index);
            var swingCount = block == null ? -1 : (block as WorkBlockSummary).getSwings();
            var compactSwings = swingCount < 0 ? "" : Lang.format("$1$sw", [swingCount]);
            var smoothScore = index >= workout.getSetSmoothnessCount()
                ? -1
                : workout.getSetSmoothnessScore(index);
            var compactSmooth = smooth.equals("")
                ? ""
                : (smoothScore < 0 ? "smooth --" : Lang.format("S$1$", [smoothScore]));
            if (!compactSwings.equals("") && !compactSmooth.equals("")) {
                return Lang.format("$1$ $2$ $3$", [compactSwings, compactSmooth, ld]);
            }
            if (!compactSwings.equals("")) {
                return Lang.format("$1$ $2$", [compactSwings, ld]);
            }
            if (!compactSmooth.equals("")) {
                return Lang.format("$1$ $2$", [compactSmooth, ld]);
            }
            return ld;
        }
        if (sw.equals("")) {
            return smooth;
        }
        if (smooth.equals("")) {
            return sw;
        }
        return Lang.format("$1$  $2$", [sw, smooth]);
    }

    // The just-finished session's own smoothness score, with a trend arrow
    // against the session before it when there is one.
    function sessionSmoothness(workout as WorkoutSession) as String {
        var score = workout.getSmoothnessScore();
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
}
