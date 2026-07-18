import Toybox.Lang;
import Toybox.Test;

// Plan under test: 5 sets x 2:00 work, 1:00 rest (cycle = 180s).
// Last set has no trailing rest; the plan is DONE when its work ends
// (4 * 180 + 120 = 840s).

(:test)
function testPlanStartsInWorkSet1(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(0);
    Test.assertEqualMessage(s[:phase] as Number, Intervals.PHASE_WORK, "starts in WORK");
    Test.assertEqualMessage(s[:set] as Number, 1, "starts on set 1");
    Test.assertEqualMessage(s[:remaining] as Number, 120, "full work remaining");
    return true;
}

(:test)
function testWorkCountsDown(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(119000);
    Test.assertEqualMessage(s[:phase] as Number, Intervals.PHASE_WORK, "still WORK at 1:59");
    Test.assertEqualMessage(s[:remaining] as Number, 1, "one second left");
    return true;
}

(:test)
function testRestBeginsWhenWorkEnds(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(120000);
    Test.assertEqualMessage(s[:phase] as Number, Intervals.PHASE_REST, "REST at 2:00");
    Test.assertEqualMessage(s[:set] as Number, 1, "rest belongs to set 1");
    Test.assertEqualMessage(s[:remaining] as Number, 60, "full rest remaining");
    return true;
}

(:test)
function testNextSetBeginsAfterRest(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(180000);
    Test.assertEqualMessage(s[:phase] as Number, Intervals.PHASE_WORK, "WORK at 3:00");
    Test.assertEqualMessage(s[:set] as Number, 2, "set 2 after first rest");
    return true;
}

(:test)
function testLastSetHasNoTrailingRest(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(839000);
    Test.assertEqualMessage(s[:phase] as Number, Intervals.PHASE_WORK, "WORK just before the end");
    Test.assertEqualMessage(s[:set] as Number, 5, "on final set");
    var d = p.stateAt(840000);
    Test.assertEqualMessage(d[:phase] as Number, Intervals.PHASE_DONE, "DONE when last work ends");
    return true;
}

(:test)
function testDoneStaysDone(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(9999000);
    Test.assertEqualMessage(s[:phase] as Number, Intervals.PHASE_DONE, "DONE long after the end");
    Test.assertEqualMessage(s[:set] as Number, 5, "set count capped at plan size");
    return true;
}

(:test)
function testZeroRestPlanChainsSets(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(3, 60, 0);
    var s = p.stateAt(60000);
    Test.assertEqualMessage(s[:phase] as Number, Intervals.PHASE_WORK, "no rest phase when rest is 0");
    Test.assertEqualMessage(s[:set] as Number, 2, "straight into set 2");
    var d = p.stateAt(180000);
    Test.assertEqualMessage(d[:phase] as Number, Intervals.PHASE_DONE, "done after 3 x 60s");
    return true;
}

(:test)
function testCompletedSetsDuringPlan(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    Test.assertEqualMessage(p.completedSetsAt(0), 0, "none done at start");
    Test.assertEqualMessage(p.completedSetsAt(119000), 0, "none done mid work");
    Test.assertEqualMessage(p.completedSetsAt(120000), 1, "one done once rest starts");
    Test.assertEqualMessage(p.completedSetsAt(840000), 5, "all done at the end");
    return true;
}

(:test)
function testStartCountdownRoundsUpAndStopsAtDeadline(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(Intervals.countdownSeconds(1000, 6000), 5, "five seconds at countdown start");
    Test.assertEqualMessage(Intervals.countdownSeconds(1999, 6000), 5, "partial seconds round up");
    Test.assertEqualMessage(Intervals.countdownSeconds(2000, 6000), 4, "countdown advances on the second");
    Test.assertEqualMessage(Intervals.countdownSeconds(6000, 6000), 0, "zero at the deadline");
    Test.assertEqualMessage(Intervals.countdownSeconds(7000, 6000), 0, "never becomes negative");
    return true;
}

