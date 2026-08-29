import Toybox.Lang;

// Feeds a recorded fixture's real per-second gyroscope samples through the
// actual production SwingCounter.maceCounter() - the same class
// WorkoutSession.onSensorData drives live. This is a characterization
// harness, not a live-accuracy oracle: see e.g. RecordedFixtureRecB's header
// for why replaying decimated debug-export gyro can't reproduce the true
// on-device count. Its purpose is narrower and still useful - does an
// algorithm change move the count computed against this real recording?
(:test)
module RecordedSwingReplay {
    // seconds: one Dictionary per second in chronological order, each with
    // :workOpen (Boolean) and :gyroX/:gyroY/:gyroZ (Array<Float>, deg/s) -
    // see RecordedFixtureRecB.seconds() for the concrete shape and
    // tools/export-replay-fixture.ts for how it's generated from a real FIT
    // fixture in tools/fixtures/index.json.
    //
    // Returns {:perSet => Array<Number>, :total => Number}: perSet is the
    // swing count accrued during each contiguous work span, in order.
    function replayMace(seconds as Array<Dictionary>) as Dictionary {
        return replayWithCounter(seconds, SwingCounter.maceCounter());
    }

    // Same replay, but against a caller-supplied Counter - lets
    // SwingTuningSearch try candidate gyro parameters (see
    // SwingCounter.maceCounterWithGyroParams()) without a second
    // implementation of this loop.
    function replayWithCounter(seconds as Array<Dictionary>, counter as SwingCounter.Counter) as Dictionary {
        var perSet = [] as Array<Number>;
        var setStartCount = 0;
        var wasWorkOpen = false;
        for (var i = 0; i < seconds.size(); i += 1) {
            var second = seconds[i];
            var workOpen = second.get(:workOpen) as Boolean;
            if (workOpen && !wasWorkOpen) {
                setStartCount = counter.getCount();
            }
            counter.addGyroSamples(
                second.get(:gyroX) as Array<Float>,
                second.get(:gyroY) as Array<Float>,
                second.get(:gyroZ) as Array<Float>,
                workOpen
            );
            if (!workOpen && wasWorkOpen) {
                perSet.add(counter.getCount() - setStartCount);
            }
            wasWorkOpen = workOpen;
        }
        // The recording can end mid-work if the last set has no trailing
        // rest lap - close it out the same way a rest transition would.
        if (wasWorkOpen) {
            perSet.add(counter.getCount() - setStartCount);
        }
        return {:perSet => perSet, :total => counter.getCount()} as Dictionary;
    }
}
