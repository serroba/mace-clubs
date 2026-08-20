import Toybox.Lang;

// On-watch swing-cycle counting from 25Hz accelerometer samples (milli-g).
// A gada/club swing whips the implement (and the wrist) through one
// high-acceleration pass per cycle, so the magnitude trace shows one
// dominant peak per swing above the ~1g resting baseline. Counting is a
// rising-edge threshold crossing with hysteresis (re-arm only after the
// magnitude falls back near baseline) plus a refractory window, because a
// single overhead pass can stay above threshold for several samples and
// competition pace never exceeds one swing per second.
module SwingCounter {
    const HIGH_MG = 1800;
    const LOW_MG = 1300;
    const SAMPLE_RATE_HZ = 25;
    const MIN_GAP_SAMPLES = 25;
    // Legacy behaviour: a single sample past threshold flips the state.
    const DEBOUNCE_SAMPLES = 1;

    // A mace's full-circle swing dwells through its arc for a couple of
    // seconds rather than whipping through one sharp pass, which leaves
    // room for in-swing noise to bounce back across HIGH_MG/LOW_MG inside
    // what is really a single rep. Requiring the signal to hold past
    // threshold for a few samples (~160ms, still far shorter than any real
    // swing's peak dwell) filters that out without touching the thresholds
    // themselves. First-pass estimate - validate against a real recording
    // before trusting it as final.
    const MACE_DEBOUNCE_SAMPLES = 4;

    // A real recording's per-second swing_event trace (never more than one
    // event per second) showed the actual failure mode: most overcounts are
    // a second, spurious re-arm-and-cross roughly 1-2s after the real one,
    // well inside the same physical rep, followed by a 3-5s gap to the next
    // genuine rep. A 1s refractory (MIN_GAP_SAMPLES) sits right in the
    // middle of that spurious gap; holding it through ~2.5s clears the
    // false doublet while staying comfortably under every observed
    // real inter-rep gap. First-pass estimate from one recording - revisit
    // once we have more real mace data across cadences.
    const MACE_MIN_GAP_SAMPLES = 63;

    class Counter {
        private var _highMg as Number;
        private var _lowMg as Number;
        private var _minGapSamples as Number;
        private var _debounceSamples as Number;
        private var _count as Number = 0;
        private var _armed as Boolean = true;
        private var _sinceLast as Number;
        private var _aboveStreak as Number = 0;
        private var _belowStreak as Number = 0;

        function initialize(
            highMg as Number,
            lowMg as Number,
            minGapSamples as Number,
            debounceSamples as Number
        ) {
            _highMg = highMg;
            _lowMg = lowMg;
            _minGapSamples = minGapSamples;
            _debounceSamples = debounceSamples;
            _sinceLast = minGapSamples;
        }

        // Comparisons stay in squared milli-g to avoid a per-sample sqrt;
        // watch accelerometers clip near 8g, which keeps the squares within
        // Number range.
        function addSamples(x as Array<Number>, y as Array<Number>, z as Array<Number>) as Void {
            var n = x.size();
            if (y.size() != n || z.size() != n) {
                return;
            }
            var high = _highMg * _highMg;
            var low = _lowMg * _lowMg;
            for (var i = 0; i < n; i++) {
                var m2 = x[i] * x[i] + y[i] * y[i] + z[i] * z[i];
                if (_sinceLast < _minGapSamples) {
                    _sinceLast++;
                }
                if (_armed) {
                    if (m2 >= high) {
                        _aboveStreak++;
                        if (_sinceLast >= _minGapSamples && _aboveStreak >= _debounceSamples) {
                            _count++;
                            _armed = false;
                            _sinceLast = 0;
                            _aboveStreak = 0;
                            _belowStreak = 0;
                        }
                    } else {
                        _aboveStreak = 0;
                    }
                } else if (m2 <= low) {
                    _belowStreak++;
                    if (_belowStreak >= _debounceSamples) {
                        _armed = true;
                        _belowStreak = 0;
                    }
                } else {
                    _belowStreak = 0;
                }
            }
        }

        function getCount() as Number {
            return _count;
        }

        function adjust(delta as Number) as Void {
            _count += delta;
            if (_count < 0) {
                _count = 0;
            }
        }

        function reset() as Void {
            _count = 0;
            _armed = true;
            _sinceLast = _minGapSamples;
            _aboveStreak = 0;
            _belowStreak = 0;
        }
    }

    // Clubs and the bulava keep the original single-sample edge behaviour;
    // nothing in the real-world data we've gathered so far points at an
    // issue with those implements.
    function defaultCounter() as Counter {
        return new Counter(HIGH_MG, LOW_MG, MIN_GAP_SAMPLES, DEBOUNCE_SAMPLES);
    }

    function maceCounter() as Counter {
        return new Counter(HIGH_MG, LOW_MG, MACE_MIN_GAP_SAMPLES, MACE_DEBOUNCE_SAMPLES);
    }
}
