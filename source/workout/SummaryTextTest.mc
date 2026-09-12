import Toybox.Lang;
import Toybox.Test;

// The per-set lines the summary and history screens read out of a finished
// session.
//
// Nothing tested these. They are pure functions over a WorkoutSession - the
// easiest thing in the app to check - and they were covered only by the e2e
// suite taking a screenshot of a screen that happened to call them, which
// tells you the text drew, not that it says the right thing.
//
// One test function, deliberately. A --unit-test build may define at most
// 253 module-level symbols and this suite runs close to that on
// venusq/instinct2/fenix5 (see LayoutTest for the full note), so a file of
// small test functions would spend a budget measured in single figures.
//
// String equality goes through .equals(): Monkey C's == on Strings is
// reference equality, so `x == ""` is false even for an empty string. That
// is the bug SummaryText's own comment warns about, and asserting with ==
// here would reproduce it.
(:test)
function testSummaryTextReadsEachSetLine(logger as Test.Logger) as Boolean {
    var workout = new WorkoutSession();

    // An index with no block behind it. Every one of these is asked for a set
    // that may not exist - the summary screen pages past the end - so the
    // empty answer is the common case, not an edge case.
    Test.assertMessage(SummaryText.side(workout, 0).equals(""), "no block, no side");
    Test.assertMessage(SummaryText.swings(workout, 0).equals(""), "no block, no swing count");
    Test.assertMessage(SummaryText.load(workout, 0).equals(""), "no block, no load");
    Test.assertMessage(SummaryText.detail(workout, 0).equals(""), "no block, no detail line");

    // A real set. addSetWithDuration is what closes a work block, so this is
    // the same object the summary screen would be reading.
    workout.selectEquipment(Equipment.TYPE_MACE, 1);
    workout.selectWorkingSide(Movement.SIDE_LEFT);
    workout.addSetWithDuration(60);

    var block = workout.getBlock(0);
    Test.assertMessage(block != null, "a completed set leaves a block to summarise");
    Test.assertEqualMessage(
        SummaryText.side(workout, 0),
        Movement.sideShortLabel(Movement.SIDE_LEFT),
        "the side line names the side the set was worked on"
    );

    // Swings are only counted when the counter is running, and it is not here.
    // -1 means "not measured" and has to read as blank rather than as zero
    // swings, which is a different claim.
    Test.assertMessage(SummaryText.swings(workout, 0).equals(""), "an unmeasured set claims no swings");

    (block as WorkBlockSummary).setSwings(12);
    Test.assertEqualMessage(SummaryText.swings(workout, 0), "12 sw", "a measured set reports its swings");

    // Smoothness is indexed separately from the blocks - it only exists for
    // sets recorded while the sensor was on - so an index past the end of
    // that list is blank rather than a score of zero.
    Test.assertMessage(
        SummaryText.smoothness(workout, workout.getSetSmoothnessCount()).equals(""),
        "no score past the end of the smoothness log"
    );

    // Zero exposure means the sensor saw no active window, which is not a
    // measurement of no load.
    (block as WorkBlockSummary).setLoadExposure(0, 0, 0);
    Test.assertMessage(SummaryText.load(workout, 0).equals(""), "zero exposure is not a load reading");
    (block as WorkBlockSummary).setLoadExposure(12400, 90, 45);
    Test.assertEqualMessage(
        SummaryText.load(workout, 0),
        LoadExposure.compactLabel(12400),
        "a real exposure reports the compact label"
    );

    // The joined line. With load present the tokens go compact so all three
    // fit a 176px screen: "12sw ... L12.4k" rather than "12 sw".
    var detail = SummaryText.detail(workout, 0);
    Test.assertMessage(detail.find("12sw") != null, "the detail line carries the compact swing count");
    Test.assertMessage(
        detail.find(LoadExposure.compactLabel(12400)) != null,
        "the detail line carries the load token"
    );
    return true;
}
