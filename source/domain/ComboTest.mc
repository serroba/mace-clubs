import Toybox.Lang;
import Toybox.Test;

(:test)
function testComboDefaultsToFourFourTwo(logger as Test.Logger) as Boolean {
    var beats = Combo.beats();
    Test.assertEqualMessage(beats.size(), 3, "three segments");
    Test.assertEqualMessage(beats[0], 4, "mill defaults to four beats");
    Test.assertEqualMessage(beats[1], 4, "reverse mill defaults to four beats");
    Test.assertEqualMessage(beats[2], 2, "bullwhip defaults to two beats");
    Test.assertEqualMessage(Combo.cycleBeats(beats), 10, "one hand's sequence spans ten beats");
    var movements = Combo.movements();
    Test.assertEqualMessage(movements[0], Movement.TYPE_MILL, "mill first");
    Test.assertEqualMessage(movements[1], Movement.TYPE_REVERSE_MILL, "reverse mill second");
    Test.assertEqualMessage(movements[2], Movement.TYPE_BULLWHIP, "bullwhip third");
    return true;
}

(:test)
function testComboStepFollowsTheBeat(logger as Test.Logger) as Boolean {
    var pattern = [4, 4, 2] as Array<Number>;
    Test.assertEqualMessage(Combo.stepAt(1, pattern), 0, "beat 1 is the mill");
    Test.assertEqualMessage(Combo.stepAt(4, pattern), 0, "beat 4 is still the mill");
    Test.assertEqualMessage(Combo.stepAt(5, pattern), 1, "beat 5 starts the reverse mill");
    Test.assertEqualMessage(Combo.stepAt(8, pattern), 1, "beat 8 is still the reverse mill");
    Test.assertEqualMessage(Combo.stepAt(9, pattern), 2, "beat 9 starts the bullwhip");
    Test.assertEqualMessage(Combo.stepAt(10, pattern), 2, "beat 10 finishes the bullwhip");
    Test.assertEqualMessage(Combo.stepAt(11, pattern), 0, "beat 11 restarts on the mill");
    return true;
}

(:test)
function testComboHandsAlternateEveryCycle(logger as Test.Logger) as Boolean {
    var pattern = [4, 4, 2] as Array<Number>;
    Test.assertEqualMessage(Combo.handAt(1, pattern), Combo.HAND_LEFT, "first cycle is the left hand");
    Test.assertEqualMessage(Combo.handAt(10, pattern), Combo.HAND_LEFT, "left through beat 10");
    Test.assertEqualMessage(Combo.handAt(11, pattern), Combo.HAND_RIGHT, "beat 11 switches to the right");
    Test.assertEqualMessage(Combo.handAt(20, pattern), Combo.HAND_RIGHT, "right through beat 20");
    Test.assertEqualMessage(Combo.handAt(21, pattern), Combo.HAND_LEFT, "beat 21 returns to the left");
    return true;
}

(:test)
function testComboStatusLabelsAreGlanceable(logger as Test.Logger) as Boolean {
    var pattern = [4, 4, 2] as Array<Number>;
    Test.assertEqualMessage(Combo.statusLabel(1, pattern), "L MILL", "left mill at the start");
    Test.assertEqualMessage(Combo.statusLabel(6, pattern), "L REV MILL", "left reverse mill mid-cycle");
    Test.assertEqualMessage(Combo.statusLabel(9, pattern), "L WHIP", "left bullwhip closes the hand");
    Test.assertEqualMessage(Combo.statusLabel(15, pattern), "R REV MILL", "second cycle works the right");
    Test.assertEqualMessage(Combo.statusLabel(0, pattern), "L MILL", "before the first beat shows the start");
    return true;
}
