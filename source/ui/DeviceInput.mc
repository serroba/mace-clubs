import Toybox.Lang;
import Toybox.System;

// What this watch can actually be driven with.
//
// The app was written against the Instinct 3's five-button layout and its
// on-screen hints name those buttons literally ("MENU opens settings",
// "UP/DOWN: pages"). That is wrong on most of the catalogue: of the 120
// devices in the manifest, 30 have no UP/DOWN keys at all and seven have no
// MENU key - venu441mm, venu445mm, venux1, vivoactive6 and the three
// vivoactive3 variants. Confirmed in the simulator on vivoactive6, where a
// long-press on the screen does nothing and a long-press of BACK exits the
// app: there is no way to reach the settings menu, so settings, history and
// the custom-workout editor were unreachable on those seven watches.
//
// Two things follow. Hints name the affordance the device really has, and on
// a touch device with no MENU key the idle screen's hint line doubles as a
// tap target (see MaceClubsDelegate.onTap).
//
// Capabilities come from DeviceSettings.inputButtons - a bitmask, @since
// 1.2.0 - rather than a device-id list, so a watch we have never seen gets
// the right answer.
module DeviceInput {
    // Swipes on a touch screen raise the same next/previous-page behaviours
    // the UP/DOWN keys do - verified on vivoactive6, where a swipe up cycles
    // the workout preset exactly as UP does on the Instinct. So paging works
    // on those devices; only the wording of the hint was wrong.
    function canPage() as Boolean {
        return hasButton(System.BUTTON_INPUT_UP) || isTouch();
    }

    function hasMenuKey() as Boolean {
        return hasButton(System.BUTTON_INPUT_MENU);
    }

    function isTouch() as Boolean {
        return System.getDeviceSettings().isTouchScreen;
    }

    // True where the idle screen has to offer its own way into the settings
    // menu, because the device has no MENU key to raise onMenu() with.
    function needsMenuTapTarget() as Boolean {
        return !hasMenuKey() && isTouch();
    }

    // How to name the gesture that opens the menu, for a hint line.
    function menuLabel() as String {
        if (hasMenuKey()) {
            return "MENU";
        }
        return isTouch() ? "TAP" : "HOLD UP";
    }

    // How to name the gesture that pages up and down.
    function pageLabel() as String {
        return hasButton(System.BUTTON_INPUT_UP) ? "UP/DOWN" : "SWIPE";
    }

    function hasButton(bit as Number) as Boolean {
        var settings = System.getDeviceSettings();
        // inputButtons is optional on very old devices; assume the buttons
        // are there rather than hiding a hint that would have been correct.
        if (settings.inputButtons == null) {
            return true;
        }
        return ((settings.inputButtons as Number) & bit) != 0;
    }
}
