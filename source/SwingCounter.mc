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

    class Counter {
        private var _count as Number = 0;
        private var _armed as Boolean = true;
        private var _sinceLast as Number = MIN_GAP_SAMPLES;

        // Comparisons stay in squared milli-g to avoid a per-sample sqrt;
        // watch accelerometers clip near 8g, which keeps the squares within
        // Number range.
        function addSamples(x as Array<Number>, y as Array<Number>, z as Array<Number>) as Void {
            var n = x.size();
            if (y.size() != n || z.size() != n) {
                return;
            }
            var high = HIGH_MG * HIGH_MG;
            var low = LOW_MG * LOW_MG;
            for (var i = 0; i < n; i++) {
                var m2 = x[i] * x[i] + y[i] * y[i] + z[i] * z[i];
                if (_sinceLast < MIN_GAP_SAMPLES) {
                    _sinceLast++;
                }
                if (_armed) {
                    if (_sinceLast >= MIN_GAP_SAMPLES && m2 >= high) {
                        _count++;
                        _armed = false;
                        _sinceLast = 0;
                    }
                } else if (m2 <= low) {
                    _armed = true;
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
            _sinceLast = MIN_GAP_SAMPLES;
        }
    }
}
