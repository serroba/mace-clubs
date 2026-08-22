import Toybox.Lang;
import Toybox.Test;

(:test)
function testMotionFeaturesOfStillWrist(logger as Test.Logger) as Boolean {
    // gravity only: constant 1000mg on one axis
    var zeros = [0, 0, 0, 0] as Array<Number>;
    var g = [1000, 1000, 1000, 1000] as Array<Number>;
    var f = Motion.features(zeros, zeros, g);
    Test.assertEqualMessage(f[:rms] as Number, 1000, "constant magnitude has rms = magnitude");
    Test.assertEqualMessage(f[:peak] as Number, 1000, "peak equals the constant magnitude");
    Test.assertEqualMessage(f[:min] as Number, 1000, "min equals the constant magnitude");
    Test.assertEqualMessage(f[:zc] as Number, 0, "no crossings when nothing moves");
    Test.assertEqualMessage(f[:dynamicRms] as Number, 0, "gravity is removed from dynamic RMS");
    Test.assertEqualMessage(f[:dynamicPeak] as Number, 0, "gravity is removed from dynamic peak");
    return true;
}

(:test)
function testMotionFeaturesOfSwing(logger as Test.Logger) as Boolean {
    // alternating hard/soft: magnitudes 1000, 3000, 1000, 3000, ...
    var zeros = [0, 0, 0, 0, 0, 0] as Array<Number>;
    var swing = [1000, 3000, 1000, 3000, 1000, 3000] as Array<Number>;
    var f = Motion.features(zeros, zeros, swing);
    Test.assertEqualMessage(f[:peak] as Number, 3000, "peak is the hard phase");
    Test.assertEqualMessage(f[:min] as Number, 1000, "min is the soft phase");
    Test.assertEqualMessage(f[:zc] as Number, 5, "each alternation crosses the mean");
    var rms = f[:rms] as Number;
    Test.assertMessage(rms > 2000 && rms < 2500, "rms sits between soft and hard magnitudes");
    Test.assertEqualMessage(f[:dynamicRms] as Number, 1000, "dynamic RMS measures variation around gravity");
    Test.assertEqualMessage(f[:dynamicPeak] as Number, 1000, "dynamic peak measures the largest deviation");
    return true;
}

(:test)
function testMotionFeaturesRejectBadBuffers(logger as Test.Logger) as Boolean {
    var empty = [] as Array<Number>;
    var one = [500] as Array<Number>;
    var f = Motion.features(empty, empty, empty);
    Test.assertEqualMessage(f[:rms] as Number, 0, "empty buffer yields zeros");
    Test.assertEqualMessage(f[:min] as Number, 0, "empty buffer has no min either");
    var g = Motion.features(one, empty, one);
    Test.assertEqualMessage(g[:peak] as Number, 0, "mismatched axis lengths yield zeros");
    Test.assertEqualMessage(g[:dynamicRms] as Number, 0, "bad buffers have no dynamic RMS");
    return true;
}

(:test)
function testGyroFeaturesOfAHold(logger as Test.Logger) as Boolean {
    // A still, near-zero rotation rate: an isometric hold, not a swing.
    var zeros = [0.0, 0.0, 0.0, 0.0] as Array<Float>;
    var tiny = [2.0, 3.0, 1.0, 2.0] as Array<Float>;
    var f = Motion.gyroFeatures(zeros, zeros, tiny);
    Test.assertEqualMessage(f[:peak] as Float, 3.0, "peak is the largest tremor sample");
    Test.assertEqualMessage(f[:min] as Float, 1.0, "min is the smallest tremor sample");
    return true;
}

(:test)
function testGyroFeaturesOfASwing(logger as Test.Logger) as Boolean {
    // A real swing rotates hard throughout, unlike a hold's near-zero rate.
    var zeros = [0.0, 0.0, 0.0, 0.0] as Array<Float>;
    var swing = [180.0, 420.0, 260.0, 500.0] as Array<Float>;
    var f = Motion.gyroFeatures(zeros, zeros, swing);
    Test.assertEqualMessage(f[:peak] as Float, 500.0, "peak is the fastest rotation in the window");
    Test.assertEqualMessage(f[:min] as Float, 180.0, "min never drops near zero mid-swing");
    var rms = f[:rms] as Float;
    Test.assertMessage(rms > 300.0, "rms reflects a sustained fast rotation");
    return true;
}

(:test)
function testGyroFeaturesRejectBadBuffers(logger as Test.Logger) as Boolean {
    var empty = [] as Array<Float>;
    var one = [5.0] as Array<Float>;
    var f = Motion.gyroFeatures(empty, empty, empty);
    Test.assertEqualMessage(f[:rms] as Float, 0.0, "empty buffer yields zeros");
    var g = Motion.gyroFeatures(one, empty, one);
    Test.assertEqualMessage(g[:peak] as Float, 0.0, "mismatched axis lengths yield zeros");
    return true;
}

(:test)
function testRawMagnitudesPreservesEverySample(logger as Test.Logger) as Boolean {
    var zeros = [0, 0, 0] as Array<Number>;
    var swing = [1000, 3000, 1800] as Array<Number>;
    var mags = Motion.rawMagnitudes(zeros, zeros, swing);
    Test.assertEqualMessage(mags.size(), 3, "one magnitude per raw sample, not one per second");
    Test.assertEqualMessage(mags[0] as Number, 1000, "first sample is preserved exactly");
    Test.assertEqualMessage(mags[1] as Number, 3000, "the peak sample is not collapsed into an aggregate");
    Test.assertEqualMessage(mags[2] as Number, 1800, "the last sample is preserved exactly");
    return true;
}

(:test)
function testRawMagnitudesRejectBadBuffers(logger as Test.Logger) as Boolean {
    var empty = [] as Array<Number>;
    var one = [500] as Array<Number>;
    Test.assertEqualMessage(
        Motion.rawMagnitudes(empty, empty, empty).size(),
        0,
        "empty buffer yields no samples"
    );
    Test.assertEqualMessage(
        Motion.rawMagnitudes(one, empty, one).size(),
        0,
        "mismatched axis lengths yield no samples"
    );
    return true;
}
