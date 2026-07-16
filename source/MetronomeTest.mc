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
function testBeatFeedbackDefaultsToVibrationOnly(logger as Test.Logger) as Boolean {
    // Both channels at once is heavy; ship vibration-only out of the box
    // and let the rider add the beep. Both stay independently toggleable.
    var m = new Metronome();
    Test.assertMessage(!m.isToneEnabled(), "beep should default off");
    Test.assertMessage(m.isVibeEnabled(), "vibration should default on");
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
    m.setCueMode(1); // every beat
    Test.assertMessage(m.shouldCue(1), "beat 1 cues");
    Test.assertMessage(m.shouldCue(2), "beat 2 cues");
    Test.assertMessage(m.shouldCue(3), "beat 3 cues");
    return true;
}

(:test)
function testCycleTopCueModeCuesOncePerPattern(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.setPattern([4, 2] as Toybox.Lang.Array<Toybox.Lang.Number>);
    m.setCueMode(2); // cycle top only
    Test.assertMessage(m.shouldCue(1), "cue at the top of the 4-2 cycle");
    Test.assertMessage(!m.shouldCue(5), "loop B start is silent in cycle-top mode");
    Test.assertMessage(!m.shouldCue(2), "silent inside loop A");
    Test.assertMessage(m.shouldCue(7), "cue at the top of the next cycle");
    Test.assertMessage(!m.shouldCue(11), "loop B start of cycle 2 is silent");
    return true;
}

(:test)
function testCycleTopMatchesLoopStartsForSingleLoop(logger as Test.Logger) as Boolean {
    // A single-loop pattern has one loop per cycle, so cycle-top and
    // loop-start modes are indistinguishable - no behaviour change.
    var m = new Metronome(); // default 4 beats, single loop
    m.setCueMode(2);
    Test.assertMessage(m.shouldCue(1), "cue on beat 1");
    Test.assertMessage(!m.shouldCue(2), "silent mid-loop");
    Test.assertMessage(m.shouldCue(5), "cue on beat 5");
    return true;
}

(:test)
function testCueModeClampsToKnownRange(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.setPattern([4, 2] as Toybox.Lang.Array<Toybox.Lang.Number>);
    m.setCueMode(99); // clamps to 2 (cycle top)
    Test.assertMessage(m.shouldCue(1), "clamped-high mode still cues loop A start");
    m.setCueMode(-5); // clamps to 0 (loop starts)
    Test.assertMessage(m.shouldCue(1), "clamped-low mode still cues loop A start");
    return true;
}

(:test)
function testMixedPatternCountsRounds(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.setPattern([4, 2] as Toybox.Lang.Array<Toybox.Lang.Number>);
    m.start(); // beat 1
    for (var i = 0; i < 5; i++) {
        m.onBeat(); // beats 2..6: one full 4-2 cycle
    }
    Test.assertEqualMessage(m.getRounds(), 2, "4-2 cycle complete = 2 rounds");
    for (var j = 0; j < 4; j++) {
        m.onBeat(); // beats 7..10: loop A of cycle 2 done
    }
    m.stop();
    Test.assertEqualMessage(m.getRounds(), 3, "next 4-beat loop = 3rd round");
    return true;
}

(:test)
function testMixedPatternRoundStarts(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.setPattern([4, 2] as Toybox.Lang.Array<Toybox.Lang.Number>);
    Test.assertMessage(m.isRoundStart(1), "beat 1 starts loop A");
    Test.assertMessage(!m.isRoundStart(4), "beat 4 is inside loop A");
    Test.assertMessage(m.isRoundStart(5), "beat 5 starts loop B");
    Test.assertMessage(!m.isRoundStart(6), "beat 6 is inside loop B");
    Test.assertMessage(m.isRoundStart(7), "beat 7 starts the next cycle");
    Test.assertMessage(m.isRoundStart(11), "beat 11 starts loop B again");
    return true;
}

(:test)
function testMixedPatternRoundCues(logger as Test.Logger) as Boolean {
    var m = new Metronome(); // default round-cue mode
    m.setPattern([4, 2] as Toybox.Lang.Array<Toybox.Lang.Number>);
    Test.assertMessage(m.shouldCue(1), "cue at loop A start");
    Test.assertMessage(m.shouldCue(5), "cue at loop B start");
    Test.assertMessage(!m.shouldCue(6), "silent inside loop B");
    Test.assertMessage(m.shouldCue(7), "cue at next cycle start");
    return true;
}

(:test)
function testApplyPatternSingleLoopWhenBIsZero(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.applyPattern(4, 0); // loop B = 0 -> uniform single loop
    Test.assertMessage(m.isRoundStart(1), "beat 1 starts a round");
    Test.assertMessage(!m.isRoundStart(2), "beat 2 is mid-loop");
    Test.assertMessage(m.isRoundStart(5), "beat 5 starts the next round");
    return true;
}

(:test)
function testApplyPatternVaryingWhenBIsPositive(logger as Test.Logger) as Boolean {
    var m = new Metronome();
    m.applyPattern(4, 2); // the club 4-2
    Test.assertMessage(m.isRoundStart(1), "beat 1 starts loop A");
    Test.assertMessage(m.isRoundStart(5), "beat 5 starts loop B");
    Test.assertMessage(!m.isRoundStart(6), "beat 6 is inside loop B");
    Test.assertMessage(m.isRoundStart(7), "beat 7 starts the next cycle");
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
