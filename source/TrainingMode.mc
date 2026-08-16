import Toybox.Lang;

module TrainingMode {
    const INTERVAL = 0;
    const REPS = 1;
    const DEFAULT_TARGET = 50;
    const TARGETS = [0, 10, 25, 50, 100, 200];

    function normalize(value as Number) as Number {
        return value == REPS ? REPS : INTERVAL;
    }

    function label(value as Number) as String {
        return normalize(value) == REPS ? "reps" : "intervals";
    }

    function targetLabel(target as Number) as String {
        return target <= 0 ? "off" : target.toString();
    }

    function nextTarget(target as Number) as Number {
        for (var i = 0; i < TARGETS.size(); i++) {
            if (TARGETS[i] == target) {
                return TARGETS[(i + 1) % TARGETS.size()];
            }
        }
        return DEFAULT_TARGET;
    }

    function crossedTarget(previous as Number, current as Number, target as Number) as Boolean {
        return target > 0 && previous < target && current >= target;
    }
}
