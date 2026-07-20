import Toybox.Lang;
import Toybox.Test;

(:test)
function testEquipmentLabels(logger as Test.Logger) as Boolean {
    var pounds = Equipment.usesPounds();
    Test.assertEqualMessage(
        Equipment.labelFor(Equipment.TYPE_MACE, 1, 10000),
        pounds ? "Mace: 22 lb" : "Mace: 10 kg",
        "mace label follows watch units"
    );
    Test.assertEqualMessage(
        Equipment.labelFor(Equipment.TYPE_CLUBS, 2, 2500),
        pounds ? "Clubs: 2 x 5.5 lb" : "Clubs: 2 x 2.5 kg",
        "pair of clubs uses per-club weight"
    );
    Test.assertEqualMessage(
        Equipment.labelFor(Equipment.TYPE_CLUBS, 1, 1500),
        pounds ? "Club: 3.3 lb" : "Club: 1.5 kg",
        "single club label"
    );
    return true;
}

(:test)
function testEquipmentHistoryKeysSeparateProfiles(logger as Test.Logger) as Boolean {
    var mace = Equipment.historyKeyFor(Equipment.TYPE_MACE, 1, 10000);
    var clubs = Equipment.historyKeyFor(Equipment.TYPE_CLUBS, 2, 10000);
    var lighterClubs = Equipment.historyKeyFor(Equipment.TYPE_CLUBS, 2, 8000);
    Test.assertMessage(!mace.equals(clubs), "mace scores are not compared with clubs");
    Test.assertMessage(!clubs.equals(lighterClubs), "different weights have separate histories");
    return true;
}

(:test)
function testEquipmentWeightConversionUsesCanonicalGrams(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(Equipment.gramsFromEditorTenths(40, false), 4000, "4.0 kg stores as 4000 g");
    Test.assertEqualMessage(Equipment.editorTenths(4000, false), 40, "4000 g displays as 4.0 kg");
    Test.assertEqualMessage(Equipment.decimalLabel(40, "kg"), "4 kg", "whole weights omit decimal zero");
    Test.assertEqualMessage(Equipment.decimalLabel(25, "kg"), "2.5 kg", "half weights retain decimal");
    var gramsFromEightPointEightPounds = Equipment.gramsFromEditorTenths(88, true);
    Test.assertEqualMessage(
        Equipment.editorTenths(gramsFromEightPointEightPounds, true),
        88,
        "pound editing round-trips without display drift"
    );
    return true;
}
