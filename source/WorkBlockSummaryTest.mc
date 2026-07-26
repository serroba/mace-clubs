import Toybox.Lang;
import Toybox.Test;

(:test)
function testWorkBlockKeepsDomainContext(logger as Test.Logger) as Boolean {
    var block = new WorkBlockSummary(
        2,
        120,
        Movement.TYPE_MILL,
        Movement.SIDE_LEFT,
        Equipment.TYPE_CLUBS,
        1,
        4000,
        1,
        87
    );
    block.setRestSeconds(60);

    Test.assertEqualMessage(block.getSetNumber(), 2, "set number");
    Test.assertEqualMessage(block.getWorkSeconds(), 120, "work duration");
    Test.assertEqualMessage(block.getRestSeconds(), 60, "rest duration");
    Test.assertEqualMessage(block.getMovementType(), Movement.TYPE_MILL, "movement");
    Test.assertEqualMessage(block.getWorkingSide(), Movement.SIDE_LEFT, "working side");
    Test.assertEqualMessage(block.getEquipmentType(), Equipment.TYPE_CLUBS, "implement");
    Test.assertEqualMessage(block.getEquipmentCount(), 1, "implement count");
    Test.assertEqualMessage(block.getEquipmentWeightGrams(), 4000, "weight");
    Test.assertEqualMessage(block.getWatchWrist(), 1, "sensor wrist remains separate");
    Test.assertEqualMessage(block.getSmoothness(), 87, "smoothness");
    return true;
}

(:test)
function testMovementLabelsCoverSupportedVocabulary(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(Movement.typeLabel(Movement.TYPE_360), "360", "360");
    Test.assertEqualMessage(Movement.typeLabel(Movement.TYPE_10_TO_2), "10-to-2", "10-to-2");
    Test.assertEqualMessage(Movement.typeLabel(Movement.TYPE_MILL), "Mill", "mill");
    Test.assertEqualMessage(Movement.typeLabel(Movement.TYPE_SHIELD_CAST), "Shield cast", "shield cast");
    Test.assertEqualMessage(Movement.typeLabel(Movement.TYPE_FLOW_OTHER), "Flow / other", "other");
    Test.assertEqualMessage(Movement.sideLabel(Movement.SIDE_LEFT), "Left", "left");
    Test.assertEqualMessage(Movement.sideLabel(Movement.SIDE_RIGHT), "Right", "right");
    Test.assertEqualMessage(Movement.sideLabel(Movement.SIDE_ALTERNATING), "Alternating", "alternating");
    Test.assertEqualMessage(Movement.sideLabel(Movement.SIDE_TWO_HANDED), "Two-handed", "two-handed");
    return true;
}
