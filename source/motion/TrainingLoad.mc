import Toybox.Application.Storage;
import Toybox.Lang;

// Acute:chronic workload ratio (ACWR) - the same "recent load vs your own
// baseline" idea sports science and Garmin's own Training Status use to
// flag a rising injury-risk trend. Built entirely from LoadExposure's
// per-set wrist-motion exposure (not real tendon force - see
// LoadExposure.mc's own disclaimer) summed across SmoothnessLog, since that
// is the only cross-session history this app already keeps. The ratio is a
// relative trend signal, not an absolute load measurement.
module TrainingLoad {
    const ACUTE_DAYS = 7;
    const CHRONIC_DAYS = 28;
    const SECONDS_PER_DAY = 86400;

    // Sum of every set's motion_exposure recorded within the last `days` of
    // `nowEpoch` (inclusive). Sessions with no exposure data (legacy records,
    // or load-exposure disabled) contribute nothing rather than skewing the
    // total negative.
    function totalExposureWithin(log as Array<Storage.ValueType>, nowEpoch as Number, days as Number) as Number {
        var cutoff = nowEpoch - days * SECONDS_PER_DAY;
        var total = 0;
        for (var i = 0; i < log.size(); i++) {
            var rec = log[i] as Array<Storage.ValueType>;
            var epoch = SmoothnessLog.epochOf(rec);
            if (epoch < cutoff || epoch > nowEpoch) {
                continue;
            }
            var blocks = SmoothnessLog.blockCountOf(rec);
            for (var b = 0; b < blocks; b++) {
                var exposure = SmoothnessLog.blockExposureOf(rec, b);
                if (exposure > 0) {
                    total += exposure;
                }
            }
        }
        return total;
    }

    // Ratio of the last 7 days' load to the last 28 days' average WEEKLY
    // load. Null when the chronic window has no exposure data at all - a
    // ratio against zero baseline would be meaningless rather than "high".
    function acuteChronicRatio(log as Array<Storage.ValueType>, nowEpoch as Number) as Float? {
        var chronicTotal = totalExposureWithin(log, nowEpoch, CHRONIC_DAYS);
        if (chronicTotal <= 0) {
            return null;
        }
        var acuteTotal = totalExposureWithin(log, nowEpoch, ACUTE_DAYS);
        var chronicWeekly = (chronicTotal * ACUTE_DAYS).toFloat() / CHRONIC_DAYS;
        return acuteTotal / chronicWeekly;
    }

    // Bands from the same convention Gabbett's ACWR research and Garmin's
    // Training Status use (roughly: <0.8 undertrained, 0.8-1.3 the "sweet
    // spot", 1.3-1.5 building, >1.5 a spike worth easing off) - not a
    // medical claim, just a rough framing for a wrist-motion proxy.
    function label(ratio as Float?) as String {
        if (ratio == null) {
            return "--";
        }
        if (ratio < 0.8) {
            return "Low";
        }
        if (ratio <= 1.3) {
            return "Steady";
        }
        if (ratio <= 1.5) {
            return "Building";
        }
        return "High";
    }
}
