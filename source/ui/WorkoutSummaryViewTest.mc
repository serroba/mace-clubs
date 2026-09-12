import Toybox.Lang;
import Toybox.Test;

(:test)
function testWorkoutSummaryPagesCoverAggregatesAndEverySet(logger as Test.Logger) as Boolean {
    var workout = new WorkoutSession();
    workout.selectWorkingSide(Movement.SIDE_LEFT);
    workout.addSetWithDuration(120);
    workout.endRestLapWithDuration(60);
    workout.addSetWithDuration(90);
    var view = new WorkoutSummaryView(workout);
    // Overview, rhythm, load, and balance - the sets were worked on a named
    // side, so balance has something to report - plus one page per completed
    // set. No set chart: nothing counted swings here, so its twelve bars
    // would all be zero.
    Test.assertEqualMessage(view.totalPages(), 6, "4 aggregate pages plus one per completed set");
    for (var i = 0; i < view.totalPages(); i++) {
        RenderTestSupport.render(view);
        view.cyclePage(1);
    }

    // The two aggregate pages a session has to earn, asserted here rather
    // than in a test function of their own: a --unit-test build allows 253
    // module-level symbols and this suite is at the ceiling - adding one more
    // fails the build on venusq and fenix5 with "Found 254 members in module
    // 'globals'". See LayoutTest for the same constraint and the same answer.
    //
    // Balance reports left/right set counts, and a two-handed session has
    // none: a real 12-set club workout drew "BALANCE / n/a / 0 left 0 right"
    // as page 4 of 16, and would draw it for every session that athlete ever
    // records. The set chart is the opposite - it appears only once there are
    // sets worth comparing and something counted them.
    var twoHanded = new WorkoutSession();
    twoHanded.selectWorkingSide(Movement.SIDE_TWO_HANDED);
    twoHanded.addSetWithDuration(120);
    twoHanded.addSetWithDuration(120);
    var plain = new WorkoutSummaryView(twoHanded);
    // Overview, rhythm, load, two sets. No balance, and no chart without
    // counted swings.
    Test.assertEqualMessage(plain.totalPages(), 5, "a two-handed session spends no page on balance");
    for (var i = 0; i < plain.totalPages(); i++) {
        RenderTestSupport.render(plain);
        Test.assertMessage(!plain.currentLines()[0].equals("BALANCE"), "no balance page to land on");
        plain.cyclePage(1);
    }

    // The same session with swings recorded against each set earns the chart.
    var counted = new WorkoutSession();
    counted.selectWorkingSide(Movement.SIDE_TWO_HANDED);
    counted.addSetWithDuration(120);
    counted.addSetWithDuration(120);
    (counted.getBlock(0) as WorkBlockSummary).setSwings(67);
    (counted.getBlock(1) as WorkBlockSummary).setSwings(46);
    var charted = new WorkoutSummaryView(counted);
    // Five pages plus the chart, where this build has one: the 96KB watches
    // compile it out, so the count follows the build rather than a literal.
    Test.assertEqualMessage(
        charted.totalPages(),
        5 + RenderTestSupport.chartPages(),
        "counted swings earn the set chart"
    );
    charted.cyclePage(1);
    var lines = charted.currentLines();
    if (RenderTestSupport.chartPages() == 1) {
        Test.assertEqualMessage(lines[0], "SETS", "the chart sits directly after the overview");
        // The caption carries the range, since the bars are unlabelled.
        Test.assertEqualMessage(lines[3], "46-67 per set", "the caption gives the bars a scale");
    } else {
        Test.assertMessage(!lines[0].equals("SETS"), "a build without the chart has no chart page");
    }
    RenderTestSupport.render(charted);
    return true;
}

(:test)
function testWorkoutSummaryPagingWraps(logger as Test.Logger) as Boolean {
    var workout = new WorkoutSession();
    workout.addSetWithDuration(60);
    var view = new WorkoutSummaryView(workout);
    var count = view.totalPages();
    view.cyclePage(-1);
    RenderTestSupport.render(view);
    view.cyclePage(count);
    RenderTestSupport.render(view);
    return true;
}

(:test)
function testWorkoutSummaryHandlesAZeroSetSession(logger as Test.Logger) as Boolean {
    // Reachable via BACK-then-SELECT before completing any set.
    var workout = new WorkoutSession();
    var view = new WorkoutSummaryView(workout);
    // Overview, rhythm and load. A session with no sets has no sides to
    // balance and no sets to chart, and neither page is worth a press to
    // read "n/a".
    Test.assertEqualMessage(view.totalPages(), 3, "no per-set pages without a set");
    RenderTestSupport.render(view);
    return true;
}

(:test)
function testWorkoutSummaryFallbackTextRendersWithNoData(logger as Test.Logger) as Boolean {
    // With no smoothness/side data, the fallback text must actually be the
    // line drawn - not silently blank. (Monkey C's == on String is reference
    // equality, not content equality; a x == "" fallback check is always
    // false even when x is genuinely empty.)
    var workout = new WorkoutSession();
    workout.addSetWithDuration(60);
    var view = new WorkoutSummaryView(workout);

    view.cyclePage(1);
    Test.assertEqualMessage(
        view.currentLines()[1],
        "not enough motion",
        "smoothness page falls back with no data"
    );

    // The balance page had a fallback here too - "n/a" when no set was worked
    // on a named side. It has no page to appear on now: a session with no
    // side data does not earn one, which is the point. What replaces this
    // assertion is the one above, that such a session never lands on BALANCE.
    return true;
}

(:test)
function testWorkoutSummaryDelegateRoutesPaging(logger as Test.Logger) as Boolean {
    var workout = new WorkoutSession();
    workout.addSetWithDuration(60);
    workout.addSetWithDuration(60);
    var view = new WorkoutSummaryView(workout);
    var delegate = new WorkoutSummaryDelegate(view);
    var start = view.totalPages();
    delegate.onNextPage();
    delegate.onNextPage();
    delegate.onPreviousPage();
    Test.assertMessage(view.totalPages() == start, "paging never changes the page count");
    return true;
}

(:test)
function testWorkoutSessionSaveIsSafeWithoutASession(logger as Test.Logger) as Boolean {
    var workout = new WorkoutSession();
    workout.save();
    Test.assertMessage(!workout.isStarted(), "save without a live session is a safe no-op");
    return true;
}
