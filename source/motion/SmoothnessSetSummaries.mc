import Toybox.Lang;

// Bounded per-set Rhythm Scores.
//
// Took cumulative Smoothness.Tracker snapshots and subtracted them, back when
// a set score was the mean of its windows. The score is now a statistic over
// a set's swing gaps rather than a running total, so the set hands over a
// finished number and the count it was computed from - see
// SwingSeries.steadiness and docs/smoothness-physics.md.
class SmoothnessSetSummaries {
    const MIN_SAMPLES = 3;

    private var _open as Boolean = false;
    private var _summaries as Array<Number> = [];

    function initialize() {}

    function begin() as Void {
        _open = true;
    }

    function complete(score as Number, samples as Number) as Void {
        if (!_open) {
            return;
        }
        _summaries.add(samples > 0 ? score : -1);
        _summaries.add(samples);
        _open = false;
    }

    function completeMissing() as Void {
        _summaries.add(-1);
        _summaries.add(0);
    }

    function isOpen() as Boolean {
        return _open;
    }

    function count() as Number {
        return _summaries.size() / 2;
    }

    function score(index as Number) as Number {
        if (index < 0 || index >= count()) {
            return -1;
        }
        return windows(index) < MIN_SAMPLES ? -1 : _summaries[index * 2];
    }

    function windows(index as Number) as Number {
        if (index < 0 || index >= count()) {
            return 0;
        }
        return _summaries[index * 2 + 1];
    }
}
