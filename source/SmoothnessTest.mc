import Toybox.Lang;
import Toybox.Test;

function smoothFeatures(rms as Number, peak as Number, crossings as Number) as Dictionary {
    return {:dynamicRms => rms, :dynamicPeak => peak, :zc => crossings};
}

(:test)
function testSmoothnessStableWindowsScoreOneHundred(logger as Test.Logger) as Boolean {
    var tracker = new Smoothness.Tracker();
    for (var i = 0; i < 5; i++) {
        tracker.add(smoothFeatures(500, 900, 4));
    }
    Test.assertEqualMessage(tracker.getScoredWindows(), 1, "four windows warm up before scoring");
    Test.assertEqualMessage(tracker.getScore(), 100, "identical motion windows are fully repeatable");
    return true;
}

(:test)
function testSmoothnessRejectsStillWindows(logger as Test.Logger) as Boolean {
    var tracker = new Smoothness.Tracker();
    for (var i = 0; i < 8; i++) {
        Test.assertMessage(!tracker.add(smoothFeatures(10, 20, 0)), "still window is ignored");
    }
    Test.assertEqualMessage(tracker.getScoredWindows(), 0, "stillness never becomes a scored swing");
    Test.assertEqualMessage(tracker.getScore(), -1, "no score is shown without enough movement");
    return true;
}

(:test)
function testSmoothnessPenalizesDifferentEffortAndTiming(logger as Test.Logger) as Boolean {
    var tracker = new Smoothness.Tracker();
    for (var i = 0; i < 4; i++) {
        tracker.add(smoothFeatures(500, 900, 4));
    }
    tracker.add(smoothFeatures(1000, 1800, 8));
    Test.assertMessage(tracker.getScore() < 30, "doubling every motion metric scores as inconsistent");
    return true;
}

(:test)
function testSmoothnessHistoryKeepsLatestTwelveSessions(logger as Test.Logger) as Boolean {
    var history = [] as Array<Number>;
    for (var i = 0; i < 14; i++) {
        history = Smoothness.appendSummary(history, 60 + i, 20 + i);
    }
    Test.assertEqualMessage(history.size(), 24, "twelve score/window pairs are retained");
    Test.assertEqualMessage(history[0], 62, "oldest two sessions are discarded");
    Test.assertEqualMessage(history[22], 73, "latest session is retained");
    Test.assertEqualMessage(history[23], 33, "scored-window count travels with the score");
    return true;
}

(:test)
function testSetSummaryUsesCumulativeSnapshotDifference(logger as Test.Logger) as Boolean {
    var sets = new SmoothnessSetSummaries();
    sets.begin(0, 0);
    sets.complete(360, 4);
    sets.begin(360, 4);
    sets.complete(600, 7);

    Test.assertEqualMessage(sets.count(), 2, "two completed boundaries create two summaries");
    Test.assertEqualMessage(sets.score(0), 90, "first set averages its four scored windows");
    Test.assertEqualMessage(sets.windows(0), 4, "first set retains its confidence count");
    Test.assertEqualMessage(sets.score(1), 80, "second set uses only the cumulative difference");
    Test.assertEqualMessage(sets.windows(1), 3, "second set excludes earlier windows");
    return true;
}

(:test)
function testSetSummaryRejectsShortSet(logger as Test.Logger) as Boolean {
    var sets = new SmoothnessSetSummaries();
    sets.begin(0, 0);
    sets.complete(180, 2);

    Test.assertEqualMessage(sets.count(), 1, "short completed set is retained");
    Test.assertEqualMessage(sets.score(0), -1, "fewer than three scored seconds is not enough motion");
    Test.assertEqualMessage(sets.windows(0), 2, "short set keeps its observed window count");
    return true;
}

(:test)
function testSetSummaryExcludesClosedRestWindow(logger as Test.Logger) as Boolean {
    var sets = new SmoothnessSetSummaries();
    sets.begin(0, 0);
    sets.complete(360, 4);
    sets.begin(460, 5);
    sets.complete(730, 8);

    Test.assertEqualMessage(sets.score(1), 90, "new baseline excludes samples accumulated while closed");
    return true;
}

(:test)
function testSetSummaryCompletesBoundaryOnce(logger as Test.Logger) as Boolean {
    var sets = new SmoothnessSetSummaries();
    sets.begin(0, 0);
    sets.complete(360, 4);
    sets.complete(720, 8);

    Test.assertEqualMessage(sets.count(), 1, "duplicate completion does not invent another set");
    return true;
}

(:test)
function testSetSummaryPreservesMissingBoundary(logger as Test.Logger) as Boolean {
    var sets = new SmoothnessSetSummaries();
    sets.begin(0, 0);
    sets.complete(360, 4);
    sets.completeMissing();

    Test.assertEqualMessage(sets.count(), 2, "missing boundary preserves the set number");
    Test.assertEqualMessage(sets.score(1), -1, "missing boundary does not invent a score");
    Test.assertEqualMessage(sets.windows(1), 0, "missing boundary has no confidence samples");
    return true;
}
