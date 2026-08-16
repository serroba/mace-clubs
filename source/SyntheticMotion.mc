import Toybox.Lang;
import Toybox.Math;

// Deterministic, on-watch motion source used by the headless Monkey C suite.
// It deliberately lives beside the production motion pipeline: Python does
// not generate these samples or the expected workout behaviour.
(:test)
module SyntheticMotion {
    const SAMPLE_RATE = 25;
    const STYLE_STILL = 0;
    const STYLE_SMOOTH = 1;
    const STYLE_IRREGULAR = 2;
    const STYLE_SPIKE = 3;

    function styleAt(second as Number) as Number {
        if (second < 5 || second >= 25 && second < 30) {
            return STYLE_STILL;
        }
        if (second < 25) {
            return STYLE_SMOOTH;
        }
        return second == 42 ? STYLE_SPIKE : STYLE_IRREGULAR;
    }

    function isWork(second as Number) as Boolean {
        return second >= 5 && second < 25 || second >= 30;
    }

    function samples(style as Number, second as Number) as Dictionary {
        var x = new Array<Number>[SAMPLE_RATE];
        var y = new Array<Number>[SAMPLE_RATE];
        var z = new Array<Number>[SAMPLE_RATE];
        for (var i = 0; i < SAMPLE_RATE; i++) {
            var angle = 2.0 * Math.PI * i / SAMPLE_RATE;
            if (style == STYLE_STILL) {
                x[i] = 0;
                y[i] = 0;
                z[i] = 1000;
            } else if (style == STYLE_SMOOTH) {
                x[i] = (560.0 * Math.sin(angle)).toNumber();
                y[i] = (308.0 * Math.cos(angle)).toNumber();
                z[i] = (1000.0 + 123.0 * Math.sin(2.0 * angle)).toNumber();
            } else if (style == STYLE_SPIKE && i == 12) {
                x[i] = 4200;
                y[i] = -900;
                z[i] = 1600;
            } else {
                var amplitude = style == STYLE_SPIKE ? 650 : 430 + (second * 97 + i * 53) % 360;
                x[i] = (amplitude * Math.sin(angle + second * 0.17)).toNumber();
                y[i] = (amplitude * 0.7 * Math.cos(1.3 * angle)).toNumber();
                z[i] = (1000.0 + amplitude * 0.3 * Math.sin(2.4 * angle)).toNumber();
            }
        }
        return {:x => x, :y => y, :z => z};
    }

    // Run the complete 50-second scenario through Motion.processWindow(), the
    // same entry point used by WorkoutSession.onSensorData().
    function run() as Dictionary {
        var smooth = new Smoothness.Tracker();
        var irregular = new Smoothness.Tracker();
        var exposure = new LoadExposure.Tracker();
        var counter = new SwingCounter.Counter();
        var records = [] as Array<Dictionary>;
        var workSeconds = 0;
        var restSeconds = 0;
        var sessionPeak = 0;
        var spikePeak = 0;

        for (var second = 0; second < 50; second++) {
            var style = styleAt(second);
            var work = isWork(second);
            var axes = samples(style, second);
            var tracker = second >= 5 && second < 25 ? smooth : (second >= 30 ? irregular : null);
            var result = Motion.processWindow(
                axes[:x] as Array<Number>,
                axes[:y] as Array<Number>,
                axes[:z] as Array<Number>,
                tracker,
                work,
                exposure,
                work,
                counter,
                true
            );
            records.add(result);
            workSeconds += work ? 1 : 0;
            restSeconds += work ? 0 : 1;
            var peak = result[:dynamicPeak] as Number;
            if (peak > sessionPeak) {
                sessionPeak = peak;
            }
            if (style == STYLE_SPIKE) {
                spikePeak = peak;
            }
        }
        return {
            :records        => records,
            :smoothScore    => smooth.getScore(),
            :irregularScore => irregular.getScore(),
            :exposure       => exposure.getExposure(),
            :activeSeconds  => exposure.getActiveSeconds(),
            :sessionPeak    => sessionPeak,
            :spikePeak      => spikePeak,
            :swings         => counter.getCount(),
            :workSeconds    => workSeconds,
            :restSeconds    => restSeconds
        };
    }
}
