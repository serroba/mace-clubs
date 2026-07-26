import Toybox.Application;
import Toybox.Lang;

// Movement and working-side context are intentionally separate from the watch
// wrist. The watch wrist locates the sensor; the working side describes the
// athlete's movement.
module Movement {
    const TYPE_360 = 0;
    const TYPE_10_TO_2 = 1;
    const TYPE_MILL = 2;
    const TYPE_SHIELD_CAST = 3;
    const TYPE_FLOW_OTHER = 4;
    const TYPE_COUNT = 5;

    const SIDE_LEFT = 0;
    const SIDE_RIGHT = 1;
    const SIDE_ALTERNATING = 2;
    const SIDE_TWO_HANDED = 3;
    const SIDE_COUNT = 4;

    function type() as Number {
        return clampProperty("movementType", TYPE_360, TYPE_COUNT);
    }

    function workingSide() as Number {
        return clampProperty("workingSide", SIDE_TWO_HANDED, SIDE_COUNT);
    }

    function typeLabel(value as Number) as String {
        if (value == TYPE_10_TO_2) {
            return "10-to-2";
        }
        if (value == TYPE_MILL) {
            return "Mill";
        }
        if (value == TYPE_SHIELD_CAST) {
            return "Shield cast";
        }
        if (value == TYPE_FLOW_OTHER) {
            return "Flow / other";
        }
        return "360";
    }

    function sideLabel(value as Number) as String {
        if (value == SIDE_LEFT) {
            return "Left";
        }
        if (value == SIDE_RIGHT) {
            return "Right";
        }
        if (value == SIDE_ALTERNATING) {
            return "Alternating";
        }
        return "Two-handed";
    }

    function clampProperty(key as String, fallback as Number, count as Number) as Number {
        try {
            var value = Application.Properties.getValue(key);
            if (value instanceof Number && value >= 0 && value < count) {
                return value;
            }
        } catch (e) {}
        return fallback;
    }
}
