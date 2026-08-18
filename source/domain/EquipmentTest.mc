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
    Test.assertEqualMessage(
        Equipment.labelFor(Equipment.TYPE_BULAVA, 1, 6000),
        pounds ? "Bulava: 13.2 lb" : "Bulava: 6 kg",
        "bulava label follows watch units"
    );
    return true;
}

(:test)
function testBulavaIsASingleImplementWithItsOwnWeight(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(
        Equipment.weightKeyFor(Equipment.TYPE_BULAVA),
        "bulavaWeightGrams",
        "bulava weight persists under its own key"
    );
    Test.assertEqualMessage(
        Equipment.defaultWeightGrams(Equipment.TYPE_BULAVA),
        6000,
        "bulava defaults heavier than mace and clubs"
    );
    var session = new WorkoutSession();
    session.selectEquipment(Equipment.TYPE_BULAVA, 2);
    Test.assertEqualMessage(session.getEquipmentCount(), 1, "bulava quantity is always one");
    return true;
}

(:test)
function testEquipmentHistoryKeysSeparateProfiles(logger as Test.Logger) as Boolean {
    var mace = Equipment.historyKeyFor(Equipment.TYPE_MACE, 1, 10000);
    var clubs = Equipment.historyKeyFor(Equipment.TYPE_CLUBS, 2, 10000);
    var lighterClubs = Equipment.historyKeyFor(Equipment.TYPE_CLUBS, 2, 8000);
    var bulava = Equipment.historyKeyFor(Equipment.TYPE_BULAVA, 1, 10000);
    Test.assertMessage(!mace.equals(clubs), "mace scores are not compared with clubs");
    Test.assertMessage(!clubs.equals(lighterClubs), "different weights have separate histories");
    Test.assertMessage(!bulava.equals(mace), "bulava scores are not compared with the mace");
    return true;
}

(:test)
function testEquipmentConvenienceWrappersMatchTheirExplicitForms(logger as Test.Logger) as Boolean {
    var kind = Equipment.type();
    var count = Equipment.count();
    var grams = Equipment.defaultWeightGrams(kind);
    Test.assertEqualMessage(
        Equipment.label(),
        Equipment.labelFor(kind, count, grams),
        "label() is labelFor over the configured profile"
    );
    Test.assertEqualMessage(
        Equipment.historyKey(),
        Equipment.historyKeyFor(kind, count, grams),
        "historyKey() is historyKeyFor over the configured profile"
    );
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