(:test)
function testWorkToRestCountsSetAndStopsMetronome(logger as Test.Logger) as Boolean {
    var a = Intervals.actionsForTransition(Intervals.PHASE_WORK, 1, Intervals.PHASE_REST, 1);
    Test.assertEqualMessage(a[:setsToAdd] as Number, 1, "finishing work counts a set");
    Test.assertMessage(a[:stopMetronome] as Boolean, "rest stops the metronome");
    Test.assertMessage(!(a[:startMetronome] as Boolean), "rest does not restart the metronome");
    Test.assertMessage(!(a[:pauseWorkout] as Boolean), "rest keeps the workout active");
    return true;
}

(:test)
function testAdvanceWarningFiresOnceWithinFiveSeconds(logger as Test.Logger) as Boolean {
    Test.assertMessage(
        !Intervals.shouldWarnNextWork(Intervals.PHASE_REST, 6, 1, 5, 0),
        "six seconds is too early"
    );
    Test.assertMessage(
        Intervals.shouldWarnNextWork(Intervals.PHASE_REST, 5, 1, 5, 0),
        "warning fires at five seconds"
    );
    Test.assertMessage(
        Intervals.shouldWarnNextWork(Intervals.PHASE_REST, 4, 1, 5, 0),
        "a delayed refresh still warns"
    );
    Test.assertMessage(
        !Intervals.shouldWarnNextWork(Intervals.PHASE_REST, 4, 1, 5, 1),
        "the same rest phase warns only once"
    );
    return true;
}

(:test)
function testRestToWorkRestartsWithoutCountingSet(logger as Test.Logger) as Boolean {
    var a = Intervals.actionsForTransition(Intervals.PHASE_REST, 1, Intervals.PHASE_WORK, 2);
    Test.assertEqualMessage(a[:setsToAdd] as Number, 0, "set was already counted when rest began");
    Test.assertMessage(a[:resetBeatCount] as Boolean, "new work resets the beat count");
    Test.assertMessage(a[:startMetronome] as Boolean, "new work starts the metronome");
    Test.assertMessage(!(a[:finished] as Boolean), "another work interval is not completion");
    return true;
}

(:test)
function testAdvanceWarningOnlyPrecedesAnotherWorkSet(logger as Test.Logger) as Boolean {
    Test.assertMessage(
        !Intervals.shouldWarnNextWork(Intervals.PHASE_WORK, 5, 1, 5, 0),
        "work countdown does not produce an advance warning"
    );
    Test.assertMessage(
        !Intervals.shouldWarnNextWork(Intervals.PHASE_REST, 5, 5, 5, 0),
        "final set has no next work interval"
    );
    Test.assertMessage(
        !Intervals.shouldWarnNextWork(Intervals.PHASE_REST, 0, 1, 5, 0),
        "zero remaining belongs to the transition"
    );
    return true;
}

(:test)
function testZeroRestRolloverCountsSetAndKeepsWorking(logger as Test.Logger) as Boolean {
    var a = Intervals.actionsForTransition(Intervals.PHASE_WORK, 1, Intervals.PHASE_WORK, 2);
    Test.assertEqualMessage(a[:setsToAdd] as Number, 1, "work-to-work rollover counts the completed set");
    Test.assertMessage(a[:resetBeatCount] as Boolean, "rollover resets the beat count");
    Test.assertMessage(a[:startMetronome] as Boolean, "rollover keeps the metronome running");
    Test.assertMessage(!(a[:pauseWorkout] as Boolean), "rollover does not pause the workout");
    return true;
}

(:test)
function testCompletionCountsFinalSetAndPauses(logger as Test.Logger) as Boolean {
    var a = Intervals.actionsForTransition(Intervals.PHASE_WORK, 5, Intervals.PHASE_DONE, 5);
    Test.assertEqualMessage(a[:setsToAdd] as Number, 1, "completion counts the final set");
    Test.assertMessage(a[:stopMetronome] as Boolean, "completion stops the metronome");
    Test.assertMessage(a[:pauseWorkout] as Boolean, "completion pauses the FIT session");
    Test.assertMessage(a[:finished] as Boolean, "completion selects the finished cue and UI");
    return true;
}

