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
    Test.assertMessage((q[:sets] as Number) >= 1, "configured custom set count is valid");
    Test.assertMessage((q[:work] as Number) >= 10, "configured custom work duration is valid");
    Test.assertMessage((q[:rest] as Number) >= 0, "configured custom rest duration is valid");
    Test.assertEqualMessage(
        q[:label] as String,
        Lang.format(
            "$1$ x $2$ | $3$",
            [q[:sets], Presets.mmss(q[:work] as Number), Presets.mmss(q[:rest] as Number)]
        ),
        "label derives from the configured custom values"
    );
    return true;
}

(:test)
function testChallengePresetsAreSingleRestlessIntervals(logger as Test.Logger) as Boolean {
    var found = 0;
    for (var i = 0; i < Presets.LIST.size(); i++) {
        var p = Presets.LIST[i] as Dictionary;
        if (p[:challenge] != true) {
            continue;
        }
        found++;
        Test.assertEqualMessage(p[:sets] as Number, 1, "a challenge is one continuous interval");
        Test.assertEqualMessage(p[:rest] as Number, 0, "a challenge has no rest");
        Test.assertMessage((p[:work] as Number) >= 300, "a challenge runs at least five minutes");
    }
    Test.assertEqualMessage(found, 2, "five and ten minute challenges exist");
    return true;
}

(:test)
function testPlanExposesItsConfiguredShape(logger as Test.Logger) as Boolean {
    var plan = new Intervals.Plan(5, 120, 60);
    Test.assertEqualMessage(plan.getSets(), 5, "set count");
    Test.assertEqualMessage(plan.getWorkSeconds(), 120, "work seconds");
    Test.assertEqualMessage(plan.getRestSeconds(), 60, "rest seconds");
    return true;
}

(:test)
function testZeroRestPlanRunsWorkThenFinishes(logger as Test.Logger) as Boolean {
    // The challenge shape: one work interval, no rest. The plan must hold
    // WORK for the whole window and flip straight to DONE at the boundary.
    var plan = new Intervals.Plan(1, 300, 0);
    var mid = plan.stateAt(299000);
    Test.assertEqualMessage(mid[:phase] as Number, Intervals.PHASE_WORK, "still working at 4:59");
    Test.assertEqualMessage(mid[:remaining] as Number, 1, "one second remaining at 4:59");
    var end = plan.stateAt(300000);
    Test.assertEqualMessage(end[:phase] as Number, Intervals.PHASE_DONE, "done exactly at 5:00");
    Test.assertEqualMessage(plan.completedSetsAt(300000), 1, "the single set completes");
    return true;
}

(:test)
function testCustomPresetDefaults(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(Presets.DEFAULT_CUSTOM_SETS, 5, "default custom sets");
    Test.assertEqualMessage(Presets.DEFAULT_CUSTOM_WORK_MINUTES, 2, "default custom work minutes");
    Test.assertEqualMessage(Presets.DEFAULT_CUSTOM_REST_MINUTES, 2, "default custom rest minutes");
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
