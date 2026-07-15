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
