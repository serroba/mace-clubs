import Toybox.Application;
import Toybox.Lang;

// The traditional bulava combination set: mill, reverse mill, and bullwhip
// on one hand, then the same sequence mirrored on the other. Beats per
// movement are phone-configurable (default 4-4-2). One metronome cycle is
// one hand's full sequence, so segment accents mark movement changes and
// the cycle top lands exactly on the hand switch.
module Combo {
    const MIN_SEGMENT_BEATS = 1;
    const MAX_SEGMENT_BEATS = 16;

    const HAND_LEFT = 0;
    const HAND_RIGHT = 1;

    function movements() as Array<Number> {
        return [Movement.TYPE_MILL, Movement.TYPE_REVERSE_MILL, Movement.TYPE_BULLWHIP] as Array<Number>;
    }

    function beats() as Array<Number> {
        return [
            beatsProperty("comboMillBeats", 4),
            beatsProperty("comboReverseMillBeats", 4),
            beatsProperty("comboBullwhipBeats", 2)
        ] as Array<Number>;
    }

    function cycleBeats(pattern as Array<Number>) as Number {
        var total = 0;
        for (var i = 0; i < pattern.size(); i++) {
            total += pattern[i];
        }
        return total;
    }

    // 0-based segment index for a 1-based metronome beat number.
    function stepAt(beatNumber as Number, pattern as Array<Number>) as Number {
        var rem = (beatNumber - 1) % cycleBeats(pattern);
        var acc = 0;
        for (var i = 0; i < pattern.size(); i++) {
            acc += pattern[i];
            if (rem < acc) {
                return i;
            }
        }
        return 0;
    }

    // Hands alternate every full cycle, starting on the left.
    function handAt(beatNumber as Number, pattern as Array<Number>) as Number {
        return (beatNumber - 1) / cycleBeats(pattern) % 2 == 0 ? HAND_LEFT : HAND_RIGHT;
    }

    // Compact all-caps step names sized for the mid-swing glance.
    function stepLabel(step as Number) as String {
        if (step == 1) {
            return "REV MILL";
        }
        if (step == 2) {
            return "WHIP";
        }
        return "MILL";
    }

    // e.g. "L MILL": the hand currently working plus the current movement.
    function statusLabel(beatNumber as Number, pattern as Array<Number>) as String {
        if (beatNumber < 1) {
            beatNumber = 1;
        }
        var hand = handAt(beatNumber, pattern) == HAND_LEFT ? "L" : "R";
        return Lang.format("$1$ $2$", [hand, stepLabel(stepAt(beatNumber, pattern))]);
    }

    function beatsProperty(key as String, fallback as Number) as Number {
        try {
            var value = Application.Properties.getValue(key);
            if (value instanceof Number) {
                if (value < MIN_SEGMENT_BEATS) {
                    return MIN_SEGMENT_BEATS;
                }
                return value > MAX_SEGMENT_BEATS ? MAX_SEGMENT_BEATS : value;
            }
        } catch (e) {}
        return fallback;
    }
}
