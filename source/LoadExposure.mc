import Toybox.Lang;

// Transparent per-set wrist-motion exposure. This is not tendon force:
// dynamic acceleration is measured at the watch and is retained alongside
// the implement, movement, and working-side context for like-for-like review.
module LoadExposure {
    const MIN_DYNAMIC_RMS = 40;

    class Tracker {
        private var _exposure as Number = 0;
        private var _peak as Number = 0;
        private var _activeSeconds as Number = 0;

        // Motion.features() supplies one summary per second, so summing its
        // dynamic RMS produces mg-seconds without retaining raw samples.
        function add(features as Dictionary) as Boolean {
            var rms = features[:dynamicRms] as Number;
            if (rms < MIN_DYNAMIC_RMS) {
                return false;
            }
            _exposure += rms;
            _activeSeconds++;
            var peak = features[:dynamicPeak] as Number;
            if (peak > _peak) {
                _peak = peak;
            }
            return true;
        }

        function getExposure() as Number {
            return _exposure;
        }

        function getPeak() as Number {
            return _peak;
        }

        function getActiveSeconds() as Number {
            return _activeSeconds;
        }

        function reset() as Void {
            _exposure = 0;
            _peak = 0;
            _activeSeconds = 0;
        }
    }

    // Weight-volume is deliberately descriptive rather than a force value.
    // Equipment weight is per implement, so a pair of clubs counts twice.
    function weightVolumeKgSwings(weightGrams as Number, quantity as Number, swings as Number) as Number {
        if (weightGrams <= 0 || quantity <= 0 || swings <= 0) {
            return 0;
        }
        return weightGrams * quantity * swings / 1000;
    }

    // Compact label for the 176 px paused/completed summary line.
    function compactLabel(exposure as Number) as String {
        if (exposure < 0) {
            return "";
        }
        if (exposure < 1000) {
            return Lang.format("L$1$", [exposure]);
        }
        var tenths = exposure / 100;
        return Lang.format("L$1$.$2$k", [tenths / 10, tenths % 10]);
    }
}
