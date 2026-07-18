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
