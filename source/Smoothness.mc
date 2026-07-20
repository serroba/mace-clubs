import Toybox.Lang;
import Toybox.Math;

// Pure, on-watch repeatability scoring over one-second motion summaries.
// See docs/smoothness-physics.md before changing the model or terminology.
module Smoothness {
    const MIN_DYNAMIC_RMS = 40;
    const WARMUP_WINDOWS = 4;
    const HISTORY_LIMIT = 12;

    function normalizedDifference(value as Float, reference as Float, floor as Float) as Float {
        var scale = reference < 0.0 ? -reference : reference;
        if (scale < floor) {
            scale = floor;
        }
        var difference = value - reference;
        if (difference < 0.0) {
            difference = -difference;
        }
        return (difference / scale).toFloat();
    }

    function windowScore(
        dynamicRms as Number,
        dynamicPeak as Number,
        crossings as Number,
        referenceRms as Float,
        referencePeak as Float,
        referenceCrossings as Float
    ) as Number {
        var rmsDifference = normalizedDifference(dynamicRms.toFloat(), referenceRms, 40.0);
        var peakDifference = normalizedDifference(dynamicPeak.toFloat(), referencePeak, 80.0);
        var timingDifference = normalizedDifference(crossings.toFloat(), referenceCrossings, 2.0);
        var difference = 0.45 * rmsDifference + 0.35 * peakDifference + 0.20 * timingDifference;
        var score = (100.0 - 100.0 * difference).toNumber();
        if (score < 0) {
            return 0;
        }
        return score > 100 ? 100 : score;
    }

    // Return a new bounded history so callers can test the persistence policy
    // without touching Application.Storage.
    function appendSummary(history as Array<Number>, score as Number, windows as Number) as Array<Number> {
        var result = [] as Array<Number>;
        var storedSessions = history.size() / 2;
        var start = storedSessions >= HISTORY_LIMIT ? 2 : 0;
        for (var i = start; i < history.size(); i++) {
            result.add(history[i]);
        }
        result.add(score);
        result.add(windows);
        return result;
    }

    class Tracker {
        private var _validWindows as Number = 0;
        private var _scoredWindows as Number = 0;
        private var _scoreTotal as Number = 0;
        private var _referenceRms as Float = 0.0;
        private var _referencePeak as Float = 0.0;
        private var _referenceCrossings as Float = 0.0;

        function add(features as Dictionary) as Boolean {
            var dynamicRms = features[:dynamicRms] as Number;
            var dynamicPeak = features[:dynamicPeak] as Number;
            var crossings = features[:zc] as Number;
            if (dynamicRms < MIN_DYNAMIC_RMS) {
                return false;
            }

            if (_validWindows == 0) {
                _referenceRms = dynamicRms.toFloat();
                _referencePeak = dynamicPeak.toFloat();
                _referenceCrossings = crossings.toFloat();
            } else {
                if (_validWindows >= WARMUP_WINDOWS) {
                    _scoreTotal += windowScore(
                        dynamicRms,
                        dynamicPeak,
                        crossings,
                        _referenceRms,
                        _referencePeak,
                        _referenceCrossings
                    );
                    _scoredWindows++;
                }
                // 20% new observation, 80% existing session reference.
                _referenceRms = 0.8 * _referenceRms + 0.2 * dynamicRms;
                _referencePeak = 0.8 * _referencePeak + 0.2 * dynamicPeak;
                _referenceCrossings = 0.8 * _referenceCrossings + 0.2 * crossings;
            }
            _validWindows++;
            return true;
        }

        function getScore() as Number {
            return _scoredWindows == 0 ? -1 : _scoreTotal / _scoredWindows;
        }

        function getScoredWindows() as Number {
            return _scoredWindows;
        }

        function getScoreTotal() as Number {
            return _scoreTotal;
        }
    }
}
