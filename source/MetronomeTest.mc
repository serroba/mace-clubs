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
function testVibeStrengthDefaultsTo50(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    Test.assertEqualMessage(m.getVibeStrength(), 50, "default vibe strength should be 50");
    return true;
}

(:test)
function testVibeStrengthClampsToPerceptibleFloor(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.setVibeStrength(0);
    Test.assertEqualMessage(m.getVibeStrength(), 10, "strength should clamp to 10");
    m.setVibeStrength(999);
    Test.assertEqualMessage(m.getVibeStrength(), 100, "strength should clamp to 100");
    return true;
}

(:test)
function testRoundsDeriveFromBeats(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    Test.assertEqualMessage(m.getRounds(), 0, "no rounds before any beats");
    m.start(); // fires beat 1 immediately
    for (var i = 0; i < 7; i++) {
        m.onBeat(); // beats 2..8
    }
    m.stop();
    Test.assertEqualMessage(m.getRounds(), 2, "8 beats at 4 per round = 2 rounds");
    return true;
}

(:test)
function testResetBeatCountClearsRounds(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.start();
    m.onBeat();
    m.onBeat();
    m.onBeat(); // 4 beats = 1 round
    m.stop();
    Test.assertEqualMessage(m.getRounds(), 1, "one round after 4 beats");
    m.resetBeatCount();
    Test.assertEqualMessage(m.getRounds(), 0, "reset starts a fresh set");
    return true;
}

(:test)
function testRoundStartMarksDownbeats(logger as Test.Logger) as Boolean {
    var m = new Metronome(); // default 4 beats per round
    Test.assertMessage(m.isRoundStart(1), "beat 1 starts round 1");
    Test.assertMessage(!m.isRoundStart(2), "beat 2 is not a downbeat");
    Test.assertMessage(!m.isRoundStart(4), "beat 4 is not a downbeat");
    Test.assertMessage(m.isRoundStart(5), "beat 5 starts round 2");
    Test.assertMessage(m.isRoundStart(9), "beat 9 starts round 3");
    return true;
}

(:test)
function testRoundCueModeIsDefaultAndPulsesOnLoops(logger as Test.Logger) as Boolean {
    var m = new Metronome(); // default: round cues, 4 beats per round
    Test.assertMessage(m.shouldCue(1), "cue on round 1 start");
    Test.assertMessage(!m.shouldCue(2), "silent mid-round");
    Test.assertMessage(!m.shouldCue(4), "silent on round-closing beat");
    Test.assertMessage(m.shouldCue(5), "cue on round 2 start");
    return true;
}

(:test)
function testEveryBeatCueModeCuesAll(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.setCueEveryBeat(true);
    Test.assertMessage(m.shouldCue(1), "beat 1 cues");
    Test.assertMessage(m.shouldCue(2), "beat 2 cues");
    Test.assertMessage(m.shouldCue(3), "beat 3 cues");
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
