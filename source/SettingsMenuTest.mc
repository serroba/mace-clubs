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
