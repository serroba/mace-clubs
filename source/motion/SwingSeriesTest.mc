import Toybox.Lang;
import Toybox.Test;

(:test)
function testSwingSeriesTracksEventsTotalAndRollingCadence(logger as Test.Logger) as Boolean {
    var tracker = new SwingSeries.Tracker();
    var first = tracker.addTotal(0);
    var second = tracker.addTotal(1);
    var third = tracker.addTotal(1);
    Test.assertEqualMessage(first[:event] as Number, 0, "no initial event");
    Test.assertEqualMessage(second[:total] as Number, 1, "cumulative count is retained");
    Test.assertEqualMessage(second[:event] as Number, 1, "new swing becomes an event");
    Test.assertEqualMessage(second[:cadence] as Number, 30, "two-second cadence is normalized");
    Test.assertEqualMessage(third[:cadence] as Number, 20, "idle second lowers rolling cadence");
    return true;
}

// The eviction path only runs once more than WINDOW_SECONDS records exist, and
// no test above reached it - which is how a by-value Array.remove(0) shipped a
// corrupted rolling sum in every recording. Every input here is 0 or 1, so a
// cadence above 60 spm is arithmetically impossible.
(:test)
function testSwingSeriesRollingWindowEvictsTheOldestSecond(logger as Test.Logger) as Boolean {
    var tracker = new SwingSeries.Tracker();
    var total = 0;
    var worst = 0;
    for (var i = 0; i < 30; i += 1) {
        total += 1;
        var cadence = tracker.addTotal(total)[:cadence] as Number;
        if (cadence > worst) {
            worst = cadence;
        }
    }
    Test.assertEqualMessage(worst, 60, "one swing per second is 60 spm and never more");

    var idle = 0;
    for (var i = 0; i < 30; i += 1) {
        idle = tracker.addTotal(total)[:cadence] as Number;
    }
    Test.assertEqualMessage(idle, 0, "the window drains to zero when swinging stops");

    var alternating = new SwingSeries.Tracker();
    var altTotal = 0;
    var last = 0;
    for (var i = 0; i < 40; i += 1) {
        if (i % 2 == 0) {
            altTotal += 1;
        }
        last = alternating.addTotal(altTotal)[:cadence] as Number;
    }
    Test.assertEqualMessage(last, 30, "one swing every two seconds is 30 spm");
    return true;
}

(:test)
function testSwingSeriesCorrectionDoesNotInventAnEvent(logger as Test.Logger) as Boolean {
    var tracker = new SwingSeries.Tracker();
    tracker.addTotal(3);
    tracker.align(4);
    var point = tracker.addTotal(4);
    Test.assertEqualMessage(point[:event] as Number, 0, "manual correction is not a detected swing");
    return true;
}
