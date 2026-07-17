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
        menu.addItem(new WatchUi.MenuItem("Corner", cornerLabel(), "circleShows", null));
        menu.addItem(new WatchUi.MenuItem("Beat cues", cueLabel(), "cueMode", null));
        menu.addItem(
            new WatchUi.ToggleMenuItem(
                "Beep on beat",
                null,
                "toneEnabled",
                boolProp("toneEnabled", false),
                null
            )
        );
        menu.addItem(
            new WatchUi.ToggleMenuItem(
                "Vibrate on beat",
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
                "Accent downbeat",
                null,
                "accentEnabled",
                boolProp("accentEnabled", true),
                null
            )
        );
        menu.addItem(
            new WatchUi.ToggleMenuItem(
                "Motion capture",
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
        return numProp("circleShows", 0) == 0 ? "Rounds" : "Heart rate";
    }

    // cueMode: 0 = every loop (default), 1 = every beat, 2 = cycle top.
    function cueLabel() as String {
        var m = numProp("cueMode", 0);
        if (m == 1) {
            return "Every beat";
        }
        if (m == 2) {
            return "Cycle top";
        }
        return "Every loop";
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
