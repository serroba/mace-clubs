import Toybox.Lang;
import Toybox.Test;

(:test)
function testEquipmentLabels(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(Equipment.labelFor(Equipment.TYPE_MACE, 1, 10000), "Mace: 10 kg", "mace label");
    Test.assertEqualMessage(
        Equipment.labelFor(Equipment.TYPE_CLUBS, 2, 2500),
        "Clubs: 2 x 2.5 kg",
        "pair of clubs uses per-club weight"
    );
    Test.assertEqualMessage(
        Equipment.labelFor(Equipment.TYPE_CLUBS, 1, 1500),
        "Club: 1.5 kg",
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
