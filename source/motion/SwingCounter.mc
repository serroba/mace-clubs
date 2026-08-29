import Toybox.Lang;
import Toybox.Math;

// On-watch swing-cycle counting. Mace counting is gyroscope-primary on the
// validated 25 Hz watch; club and bulava retain the legacy accelerometer
// detector until labelled gyro recordings exist for those implements.
module SwingCounter {
    const HIGH_MG = 1800;
    const LOW_MG = 1300;
    const SAMPLE_RATE_HZ = 25;
    const MIN_GAP_SAMPLES = 25;
    // Legacy behaviour: a single sample past threshold flips the state.
    const DEBOUNCE_SAMPLES = 1;

    // Gyroscope-primary mace counting. The shared offline fit across both
    // labelled gyro recordings uses an 11-sample window at the exported 12.5Hz
    // rate; the watch receives 25Hz, so 22 samples preserves the same ~0.88s
    // smoothing horizon. One-sample-delayed peak confirmation is causal and
    // scored [5,5,10,10] and [60,60] against the two labelled recordings.
    const GYRO_THRESHOLD_DPS = 250.0;
    const GYRO_SMOOTHING_SAMPLES = 22;
    const GYRO_MIN_GAP_SAMPLES = 25;

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
        private var _useGyro as Boolean;
        private var _gyroThresholdDps as Float;
        private var _gyroSmoothingSamples as Number;
        private var _gyroMinGapSamples as Number;
        private var _gyroWindow as Array<Float> = [];
        private var _gyroWindowSum as Float = 0.0;
        private var _gyroPreviousAverage as Float?;
        private var _gyroCurrentAverage as Float?;
        private var _sinceGyroPeak as Number;

        function initialize(
            highMg as Number,
            lowMg as Number,
            minGapSamples as Number,
            debounceSamples as Number,
            useGyro as Boolean,
            gyroThresholdDps as Float,
            gyroSmoothingSamples as Number,
            gyroMinGapSamples as Number
        ) {
            _highMg = highMg;
            _lowMg = lowMg;
            _minGapSamples = minGapSamples;
            _debounceSamples = debounceSamples;
            _sinceLast = minGapSamples;
            _useGyro = useGyro;
            _gyroThresholdDps = gyroThresholdDps;
            _gyroSmoothingSamples = gyroSmoothingSamples;
            _gyroMinGapSamples = gyroMinGapSamples;
            _sinceGyroPeak = gyroMinGapSamples;
        }

        // Comparisons stay in squared milli-g to avoid a per-sample sqrt;
        // watch accelerometers clip near 8g, which keeps the squares within
        // Number range.
        function addSamples(x as Array<Number>, y as Array<Number>, z as Array<Number>) as Void {
            if (_useGyro) {
                return;
            }
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

        // Streaming 25Hz rotation-rate peak detector. A trailing moving
        // average suppresses small shoulders; the previous average is only
        // accepted once the next sample confirms it was a local maximum.
        function addGyroSamples(
            x as Array<Float>,
            y as Array<Float>,
            z as Array<Float>,
            countingOpen as Boolean
        ) as Void {
            if (!_useGyro) {
                return;
            }
            var n = x.size();
            if (n == 0 || y.size() != n || z.size() != n) {
                return;
            }
            for (var i = 0; i < n; i++) {
                var fx = x[i];
                var fy = y[i];
                var fz = z[i];
                var magnitude = Math.sqrt(fx * fx + fy * fy + fz * fz).toFloat();
                _gyroWindow.add(magnitude);
                _gyroWindowSum += magnitude;
                if (_gyroWindow.size() > _gyroSmoothingSamples) {
                    var removed = _gyroWindow[0];
                    _gyroWindowSum -= removed;
                    _gyroWindow.remove(removed);
                }
                if (_sinceGyroPeak < _gyroMinGapSamples) {
                    _sinceGyroPeak++;
                }
                var average = _gyroWindowSum / _gyroWindow.size();
                var previous = _gyroPreviousAverage;
                var current = _gyroCurrentAverage;
                if (previous != null
                    && current != null
                    && current >= _gyroThresholdDps
                    && current > previous
                    && current >= average
                    && _sinceGyroPeak >= _gyroMinGapSamples)
                {
                    if (countingOpen) {
                        _count++;
                    }
                    _sinceGyroPeak = 0;
                }
                _gyroPreviousAverage = current;
                _gyroCurrentAverage = average;
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
            _gyroWindow = [];
            _gyroWindowSum = 0.0;
            _gyroPreviousAverage = null;
            _gyroCurrentAverage = null;
            _sinceGyroPeak = _gyroMinGapSamples;
        }
    }

    // Clubs and the bulava keep the original single-sample edge behaviour;
    // nothing in the real-world data we've gathered so far points at an
    // issue with those implements.
    function defaultCounter() as Counter {
        return new Counter(
            HIGH_MG,
            LOW_MG,
            MIN_GAP_SAMPLES,
            DEBOUNCE_SAMPLES,
            false,
            GYRO_THRESHOLD_DPS,
            GYRO_SMOOTHING_SAMPLES,
            GYRO_MIN_GAP_SAMPLES
        );
    }

    // Mace counting is rotation-primary on the gyroscope-equipped support
    // matrix; accelerometer parameters are ignored by this mode.
    function maceCounter() as Counter {
        return maceCounterWithGyroParams(GYRO_THRESHOLD_DPS, GYRO_SMOOTHING_SAMPLES, GYRO_MIN_GAP_SAMPLES);
    }

    // Dev/tuning only: lets a search harness try candidate gyro parameters
    // against the real Counter implementation instead of a reimplementation.
    // See source/motion/SwingTuningSearch.mc.
    function maceCounterWithGyroParams(
        gyroThresholdDps as Float,
        gyroSmoothingSamples as Number,
        gyroMinGapSamples as Number
    ) as Counter {
        return new Counter(
            HIGH_MG,
            LOW_MG,
            MIN_GAP_SAMPLES,
            DEBOUNCE_SAMPLES,
            true,
            gyroThresholdDps,
            gyroSmoothingSamples,
            gyroMinGapSamples
        );
    }
}
