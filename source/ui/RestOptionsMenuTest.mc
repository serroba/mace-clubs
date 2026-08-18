import Toybox.Lang;
import Toybox.Test;

(:test)
function testRestOptionsLabelsAreCompact(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(
        RestOptionsMenu.movementLabel(Movement.TYPE_360),
        "Move: 360",
        "movement row label"
    );
    Test.assertEqualMessage(
        RestOptionsMenu.movementLabel(Movement.TYPE_COMBO),
        "Move: Combo",
        "combo row label"
    );
    Test.assertEqualMessage(RestOptionsMenu.sideLabel(Movement.SIDE_LEFT), "Side: Left", "side row label");
    Test.assertEqualMessage(
        RestOptionsMenu.sideLabel(Movement.SIDE_ALTERNATING),
        "Side: Alternating",
        "alternating side row label"
    );
    return true;
}
