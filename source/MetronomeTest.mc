import Toybox.Lang;
import Toybox.Test;

// Run with: monkeydo bin/mace-clubs.prg instinct3solar45mm -t
// (build with `monkeyc ... --unit-test` first)
//
// Limits are asserted as literals (20/240/50) rather than through the
// class constants: Monkey C does not expose class consts as static
// symbols, and the literals pin the documented contract anyway.

(:test)
function testDefaultBpmIs50(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    Test.assertEqualMessage(m.getBpm(), 50, "default bpm should be 50");
    return true;
}

(:test)
function testBpmClampsToMinimum(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.setBpm(5);
    Test.assertEqualMessage(m.getBpm(), 20, "bpm should clamp to minimum");
    return true;
}

(:test)
function testBpmClampsToMaximum(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.setBpm(999);
    Test.assertEqualMessage(m.getBpm(), 240, "bpm should clamp to maximum");
    return true;
}

(:test)
function testAdjustBpmMovesInSteps(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.setBpm(50);
    m.adjustBpm(1);
    Test.assertEqualMessage(m.getBpm(), 55, "one step up from 50 should be 55");
    m.adjustBpm(-2);
    Test.assertEqualMessage(m.getBpm(), 45, "two steps down from 55 should be 45");
    return true;
}

(:test)
function testAdjustBpmDoesNotCrossLimits(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.setBpm(20);
    m.adjustBpm(-1);
    Test.assertEqualMessage(m.getBpm(), 20, "adjust below min should stay at min");
    return true;
}

(:test)
function testMetronomeStartsAndStops(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    Test.assertMessage(!m.isRunning(), "should not run before start");
    m.start();
    Test.assertMessage(m.isRunning(), "should run after start");
    m.stop();
    Test.assertMessage(!m.isRunning(), "should not run after stop");
    return true;
}
