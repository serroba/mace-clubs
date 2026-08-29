import Toybox.Lang;
import Toybox.Test;

// Characterization tests for RecordedSwingReplay: real recorded gyro data
// replayed through the production SwingCounter, asserted against a captured
// baseline rather than true ground truth (see each RecordedFixture*'s header
// for why decimated debug-export gyro can't reproduce true on-device counts).
// If an intentional algorithm change moves these numbers, recapture the
// baseline (run `make simulator-test`, temporarily print `perSet` to read
// its new value) rather than guessing.
//
// To add another fixture to this framework: pick a gyro-capable entry from
// tools/fixtures/index.json, run
// `node --experimental-strip-types tools/export-replay-fixture.ts <id>`,
// `make format`, then add a test here following the pattern below - no
// changes to RecordedSwingReplay.mc's harness are needed for another
// SwingCounter fixture. A different watch behaviour (smoothness scoring,
// training load, ...) would want its own replay*() function alongside
// replayMace() in RecordedSwingReplay.mc, reusing the same per-second
// seconds() data (Motion.processWindow() takes the same accel/gyro shape).

// Baseline: tools/fixtures/index.json's true onDeviceDetectedPerSet =
// [2, 3, 8, 7], realSwingsPerSet = [5, 5, 10, 10].
(:test)
function testRecordedFixtureRecBMaceReplay(logger as Test.Logger) as Boolean {
    var result = RecordedSwingReplay.replayMace(RecordedFixtureRecB.seconds());
    var perSet = result.get(:perSet) as Array<Number>;
    Test.assertEqualMessage(perSet.size(), 4, "recB has 4 work sets");
    Test.assertEqualMessage(perSet[0], 5, "recB set 1 (5 real)");
    Test.assertEqualMessage(perSet[1], 5, "recB set 2 (5 real)");
    Test.assertEqualMessage(perSet[2], 8, "recB set 3 (10 real)");
    Test.assertEqualMessage(perSet[3], 7, "recB set 4 (10 real)");
    return true;
}

// Baseline: tools/fixtures/index.json's true onDeviceDetectedPerSet =
// [17, 18], realSwingsPerSet = [60, 60] - the primary slow-heavy-mace
// undercount fixture (10-to-2, two-handed). Whatever future gyro/fusion
// tuning targets this case, this test is the tripwire for "did it move".
(:test)
function testRecordedFixtureRecCMaceReplay(logger as Test.Logger) as Boolean {
    var result = RecordedSwingReplay.replayMace(RecordedFixtureRecC.seconds());
    var perSet = result.get(:perSet) as Array<Number>;
    Test.assertEqualMessage(perSet.size(), 2, "recC has 2 work sets");
    Test.assertEqualMessage(perSet[0], 36, "recC set 1 (60 real)");
    Test.assertEqualMessage(perSet[1], 48, "recC set 2 (60 real)");
    return true;
}
