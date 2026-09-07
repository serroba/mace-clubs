import Toybox.Lang;
import Toybox.Test;

// FitFields only touches real FitContributor.Field objects once a live
// recording session created them, so every write path must be a safe no-op
// beforehand. The live-session write paths are covered in the simulator.

(:test)
function testFitFieldsWritesAreSafeWithoutASession(logger as Test.Logger) as Boolean {
    var fields = new FitFields();
    Test.assertMessage(!fields.hasLapFields(), "no lap fields before a session exists");
    var block = new WorkBlockSummary(
        1,
        60,
        Movement.TYPE_360,
        Movement.SIDE_TWO_HANDED,
        Equipment.TYPE_MACE,
        1,
        4000,
        0,
        75
    );
    fields.writeSets(1);
    FitFieldsTestSupport.motionExportWrites(fields);
    fields.writeSwingPoint(10, 1, 60);
    fields.writeLapBoundary(1, 1, block);
    fields.writeLapBoundary(0, 0, block);
    fields.prepareOpenLap(1);
    fields.writeSessionSummary(Equipment.TYPE_MACE, 1, 4000, 0, 120, 60, "Mace");
    fields.writeBatteryUsed(1.5);
    fields.writeSwingTotal(37);
    fields.clearLoadExposureFields();
    fields.reset();
    Test.assertMessage(!fields.hasLapFields(), "reset leaves no lap fields behind");
    return true;
}

// The motion-export writers are compiled out on the Instinct 2 family (see
// the jungles), so the safe-without-a-session check has to reach them
// through a pair like every other caller does rather than naming them
// directly - the symbols are not there to name.
//
// In a module, not as loose (:test) functions: the test runner treats every
// (:test) function as a test entry and calls it with no arguments, which is
// how the first attempt at this turned a helper into a failing test.
(:test)
module FitFieldsTestSupport {
    (:motionExport)
    function motionExportWrites(fields as FitFields) as Void {
        fields.writeMotionFeatures(1000, 2000, 300);
        fields.writeRecordSmoothness(80);
        fields.writeRecordSmoothness(-1);
    }

    (:noMotionExport)
    function motionExportWrites(fields as FitFields) as Void {}
}
