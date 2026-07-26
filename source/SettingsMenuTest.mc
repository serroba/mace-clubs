import Toybox.Lang;
import Toybox.Test;

(:test)
function testSettingsMenuCornerLabels(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SettingsMenu.cornerLabelFor(0), "Corner: rounds", "rounds label is compact");
    Test.assertEqualMessage(SettingsMenu.cornerLabelFor(1), "Corner: HR", "heart-rate label is compact");
    return true;
}

(:test)
function testSettingsMenuCueLabels(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SettingsMenu.cueLabelFor(0), "Cues: every loop", "loop cue label is compact");
    Test.assertEqualMessage(SettingsMenu.cueLabelFor(1), "Cues: every beat", "beat cue label is compact");
    Test.assertEqualMessage(SettingsMenu.cueLabelFor(2), "Cues: cycle top", "cycle cue label is compact");
    return true;
}

(:test)
function testSettingsMenuWristLabels(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SettingsMenu.wristLabelFor(0), "Wrist: left", "left wrist label is compact");
    Test.assertEqualMessage(SettingsMenu.wristLabelFor(1), "Wrist: right", "right wrist label is compact");
    return true;
}

(:test)
function testSettingsMenuMovementLabels(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SettingsMenu.movementLabelFor(Movement.TYPE_360), "Move: 360", "360 label");
    Test.assertEqualMessage(
        SettingsMenu.movementLabelFor(Movement.TYPE_SHIELD_CAST),
        "Move: Shield cast",
        "shield-cast label"
    );
    Test.assertEqualMessage(
        SettingsMenu.workingSideLabelFor(Movement.SIDE_ALTERNATING),
        "Side: Alternating",
        "alternating-side label"
    );
    Test.assertEqualMessage(
        SettingsMenu.workingSideLabelFor(Movement.SIDE_TWO_HANDED),
        "Side: Two-handed",
        "two-handed label"
    );
    return true;
}
