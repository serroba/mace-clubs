import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// On-watch settings menu. Sideloaded builds don't get Garmin Connect's
// settings gear, so the most useful settings are editable here directly.
module SettingsMenu {
    function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Settings"});
        // Instinct's circular safe area is too short for Menu2's secondary
        // labels. Keep the current value in one compact primary label.
        menu.addItem(new WatchUi.MenuItem(cornerLabel(), null, "circleShows", null));
        menu.addItem(new WatchUi.MenuItem(wristLabel(), null, "watchWrist", null));
        menu.addItem(new WatchUi.MenuItem(movementLabel(), null, "movementType", null));
        menu.addItem(new WatchUi.MenuItem(workingSideLabel(), null, "workingSide", null));
        menu.addItem(new WatchUi.MenuItem(cueLabel(), null, "cueMode", null));
        menu.addItem(new WatchUi.MenuItem(customWorkoutLabel(), null, "customWorkout", null));
        menu.addItem(new WatchUi.MenuItem(equipmentWeightLabel(Equipment.TYPE_MACE), null, "maceWeight", null));
        menu.addItem(
            new WatchUi.MenuItem(equipmentWeightLabel(Equipment.TYPE_CLUBS), null, "clubWeight", null)
        );
        menu.addItem(
            new WatchUi.MenuItem(equipmentWeightLabel(Equipment.TYPE_BULAVA), null, "bulavaWeight", null)
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
                "Swing counter",
                null,
                "swingCounter",
                boolProp("swingCounter", false),
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

    function wristLabel() as String {
        return wristLabelFor(numProp("watchWrist", 0));
    }

    function wristLabelFor(value as Number) as String {
        return value == 1 ? "Wrist: right" : "Wrist: left";
    }

    function movementLabel() as String {
        return movementLabelFor(Movement.typeFor(Equipment.type()));
    }

    function movementLabelFor(value as Number) as String {
        return Lang.format("Move: $1$", [Movement.typeLabel(value)]);
    }

    function workingSideLabel() as String {
        return workingSideLabelFor(Movement.workingSide());
    }

    function workingSideLabelFor(value as Number) as String {
        return Lang.format("Side: $1$", [Movement.sideLabel(value)]);
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
        return Lang.format(
            "$1$: $2$",
            [Equipment.implementName(kind), Equipment.weightLabel(Equipment.defaultWeightGrams(kind))]
        );
    }

    function customWorkoutLabel() as String {
        var custom = Presets.custom();
        return Lang.format(
            "Custom: $1$x $2$/$3$",
            [custom[:sets], Presets.mmss(custom[:work] as Number), Presets.mmss(custom[:rest] as Number)]
        );
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
