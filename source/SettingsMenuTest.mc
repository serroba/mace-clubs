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
function testSettingsMenuPropertyFallbacks(logger as Test.Logger) as Boolean {
    Test.assertMessage(SettingsMenu.boolProp("noSuchKeyForTests", true), "missing key keeps true default");
    Test.assertMessage(!SettingsMenu.boolProp("noSuchKeyForTests", false), "missing key keeps false default");
    Test.assertEqualMessage(
        SettingsMenu.numProp("noSuchKeyForTests", 7),
        7,
        "missing key keeps number default"
    );
    return true;
}

(:test)
function testSettingsMenuLiveLabelsMatchTheirValueForms(logger as Test.Logger) as Boolean {
    // The live label readers must agree with their *For(value) forms over
    // whatever the current property values are.
    Test.assertEqualMessage(
        SettingsMenu.cornerLabel(),
        SettingsMenu.cornerLabelFor(SettingsMenu.numProp("circleShows", 0)),
        "corner label reads the live setting"
    );
    Test.assertEqualMessage(
        SettingsMenu.wristLabel(),
        SettingsMenu.wristLabelFor(SettingsMenu.numProp("watchWrist", 0)),
        "wrist label reads the live setting"
    );
    Test.assertEqualMessage(
        SettingsMenu.movementLabel(),
        SettingsMenu.movementLabelFor(Movement.typeFor(Equipment.type())),
        "movement label resolves against the default equipment"
    );
    Test.assertEqualMessage(
        SettingsMenu.workingSideLabel(),
        SettingsMenu.workingSideLabelFor(Movement.workingSide()),
        "side label reads the live setting"
    );
    Test.assertEqualMessage(
        SettingsMenu.cueLabel(),
        SettingsMenu.cueLabelFor(SettingsMenu.numProp("cueMode", 0)),
        "cue label reads the live setting"
    );
    Test.assertEqualMessage(
        SettingsMenu.equipmentWeightLabel(Equipment.TYPE_BULAVA),
        Lang.format(
            "Bulava: $1$",
            [Equipment.weightLabel(Equipment.defaultWeightGrams(Equipment.TYPE_BULAVA))]
        ),
        "weight rows name the implement"
    );
    var custom = Presets.custom();
    Test.assertEqualMessage(
        SettingsMenu.customWorkoutLabel(),
        Lang.format(
            "Custom: $1$x $2$/$3$",
            [custom[:sets], Presets.mmss(custom[:work] as Number), Presets.mmss(custom[:rest] as Number)]
        ),
        "custom row mirrors the configured shape"
    );
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