(:test)
function testSkippedRefreshCountsEveryCompletedSet(logger as Test.Logger) as Boolean {
    var a = Intervals.actionsForTransition(Intervals.PHASE_WORK, 1, Intervals.PHASE_WORK, 4);
    Test.assertEqualMessage(a[:setsToAdd] as Number, 3, "skipping two boundaries still counts all three sets");
    return true;
}

(:test)
function testCustomPresetIsLastAndWellFormed(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(
        Presets.count(),
        Presets.LIST.size() + 1,
        "custom preset extends the built-in list by one"
    );
    var q = Presets.get(Presets.count() - 1);
    var isCustom = q[:custom] as Boolean?;
    Test.assertMessage(isCustom != null, "last preset is the custom one");
    Test.assertEqualMessage(q[:sets] as Number, 4, "default custom sets");
    Test.assertEqualMessage(q[:work] as Number, 90, "default custom work seconds");
    Test.assertEqualMessage(q[:rest] as Number, 60, "default custom rest seconds");
    Test.assertEqualMessage(q[:label] as String, "4 x 1:30 | 1:00", "label derives from the custom values");
    return true;
}

(:test)
function testCustomClampKeepsValuesSane(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(Presets.clamp(0, 1, 50), 1, "clamps up to minimum");
    Test.assertEqualMessage(Presets.clamp(999, 1, 50), 50, "clamps down to maximum");
    Test.assertEqualMessage(Presets.clamp(7, 1, 50), 7, "in-range value unchanged");
    return true;
}

(:test)
function testBuiltInPresetsCarryLoopPatterns(logger as Test.Logger) as Boolean {
    // Baked patterns per the chosen mapping: the two |1:00 shapes are 4-2,
    // the others fixed. beatsB == 0 means a single uniform loop.
    var varying = Presets.get(1); // 5 x 2:00 | 1:00
    Test.assertEqualMessage(varying[:beatsA] as Number, 4, "loop A is 4");
    Test.assertEqualMessage(varying[:beatsB] as Number, 2, "5x2:00|1:00 is a 4-2");

    var fixed = Presets.get(2); // 5 x 2:00 | 2:00
    Test.assertEqualMessage(fixed[:beatsB] as Number, 0, "5x2:00|2:00 is a fixed loop");

    Test.assertEqualMessage(Presets.get(3)[:beatsB] as Number, 2, "3x2:00|1:00 is a 4-2");
    Test.assertEqualMessage(Presets.get(4)[:beatsB] as Number, 0, "10x1:00|0:30 is fixed");
    return true;
}

(:test)
function testCustomPresetCarriesPhonePattern(logger as Test.Logger) as Boolean {
    // With no phone overrides in the test harness, the pattern defaults to
    // a uniform 4-beat loop.
    var q = Presets.get(Presets.count() - 1);
    Test.assertEqualMessage(q[:beatsA] as Number, 4, "default loop A is 4");
    Test.assertEqualMessage(q[:beatsB] as Number, 0, "default is a single loop");
    return true;
}

(:test)
function testPresetsAreWellFormed(logger as Test.Logger) as Boolean {
    Test.assertMessage(Presets.LIST.size() >= 2, "at least free + one preset");
    var free = Presets.LIST[0] as Dictionary;
    Test.assertEqualMessage(free[:sets] as Number, 0, "first preset is free training");
    for (var i = 1; i < Presets.LIST.size(); i++) {
        var q = Presets.LIST[i] as Dictionary;
        Test.assertMessage((q[:sets] as Number) > 0, "preset has sets");
        Test.assertMessage((q[:work] as Number) > 0, "preset has work time");
        Test.assertMessage((q[:rest] as Number) >= 0, "preset rest is non-negative");
        var label = q[:label] as String;
        Test.assertMessage(label.length() > 0, "preset has a label");
    }
    return true;
}
