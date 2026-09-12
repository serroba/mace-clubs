import Toybox.Lang;
import Toybox.Math;

// Converts the detector's cumulative count into record-level training data.
// Cadence is a trailing ten-second rate: responsive enough to show changes
// without turning one missed sample into a distracting 0/60 oscillation.
//
// The Rhythm Score lives here too, for the same reason: it is the steadiness
// of the gaps between the swings this already sees, second by second. See
// docs/smoothness-physics.md for why it is measured here rather than from
// wrist acceleration, and what the old model got wrong.
module SwingSeries {
    const WINDOW_SECONDS = 10;

    // Gaps longer than this are not rhythm, they are a pause: a dropped
    // implement, a rest taken mid-set, or a run of swings the detector missed.
    // Counting them would report a break in training as a break in rhythm.
    const MAX_GAP_SECONDS = 10;

    // Below this a coefficient of variation says more about the detector than
    // about the athlete. Three gaps is four swings.
    const MIN_GAPS = 3;

    /**
     * Steadiness of a run of gaps, 0-100, or -1 when there are too few.
     *
     * 100 is a metronome. Scatter over mean - the coefficient of variation -
     * is the right shape because it is scale-free: swinging slowly and evenly
     * scores the same as swinging quickly and evenly, which is what makes this
     * a rhythm score rather than a pace one.
    */
    function steadiness(gaps as Number, total as Number, totalSquares as Number) as Number {
        if (gaps < MIN_GAPS || total <= 0) {
            return -1;
        }
        var n = gaps.toFloat();
        var mean = total.toFloat() / n;
        // Population variance from the running sums, floored at zero: exact in
        // integers, but the subtraction can land a hair below zero in Float
        // when every gap is identical.
        var variance = totalSquares.toFloat() / n - mean * mean;
        if (variance < 0.0) {
            variance = 0.0;
        }
        var score = (100.0 - 100.0 * (Math.sqrt(variance) / mean)).toNumber();
        if (score < 0) {
            return 0;
        }
        return score > 100 ? 100 : score;
    }

    class Tracker {
        private var _lastTotal as Number = 0;
        private var _events as Array<Number> = [];
        private var _windowTotal as Number = 0;
        // Rhythm, accumulated rather than sampled: a set can hold a few
        // hundred swings and these watches have kilobytes spare, so nothing
        // keeps the gaps themselves.
        private var _second as Number = -1;
        private var _lastSwingSecond as Number = -1;
        private var _gaps as Number = 0;
        private var _gapTotal as Number = 0;
        private var _gapSquares as Number = 0;
        // The same sums again for the whole session, because the set span is
        // cleared at every set boundary and the session score outlives it.
        private var _sessionGaps as Number = 0;
        private var _sessionTotal as Number = 0;
        private var _sessionSquares as Number = 0;

        function addTotal(total as Number) as Dictionary {
            var event = total - _lastTotal;
            if (event < 0) {
                event = 0;
            } else if (event > 255) {
                event = 255;
            }
            _lastTotal = total;
            _second++;
            recordGaps(event);
            _events.add(event);
            _windowTotal += event;
            if (_events.size() > WINDOW_SECONDS) {
                // slice, not remove: Array.remove() takes a VALUE, so
                // remove(0) deleted the first *zero* in the window rather than
                // the oldest second. _windowTotal was decremented by the
                // oldest value while a different element left the array, so it
                // drifted below the array's real sum and went negative - which
                // the UINT8 swing_cadence field then wrapped to ~255. Every
                // recording shipped a cadence trace that was mostly garbage.
                _windowTotal -= _events[0];
                _events = _events.slice(1, null);
            }
            var seconds = _events.size();
            var cadence = seconds == 0 ? 0 : _windowTotal * 60 / seconds;
            // swing_cadence is a UINT8. A count can legitimately exceed one per
            // second (the club detector counts movements), so clamp rather than
            // let the field wrap silently the way it just did.
            if (cadence < 0) {
                cadence = 0;
            } else if (cadence > 255) {
                cadence = 255;
            }
            return {:total => total, :event => event, :cadence => cadence};
        }

        /**
         * The gaps closed by `swings` detected in the current second.
         *
         * More than one in a second is treated as evenly spaced inside the gap
         * that closed - the only assumption available at 1 Hz, and only
         * reachable above 60 swings a minute, where calling the second gap
         * zero would score a burst as perfect rhythm.
        */
        private function recordGaps(swings as Number) as Void {
            if (swings <= 0) {
                return;
            }
            if (_lastSwingSecond >= 0) {
                var span = _second - _lastSwingSecond;
                if (span > 0 && span <= MAX_GAP_SECONDS) {
                    var each = span / swings;
                    if (each < 1) {
                        each = 1;
                    }
                    for (var i = 0; i < swings; i++) {
                        _gaps++;
                        _gapTotal += each;
                        _gapSquares += each * each;
                        _sessionGaps++;
                        _sessionTotal += each;
                        _sessionSquares += each * each;
                    }
                }
            }
            _lastSwingSecond = _second;
        }

        /** The Rhythm Score for the gaps seen since the last openSpan(). */
        function getSteadiness() as Number {
            return steadiness(_gaps, _gapTotal, _gapSquares);
        }

        function getGaps() as Number {
            return _gaps;
        }

        /** The Rhythm Score for every gap in the session so far. */
        function getSessionSteadiness() as Number {
            return steadiness(_sessionGaps, _sessionTotal, _sessionSquares);
        }

        function getSessionGaps() as Number {
            return _sessionGaps;
        }

        /**
         * Starts a fresh scoring span - a new set - without forgetting where
         * the last swing was.
         *
         * Deliberately not clearing _lastSwingSecond: the first swing of a set
         * closes the gap that spans the rest before it, which is minutes long
         * and discarded by MAX_GAP_SECONDS. Clearing it would make no
         * difference to the score and would cost the guarantee that a rest is
         * never counted as rhythm.
        */
        function openSpan() as Void {
            _gaps = 0;
            _gapTotal = 0;
            _gapSquares = 0;
        }

        // Manual count corrections are bookkeeping, not newly detected
        // swings. Aligning prevents the next sensor record inventing an event.
        function align(total as Number) as Void {
            _lastTotal = total;
        }

        function reset() as Void {
            _lastTotal = 0;
            _events = [];
            _windowTotal = 0;
            _second = -1;
            _lastSwingSecond = -1;
            _sessionGaps = 0;
            _sessionTotal = 0;
            _sessionSquares = 0;
            openSpan();
        }
    }
}
