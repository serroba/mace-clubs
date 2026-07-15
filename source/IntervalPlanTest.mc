import Toybox.Lang;
import Toybox.Test;

// Plan under test: 5 sets x 2:00 work, 1:00 rest (cycle = 180s).
// Last set has no trailing rest; the plan is DONE when its work ends
// (4 * 180 + 120 = 840s).

(:test)
function testPlanStartsInWorkSet1(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(0);
    Test.assertEqualMessage(s[:phase], Intervals.PHASE_WORK, "starts in WORK");
    Test.assertEqualMessage(s[:set], 1, "starts on set 1");
    Test.assertEqualMessage(s[:remaining], 120, "full work remaining");
    return true;
}

(:test)
function testWorkCountsDown(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(119000);
    Test.assertEqualMessage(s[:phase], Intervals.PHASE_WORK, "still WORK at 1:59");
    Test.assertEqualMessage(s[:remaining], 1, "one second left");
    return true;
}

(:test)
function testRestBeginsWhenWorkEnds(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(120000);
    Test.assertEqualMessage(s[:phase], Intervals.PHASE_REST, "REST at 2:00");
    Test.assertEqualMessage(s[:set], 1, "rest belongs to set 1");
    Test.assertEqualMessage(s[:remaining], 60, "full rest remaining");
    return true;
}

(:test)
function testNextSetBeginsAfterRest(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(180000);
    Test.assertEqualMessage(s[:phase], Intervals.PHASE_WORK, "WORK at 3:00");
    Test.assertEqualMessage(s[:set], 2, "set 2 after first rest");
    return true;
}

(:test)
function testLastSetHasNoTrailingRest(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(839000);
    Test.assertEqualMessage(s[:phase], Intervals.PHASE_WORK, "WORK just before the end");
    Test.assertEqualMessage(s[:set], 5, "on final set");
    var d = p.stateAt(840000);
    Test.assertEqualMessage(d[:phase], Intervals.PHASE_DONE, "DONE when last work ends");
    return true;
}

(:test)
function testDoneStaysDone(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(5, 120, 60);
    var s = p.stateAt(9999000);
    Test.assertEqualMessage(s[:phase], Intervals.PHASE_DONE, "DONE long after the end");
    Test.assertEqualMessage(s[:set], 5, "set count capped at plan size");
    return true;
}

(:test)
function testZeroRestPlanChainsSets(logger as Test.Logger) as Boolean {
    var p = new Intervals.Plan(3, 60, 0);
    var s = p.stateAt(60000);
    Test.assertEqualMessage(s[:phase], Intervals.PHASE_WORK, "no rest phase when rest is 0");
    Test.assertEqualMessage(s[:set], 2, "straight into set 2");
    var d = p.stateAt(180000);
    Test.assertEqualMessage(d[:phase], Intervals.PHASE_DONE, "done after 3 x 60s");
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
function testPresetsAreWellFormed(logger as Test.Logger) as Boolean {
    Test.assertMessage(Presets.LIST.size() >= 2, "at least free + one preset");
    var free = Presets.LIST[0] as Dictionary;
    Test.assertEqualMessage(free[:sets], 0, "first preset is free training");
    for (var i = 1; i < Presets.LIST.size(); i++) {
        var q = Presets.LIST[i] as Dictionary;
        Test.assertMessage((q[:sets] as Number) > 0, "preset has sets");
        Test.assertMessage((q[:work] as Number) > 0, "preset has work time");
        Test.assertMessage((q[:rest] as Number) >= 0, "preset rest is non-negative");
        Test.assertMessage(q[:label] != null, "preset has a label");
    }
    return true;
}
