import Toybox.Lang;
import Toybox.Test;

(:test)
function testMovementOptionsPerEquipment(logger as Test.Logger) as Boolean {
    var mace = Movement.optionsFor(Equipment.TYPE_MACE);
    Test.assertEqualMessage(mace.size(), 3, "mace offers three movements");
    Test.assertEqualMessage(mace[0], Movement.TYPE_360, "mace leads with the 360");
    Test.assertEqualMessage(mace[1], Movement.TYPE_10_TO_2, "mace includes the 10-to-2");
    Test.assertEqualMessage(mace[2], Movement.TYPE_FLOW_OTHER, "mace keeps the flow catch-all");
    var clubs = Movement.optionsFor(Equipment.TYPE_CLUBS);
    Test.assertEqualMessage(clubs.size(), 3, "clubs offer three movements");
    Test.assertEqualMessage(clubs[0], Movement.TYPE_MILL, "clubs lead with the mill");
    Test.assertEqualMessage(clubs[1], Movement.TYPE_SHIELD_CAST, "clubs include the shield cast");
    Test.assertEqualMessage(clubs[2], Movement.TYPE_FLOW_OTHER, "clubs keep the flow catch-all");
    var bulava = Movement.optionsFor(Equipment.TYPE_BULAVA);
    Test.assertEqualMessage(bulava.size(), 5, "bulava offers five movements");
    Test.assertEqualMessage(bulava[0], Movement.TYPE_COMBO, "bulava leads with the traditional combo");
    Test.assertEqualMessage(bulava[1], Movement.TYPE_MILL, "bulava includes the mill");
    Test.assertEqualMessage(bulava[2], Movement.TYPE_REVERSE_MILL, "bulava includes the reverse mill");
    Test.assertEqualMessage(bulava[3], Movement.TYPE_BULLWHIP, "bulava includes the bullwhip");
    Test.assertEqualMessage(bulava[4], Movement.TYPE_FLOW_OTHER, "bulava keeps the flow catch-all");
    return true;
}

(:test)
function testBulavaMovementLabelsAndFallback(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(
        Movement.typeLabel(Movement.TYPE_REVERSE_MILL),
        "Reverse mill",
        "reverse mill label"
    );
    Test.assertEqualMessage(Movement.typeLabel(Movement.TYPE_BULLWHIP), "Bullwhip", "bullwhip label");
    Test.assertEqualMessage(Movement.typeLabel(Movement.TYPE_COMBO), "Combo", "combo label");
    Test.assertEqualMessage(
        Movement.resolveFor(Movement.TYPE_360, Equipment.TYPE_BULAVA),
        Movement.TYPE_COMBO,
        "a mace movement falls back to the bulava default"
    );
    Test.assertEqualMessage(
        Movement.resolveFor(Movement.TYPE_BULLWHIP, Equipment.TYPE_MACE),
        Movement.TYPE_360,
        "a bulava movement falls back to the mace default"
    );
    return true;
}

(:test)
function testMovementResolveKeepsValidChoices(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(
        Movement.resolveFor(Movement.TYPE_10_TO_2, Equipment.TYPE_MACE),
        Movement.TYPE_10_TO_2,
        "10-to-2 stays valid for the mace"
    );
    Test.assertEqualMessage(
        Movement.resolveFor(Movement.TYPE_SHIELD_CAST, Equipment.TYPE_CLUBS),
        Movement.TYPE_SHIELD_CAST,
        "shield cast stays valid for clubs"
    );
    Test.assertEqualMessage(
        Movement.resolveFor(Movement.TYPE_FLOW_OTHER, Equipment.TYPE_CLUBS),
        Movement.TYPE_FLOW_OTHER,
        "flow stays valid everywhere"
    );
    return true;
}

(:test)
function testMovementResolveFallsBackAcrossEquipment(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(
        Movement.resolveFor(Movement.TYPE_MILL, Equipment.TYPE_MACE),
        Movement.TYPE_360,
        "a club movement falls back to the mace default"
    );
    Test.assertEqualMessage(
        Movement.resolveFor(Movement.TYPE_360, Equipment.TYPE_CLUBS),
        Movement.TYPE_MILL,
        "a mace movement falls back to the club default"
    );
    return true;
}

(:test)
function testSideShortLabelsAreCompact(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(Movement.sideShortLabel(Movement.SIDE_LEFT), "L", "left tag");
    Test.assertEqualMessage(Movement.sideShortLabel(Movement.SIDE_RIGHT), "R", "right tag");
    Test.assertEqualMessage(Movement.sideShortLabel(Movement.SIDE_ALTERNATING), "Alt", "alternating tag");
    Test.assertEqualMessage(Movement.sideShortLabel(Movement.SIDE_TWO_HANDED), "2H", "two-handed tag");
    return true;
}

(:test)
function testBalanceLabelShowsOnlyForSingleSideSets(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(Movement.balanceLabel(0, 0), "", "no single-side sets, no balance tag");
    Test.assertEqualMessage(Movement.balanceLabel(3, 2), "L3/R2", "uneven session is visible");
    Test.assertEqualMessage(Movement.balanceLabel(0, 1), "L0/R1", "a single right set still shows");
    return true;
}

(:test)
function testMovementNextCyclesWithinEquipment(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(
        Movement.nextTypeFor(Movement.TYPE_360, Equipment.TYPE_MACE),
        Movement.TYPE_10_TO_2,
        "mace cycles 360 to 10-to-2"
    );
    Test.assertEqualMessage(
        Movement.nextTypeFor(Movement.TYPE_FLOW_OTHER, Equipment.TYPE_MACE),
        Movement.TYPE_360,
        "mace wraps flow back to the 360"
    );
    Test.assertEqualMessage(
        Movement.nextTypeFor(Movement.TYPE_MILL, Equipment.TYPE_CLUBS),
        Movement.TYPE_SHIELD_CAST,
        "clubs cycle mill to shield cast"
    );
    Test.assertEqualMessage(
        Movement.nextTypeFor(Movement.TYPE_360, Equipment.TYPE_CLUBS),
        Movement.TYPE_MILL,
        "an invalid value restarts the club cycle"
    );
    return true;
}
