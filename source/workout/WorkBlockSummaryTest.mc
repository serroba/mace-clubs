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
    Test.assertEqualMessage(block.getSwings(), -1, "swings default to not-counted");
    Test.assertEqualMessage(block.getMotionExposure(), -1, "load exposure defaults to not-measured");
    Test.assertEqualMessage(block.getMotionPeak(), -1, "motion peak defaults to not-measured");
    Test.assertEqualMessage(block.getActiveSeconds(), -1, "active time defaults to not-measured");
    Test.assertEqualMessage(block.getWeightVolume(), 0, "unknown swings have no weight-volume");
    block.setSwings(45);
    Test.assertEqualMessage(block.getSwings(), 45, "swing count");
    block.setLoadExposure(1234, 2500, 42);
    Test.assertEqualMessage(block.getMotionExposure(), 1234, "motion exposure");
    Test.assertEqualMessage(block.getMotionPeak(), 2500, "motion peak");
    Test.assertEqualMessage(block.getActiveSeconds(), 42, "active seconds");
    Test.assertEqualMessage(block.getWeightVolume(), 180, "weight-volume in kg-swings");
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
