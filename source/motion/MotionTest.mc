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
    var g = Motion.features(one, empty, one);
    Test.assertEqualMessage(g[:peak] as Number, 0, "mismatched axis lengths yield zeros");
    Test.assertEqualMessage(g[:dynamicRms] as Number, 0, "bad buffers have no dynamic RMS");
    return true;
}
