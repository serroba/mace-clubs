import Toybox.Lang;
import Toybox.Test;
// The Rhythm Score, which is the steadiness of the gaps between swings.
//
// Four tests of the model this replaced were deleted with it: they asserted
// that identical one-second acceleration windows score 100 and that doubling
// every metric scores under 30. Both were true of that model, and both are
// why it ran against effort - see docs/smoothness-physics.md.
//
// Asserted in one function rather than four because a --unit-test build
// allows 253 module-level symbols and this suite sits at the ceiling.
(:test)
function testRhythmScoresTheEvennessOfSwingGaps(logger as Test.Logger) as Boolean {
    // A metronome. Every gap identical, so there is no scatter to report.
    var steady = new SwingSeries.Tracker();
    var total = 0;
    for (var second = 0; second < 40; second++) {
        total += second % 2 == 0 ? 1 : 0;
        steady.addTotal(total);
    }
    Test.assertEqualMessage(steady.getSteadiness(), 100, "evenly spaced swings are perfect rhythm");

    // The same number of swings, raggedly spaced. Same mean gap, so a pace
    // measure could not tell these apart - which is the point of measuring
    // scatter instead.
    var ragged = new SwingSeries.Tracker();
    var raggedTotal = 0;
    var pattern = [1, 3, 1, 5, 1, 3, 1, 5, 1, 3] as Array<Number>;
    var second = 0;
    for (var i = 0; i < pattern.size(); i++) {
        second += pattern[i];
        raggedTotal++;
        for (var fill = 0; fill < pattern[i]; fill++) {
            ragged.addTotal(fill == pattern[i] - 1 ? raggedTotal : raggedTotal - 1);
        }
    }
    Test.assertMessage(
        ragged.getSteadiness() < 80,
        Lang.format("ragged spacing should score well below a metronome, got $1$", [ragged.getSteadiness()])
    );

    // Too few gaps to say anything. Three gaps is four swings.
    var sparse = new SwingSeries.Tracker();
    sparse.addTotal(1);
    sparse.addTotal(1);
    sparse.addTotal(2);
    Test.assertEqualMessage(sparse.getSteadiness(), -1, "two swings are not a rhythm");

    // A pause inside a set is not a gap in rhythm. Twenty still seconds
    // between two swings would otherwise report a rest as terrible timing.
    var paused = new SwingSeries.Tracker();
    var pausedTotal = 0;
    for (var i = 0; i < 8; i++) {
        pausedTotal += i % 2 == 0 ? 1 : 0;
        paused.addTotal(pausedTotal);
    }
    var before = paused.getGaps();
    for (var i = 0; i < 20; i++) {
        paused.addTotal(pausedTotal);
    }
    pausedTotal++;
    paused.addTotal(pausedTotal);
    Test.assertEqualMessage(paused.getGaps(), before, "a twenty-second pause adds no rhythm gap");

    // A set boundary opens a fresh span while the session keeps every gap.
    Test.assertMessage(paused.getSessionGaps() >= before, "the session span outlives the set span");
    paused.openSpan();
    Test.assertEqualMessage(paused.getGaps(), 0, "a new set starts with no gaps of its own");
    Test.assertMessage(paused.getSessionGaps() > 0, "opening a set does not clear the session");
    return true;
}

(:test)
function testSetSummaryTracksOpenState(logger as Test.Logger) as Boolean {
    var summaries = new SmoothnessSetSummaries();
    Test.assertMessage(!summaries.isOpen(), "nothing is open before the first work phase");
    summaries.begin();
    Test.assertMessage(summaries.isOpen(), "begin opens a set window");
    summaries.complete(100, 1);
    Test.assertMessage(!summaries.isOpen(), "complete closes the set window");
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
    var summaries = new SmoothnessSetSummaries();
    summaries.begin();
    summaries.complete(64, 40);
    summaries.begin();
    summaries.complete(51, 30);
    Test.assertEqualMessage(summaries.count(), 2, "one summary per completed set");
    Test.assertEqualMessage(summaries.score(0), 64, "a set keeps the score it was handed");
    Test.assertEqualMessage(summaries.windows(0), 40, "and the sample count behind it");
    Test.assertEqualMessage(summaries.score(1), 51, "the next set is scored independently");
    return true;
}

(:test)
function testSetSummaryRejectsShortSet(logger as Test.Logger) as Boolean {
    var sets = new SmoothnessSetSummaries();
    sets.begin();
    sets.complete(180, 2);

    Test.assertEqualMessage(sets.count(), 1, "short completed set is retained");
    Test.assertEqualMessage(sets.score(0), -1, "fewer than three gaps is not a rhythm");
    Test.assertEqualMessage(sets.windows(0), 2, "short set keeps its observed window count");
    return true;
}

(:test)
function testSetSummaryCompletesBoundaryOnce(logger as Test.Logger) as Boolean {
    var sets = new SmoothnessSetSummaries();
    sets.begin();
    sets.complete(360, 4);
    sets.complete(720, 8);

    Test.assertEqualMessage(sets.count(), 1, "duplicate completion does not invent another set");
    return true;
}

(:test)
function testSetSummaryPreservesMissingBoundary(logger as Test.Logger) as Boolean {
    var sets = new SmoothnessSetSummaries();
    sets.begin();
    sets.complete(360, 4);
    sets.completeMissing();

    Test.assertEqualMessage(sets.count(), 2, "missing boundary preserves the set number");
    Test.assertEqualMessage(sets.score(1), -1, "missing boundary does not invent a score");
    Test.assertEqualMessage(sets.windows(1), 0, "missing boundary has no confidence samples");
    return true;
}
