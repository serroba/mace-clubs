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

    // The traditional canon differs per implement: the gada's exercises are
    // the 360 and the 10-to-2, while mills and shield casts come from club
    // swinging. Flow/other stays available everywhere as the catch-all.
    function optionsFor(equipmentType as Number) as Array<Number> {
        if (equipmentType == Equipment.TYPE_CLUBS) {
            return [TYPE_MILL, TYPE_SHIELD_CAST, TYPE_FLOW_OTHER] as Array<Number>;
        }
        return [TYPE_360, TYPE_10_TO_2, TYPE_FLOW_OTHER] as Array<Number>;
    }

    // Maps any stored movement onto the equipment's list, so switching
    // implements never records a movement the implement cannot perform.
    function resolveFor(value as Number, equipmentType as Number) as Number {
        var options = optionsFor(equipmentType);
        for (var i = 0; i < options.size(); i++) {
            if (options[i] == value) {
                return value;
            }
        }
        return options[0];
    }

    function typeFor(equipmentType as Number) as Number {
        return resolveFor(type(), equipmentType);
    }

    function nextTypeFor(value as Number, equipmentType as Number) as Number {
        var options = optionsFor(equipmentType);
        for (var i = 0; i < options.size(); i++) {
            if (options[i] == value) {
                return options[(i + 1) % options.size()];
            }
        }
        return options[0];
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
