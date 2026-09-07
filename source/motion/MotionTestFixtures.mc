import Toybox.Application.Storage;
import Toybox.Lang;

// Synthetic sensor seconds and stored-record fixtures shared by the motion
// suites, in a module rather than as loose functions for the same reason
// RenderTestSupport is one: a --unit-test build may define at most 253
// module-level symbols, a module spends one of them however many members it
// holds, and venusq/fenix5/fr55 were failing to build at 255. Being (:test)
// also keeps them out of release builds, which loose top-level helpers in a
// *Test.mc file are not - they were being compiled into every watch.
(:test)
module MotionTestFixtures {
    function smoothFeatures(rms as Number, peak as Number, crossings as Number) as Dictionary {
        return {:dynamicRms => rms, :dynamicPeak => peak, :zc => crossings};
    }

    // Builds one axis of a synthetic 25Hz second: baseline samples with a
    // spike of the given magnitude at the given index. The other axes stay 0
    // so the sample magnitude equals the axis value.
    function swingTestSecond(spikeAt as Number, spikeMg as Number, baselineMg as Number) as Array<Number> {
        var samples = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
        for (var i = 0; i < samples.size(); i++) {
            samples[i] = i == spikeAt ? spikeMg : baselineMg;
        }
        return samples;
    }

    function swingTestZeros() as Array<Number> {
        var samples = new Array<Number>[SwingCounter.SAMPLE_RATE_HZ];
        for (var i = 0; i < samples.size(); i++) {
            samples[i] = 0;
        }
        return samples;
    }

    function gyroTestAxis(rate as Float) as Array<Float> {
        var samples = new Array<Float>[SwingCounter.SAMPLE_RATE_HZ];
        for (var i = 0; i < samples.size(); i++) {
            samples[i] = rate;
        }
        return samples;
    }

    function trainingLoadTestRecord(epoch as Number, exposure as Number) as Array<Storage.ValueType> {
        var block = new WorkBlockSummary(
            1,
            180,
            Movement.TYPE_360,
            Movement.SIDE_TWO_HANDED,
            Equipment.TYPE_MACE,
            1,
            4000,
            0,
            60
        );
        block.setLoadExposure(exposure, 2000, 120);
        var rec = SmoothnessLog.record(
            epoch,
            Equipment.TYPE_MACE,
            1,
            4000,
            Movement.TYPE_360,
            Movement.SIDE_TWO_HANDED,
            60,
            [60]
        );
        return SmoothnessLog.withDetails(rec, 180, 60, [block]);
    }
}
