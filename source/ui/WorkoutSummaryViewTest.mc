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
    // 4 aggregate pages (overview, smoothness, swings & load, balance) plus
    // one per completed set.
    Test.assertEqualMessage(view.totalPages(), 6, "4 aggregate pages plus one per completed set");
    for (var i = 0; i < view.totalPages(); i++) {
        RenderTestSupport.render(view);
        view.cyclePage(1);
    }
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
    Test.assertEqualMessage(view.totalPages(), 4, "no per-set pages without a set");
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

    view.cyclePage(2);
    Test.assertEqualMessage(view.currentLines()[1], "n/a", "balance page falls back with no side data");
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
