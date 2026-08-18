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

(:test)
function testSwingSeriesCorrectionDoesNotInventAnEvent(logger as Test.Logger) as Boolean {
    var tracker = new SwingSeries.Tracker();
    tracker.addTotal(3);
    tracker.align(4);
    var point = tracker.addTotal(4);
    Test.assertEqualMessage(point[:event] as Number, 0, "manual correction is not a detected swing");
    return true;
}
