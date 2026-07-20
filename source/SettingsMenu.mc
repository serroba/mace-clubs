import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// On-watch settings menu. Sideloaded builds don't get Garmin Connect's
// settings gear, so the toggle/list settings are editable here directly.
// Numeric settings (tempo, vibe strength, loop A/B, custom shape) stay
// phone-only for now; tempo is already UP/DOWN adjustable in a workout.
module SettingsMenu {
    function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Settings"});
        // Instinct's circular safe area is too short for Menu2's secondary
        // labels. Keep the current value in one compact primary label.
        menu.addItem(new WatchUi.MenuItem(cornerLabel(), null, "circleShows", null));
        menu.addItem(new WatchUi.MenuItem(cueLabel(), null, "cueMode", null));
        menu.addItem(new WatchUi.MenuItem(equipmentWeightLabel(Equipment.TYPE_MACE), null, "maceWeight", null));
        menu.addItem(
            new WatchUi.MenuItem(equipmentWeightLabel(Equipment.TYPE_CLUBS), null, "clubWeight", null)
        );
        menu.addItem(
            new WatchUi.ToggleMenuItem("Beat beep", null, "toneEnabled", boolProp("toneEnabled", false), null)
        );
        menu.addItem(
            new WatchUi.ToggleMenuItem(
                "Beat vibration",
                null,
                "vibeEnabled",
                boolProp("vibeEnabled", true),
                null
            )
        );
        menu.addItem(
            new WatchUi.ToggleMenuItem("Soft beep", null, "softBeep", boolProp("softBeep", true), null)
        );
        menu.addItem(
            new WatchUi.ToggleMenuItem(
                "Downbeat accent",
                null,
                "accentEnabled",
                boolProp("accentEnabled", true),
                null
            )
        );
        menu.addItem(
            new WatchUi.ToggleMenuItem(
                "Smoothness",
                null,
                "smoothnessEnabled",
                boolProp("smoothnessEnabled", false),
                null
            )
        );
        menu.addItem(
            new WatchUi.ToggleMenuItem(
                "Motion logging",
                null,
                "motionCapture",
                boolProp("motionCapture", false),
                null
            )
        );
        return menu;
    }

    // circleShows: 0 = rounds (default), 1 = heart rate.
    function cornerLabel() as String {
        return cornerLabelFor(numProp("circleShows", 0));
    }

    function cornerLabelFor(value as Number) as String {
        return value == 0 ? "Corner: rounds" : "Corner: HR";
    }

    // cueMode: 0 = every loop (default), 1 = every beat, 2 = cycle top.
    function cueLabel() as String {
        return cueLabelFor(numProp("cueMode", 0));
    }

    function cueLabelFor(value as Number) as String {
        if (value == 1) {
            return "Cues: every beat";
        }
        if (value == 2) {
            return "Cues: cycle top";
        }
        return "Cues: every loop";
    }

    function equipmentWeightLabel(kind as Number) as String {
        var name = kind == Equipment.TYPE_CLUBS ? "Club" : "Mace";
        return Lang.format("$1$: $2$", [name, Equipment.weightLabel(Equipment.defaultWeightGrams(kind))]);
    }

    function boolProp(key as String, dflt as Boolean) as Boolean {
        try {
            var v = Application.Properties.getValue(key);
            if (v instanceof Boolean) {
                return v;
            }
        } catch (e) {}
        return dflt;
    }

    function numProp(key as String, dflt as Number) as Number {
        try {
            var v = Application.Properties.getValue(key);
            if (v instanceof Number) {
                return v;
            }
        } catch (e) {}
        return dflt;
    }
}
