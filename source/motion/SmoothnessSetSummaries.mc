import Toybox.Lang;

// Converts cumulative Smoothness.Tracker snapshots into bounded per-set
// summaries. A single session reference remains in the tracker, so every set
// is compared consistently without repeating the four-window warm-up.
class SmoothnessSetSummaries {
    const MIN_WINDOWS = 3;

    private var _baselineTotal as Number = 0;
    private var _baselineWindows as Number = 0;
    private var _open as Boolean = false;
    private var _summaries as Array<Number> = [];

    function initialize() {}

    function begin(scoreTotal as Number, scoredWindows as Number) as Void {
        _baselineTotal = scoreTotal;
        _baselineWindows = scoredWindows;
        _open = true;
    }

    function complete(scoreTotal as Number, scoredWindows as Number) as Void {
        if (!_open) {
            return;
        }
        var windows = scoredWindows - _baselineWindows;
        var total = scoreTotal - _baselineTotal;
        _summaries.add(windows > 0 ? total / windows : -1);
        _summaries.add(windows);
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
        return windows(index) < MIN_WINDOWS ? -1 : _summaries[index * 2];
    }

    function windows(index as Number) as Number {
        if (index < 0 || index >= count()) {
            return 0;
        }
        return _summaries[index * 2 + 1];
    }
}
