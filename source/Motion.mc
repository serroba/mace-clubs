import Toybox.Lang;
import Toybox.Math;

// Per-second feature extraction over a buffer of accelerometer samples
// (milli-g per axis). These 1Hz aggregates go into the FIT record
// stream as developer fields - small enough to log every second, rich
// enough to study swing periodicity offline before building any
// on-watch inference.
module Motion {
    // :rms        - RMS of the acceleration magnitude (mg)
    // :peak       - largest magnitude in the window (mg)
    // :zc         - sign changes of the demeaned magnitude (periodicity proxy)
    // :dynamicRms - RMS after subtracting the per-axis window mean (mg)
    // :dynamicPeak- peak after subtracting the per-axis window mean (mg)
    function features(x as Array<Number>, y as Array<Number>, z as Array<Number>) as Dictionary {
        var n = x.size();
        if (n == 0 || y.size() != n || z.size() != n) {
            return {:rms => 0, :peak => 0, :zc => 0, :dynamicRms => 0, :dynamicPeak => 0};
        }

        var mags = new Array<Float>[n];
        var sumSq = 0.0;
        var sum = 0.0;
        var sumX = 0.0;
        var sumY = 0.0;
        var sumZ = 0.0;
        var peak = 0.0;
        for (var i = 0; i < n; i++) {
            var fx = x[i].toFloat();
            var fy = y[i].toFloat();
            var fz = z[i].toFloat();
            sumX += fx;
            sumY += fy;
            sumZ += fz;
            var mag = Math.sqrt(fx * fx + fy * fy + fz * fz).toFloat();
            mags[i] = mag;
            sum += mag;
            sumSq += mag * mag;
            if (mag > peak) {
                peak = mag;
            }
        }

        var mean = sum / n;
        var meanX = sumX / n;
        var meanY = sumY / n;
        var meanZ = sumZ / n;
        var zc = 0;
        var lastSign = 0;
        var dynamicSumSq = 0.0;
        var dynamicPeak = 0.0;
        for (var j = 0; j < n; j++) {
            var d = (mags[j] as Float) - mean;
            var sign = d > 0.0 ? 1 : (d < 0.0 ? -1 : 0);
            if (sign != 0 && lastSign != 0 && sign != lastSign) {
                zc++;
            }
            if (sign != 0) {
                lastSign = sign;
            }
            var dx = x[j].toFloat() - meanX;
            var dy = y[j].toFloat() - meanY;
            var dz = z[j].toFloat() - meanZ;
            var dynamicMag = Math.sqrt(dx * dx + dy * dy + dz * dz).toFloat();
            dynamicSumSq += dynamicMag * dynamicMag;
            if (dynamicMag > dynamicPeak) {
                dynamicPeak = dynamicMag;
            }
        }

        return {
            :rms         => Math.sqrt(sumSq / n).toNumber(),
            :peak        => peak.toNumber(),
            :zc          => zc,
            :dynamicRms  => Math.sqrt(dynamicSumSq / n).toNumber(),
            :dynamicPeak => dynamicPeak.toNumber()
        };
    }
}
