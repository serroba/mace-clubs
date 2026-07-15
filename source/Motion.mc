import Toybox.Lang;
import Toybox.Math;

// Per-second feature extraction over a buffer of accelerometer samples
// (milli-g per axis). These 1Hz aggregates go into the FIT record
// stream as developer fields - small enough to log every second, rich
// enough to study swing periodicity offline before building any
// on-watch inference.
module Motion {
    // :rms  - RMS of the acceleration magnitude (mg)
    // :peak - largest magnitude in the window (mg)
    // :zc   - sign changes of the demeaned magnitude (periodicity proxy)
    function features(x as Array<Number>, y as Array<Number>, z as Array<Number>) as Dictionary {
        var n = x.size();
        if (n == 0 || y.size() != n || z.size() != n) {
            return {:rms => 0, :peak => 0, :zc => 0};
        }

        var mags = new Array<Float>[n];
        var sumSq = 0.0;
        var sum = 0.0;
        var peak = 0.0;
        for (var i = 0; i < n; i++) {
            var fx = x[i].toFloat();
            var fy = y[i].toFloat();
            var fz = z[i].toFloat();
            var mag = Math.sqrt(fx * fx + fy * fy + fz * fz).toFloat();
            mags[i] = mag;
            sum += mag;
            sumSq += mag * mag;
            if (mag > peak) {
                peak = mag;
            }
        }

        var mean = sum / n;
        var zc = 0;
        var lastSign = 0;
        for (var j = 0; j < n; j++) {
            var d = (mags[j] as Float) - mean;
            var sign = d > 0.0 ? 1 : (d < 0.0 ? -1 : 0);
            if (sign != 0 && lastSign != 0 && sign != lastSign) {
                zc++;
            }
            if (sign != 0) {
                lastSign = sign;
            }
        }

        return {:rms => Math.sqrt(sumSq / n).toNumber(), :peak => peak.toNumber(), :zc => zc};
    }
}
