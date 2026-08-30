import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// One test function, deliberately: a --unit-test build allows at most 253
// module-level symbols and this suite runs close to that on
// venusq/instinct2/fenix5 (see LayoutTest for the same constraint).
//
// The point of these assertions is that the hints and the tap target follow
// the hardware rather than a device-id list. Observed bitmasks, for the
// record: instinct3solar45mm 143 (select+up+down+menu+esc),
// venu3 137 (select+menu+esc, no up/down), vivoactive6 129 (select+esc only).
(:test)
function testInputHintsMatchTheHardware(logger as Test.Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var menuLabel = DeviceInput.menuLabel();
    var pageLabel = DeviceInput.pageLabel();

    // A hint may never name a button this watch does not have.
    Test.assertEqualMessage(
        menuLabel.equals("MENU"),
        DeviceInput.hasMenuKey(),
        Lang.format("menu hint \"$1$\" against inputButtons $2$", [menuLabel, settings.inputButtons])
    );
    Test.assertEqualMessage(
        pageLabel.equals("UP/DOWN"),
        (settings.inputButtons as Number) & System.BUTTON_INPUT_UP != 0,
        Lang.format("page hint \"$1$\" against inputButtons $2$", [pageLabel, settings.inputButtons])
    );

    // The tap target exists exactly where there is no other way into the
    // menu, and never where onMenu() can already be raised.
    Test.assertMessage(
        !(DeviceInput.needsMenuTapTarget() && DeviceInput.hasMenuKey()),
        "a device with a MENU key must not also claim the tap target"
    );
    if (DeviceInput.needsMenuTapTarget()) {
        Test.assertMessage(DeviceInput.isTouch(), "the tap target only makes sense on a touch screen");
        Test.assertEqualMessage(menuLabel, "TAP", "a tap-target device tells the user to tap");
    }

    // Paging must be reachable somehow on every device: either UP/DOWN keys
    // or swipes, or preset selection and rest paging are dead ends.
    Test.assertMessage(
        DeviceInput.canPage(),
        Lang.format(
            "no way to page on this device (inputButtons $1$, touch $2$)",
            [settings.inputButtons, settings.isTouchScreen]
        )
    );
    return true;
}
