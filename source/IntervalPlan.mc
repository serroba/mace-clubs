import Toybox.Application;
import Toybox.Lang;

// Interval training plans: N sets of work with rest in between.
// State is derived purely from the FIT timer time, so pausing the
// session (which freezes the timer) freezes the plan for free.
module Intervals {
    const PHASE_WORK = 0;
    const PHASE_REST = 1;
    const PHASE_DONE = 2;

    // Whole seconds to show during a deadline-based countdown. Rounding up
    // keeps "5" visible immediately after a five-second countdown starts.
    function countdownSeconds(nowMs as Number, deadlineMs as Number) as Number {
        var remaining = deadlineMs - nowMs;
        if (remaining <= 0) {
            return 0;
        }
        return (remaining + 999) / 1000;
    }

    // Warn once when an interval plan enters the final five seconds before
    // another work set. <= 5 tolerates a delayed one-second UI refresh.
    function shouldWarnNextWork(
        phase as Number,
        remaining as Number,
        set as Number,
        totalSets as Number,
        warnedSet as Number
    ) as Boolean {
        return phase == PHASE_REST && remaining > 0 && remaining <= 5 && set < totalSets && set != warnedSet;
    }

    class Plan {
        private var _sets as Number;
        private var _workSecs as Number;
        private var _restSecs as Number;

        function initialize(sets as Number, workSecs as Number, restSecs as Number) {
            _sets = sets;
            _workSecs = workSecs;
            _restSecs = restSecs;
        }

        function getSets() as Number {
            return _sets;
        }

        // Phase, 1-based set number, and seconds remaining in the phase
        // at the given timer time. The last set has no trailing rest.
        function stateAt(timerMs as Number) as Dictionary {
            var t = timerMs / 1000;
            var cycle = _workSecs + _restSecs;
            var set = t / cycle;
            var within = t - set * cycle;

            if (set >= _sets || set == _sets - 1 && within >= _workSecs) {
                return {:phase => PHASE_DONE, :set => _sets, :remaining => 0};
            }
            if (within < _workSecs) {
                return {:phase => PHASE_WORK, :set => set + 1, :remaining => _workSecs - within};
            }
            return {:phase => PHASE_REST, :set => set + 1, :remaining => cycle - within};
        }

        // Number of fully completed work intervals at the given timer time.
        function completedSetsAt(timerMs as Number) as Number {
            var s = stateAt(timerMs);
            var phase = s[:phase] as Number;
            var set = s[:set] as Number;
            if (phase == PHASE_DONE) {
                return _sets;
            }
            if (phase == PHASE_REST) {
                return set;
            }
            return set - 1;
        }
    }
}

// Workout shapes shown on the idle screen. :sets == 0 is free training
// (no interval plan, manual set marking). The last slot is the Custom
// preset, built from phone-editable app settings on every read.
//
// Each preset also carries its own metronome loop pattern: :beatsA is
// the loop length and :beatsB the optional second loop (0 = single,
// uniform loop; >0 = a varying A-B pattern like the club 4-2). Built-in
// shapes bake a sensible pattern; Free training and Custom take theirs
// from the phone (beatsPerRound / beatsPerRound2) so there is always a
// fully tunable slot.
module Presets {
    const LIST = [
        {:label => "Free training", :sets => 0, :work => 0, :rest => 0, :beatsA => 4, :beatsB => 0},
        {:label => "5 x 2:00 | 1:00", :sets => 5, :work => 120, :rest => 60, :beatsA => 4, :beatsB => 2},
        {:label => "5 x 2:00 | 2:00", :sets => 5, :work => 120, :rest => 120, :beatsA => 4, :beatsB => 0},
        {:label => "3 x 2:00 | 1:00", :sets => 3, :work => 120, :rest => 60, :beatsA => 4, :beatsB => 2},
        {:label => "10 x 1:00 | 0:30", :sets => 10, :work => 60, :rest => 30, :beatsA => 4, :beatsB => 0}
    ] as Array<Dictionary>;

    function count() as Number {
        return LIST.size() + 1;
    }

    function get(index as Number) as Dictionary {
        if (index < LIST.size()) {
            var p = LIST[index] as Dictionary;
            // Free training has no fixed shape, so its pattern comes from
            // the phone like Custom's does, not from the baked placeholder.
            if ((p[:sets] as Number) == 0) {
                var pat = phonePattern();
                return {
                    :label  => p[:label],
                    :sets   => 0,
                    :work   => 0,
                    :rest   => 0,
                    :beatsA => pat[0],
                    :beatsB => pat[1]
                };
            }
            return p;
        }
        return custom();
    }

    // Loop pattern from the phone settings, clamped: [loopA, loopB] with
    // loopB == 0 meaning a single uniform loop.
    function phonePattern() as Array<Number> {
        var a = 4;
        var b = 0;
        try {
            var bpr = Application.Properties.getValue("beatsPerRound");
            if (bpr instanceof Number) {
                a = clamp(bpr, 1, 16);
            }
            var bpr2 = Application.Properties.getValue("beatsPerRound2");
            if (bpr2 instanceof Number) {
                b = clamp(bpr2, 0, 16);
            }
        } catch (e) {}
        return [a, b] as Array<Number>;
    }

    // The Custom preset reads customSets / customWorkSecs / customRestSecs
    // from app settings (Garmin Connect on the phone), clamped to sane
    // ranges; defaults apply when a key is missing.
    function custom() as Dictionary {
        var sets = 4;
        var work = 90;
        var rest = 60;
        try {
            var s = Application.Properties.getValue("customSets");
            if (s instanceof Number) {
                sets = clamp(s, 1, 50);
            }
            var wk = Application.Properties.getValue("customWorkSecs");
            if (wk instanceof Number) {
                work = clamp(wk, 10, 3600);
            }
            var r = Application.Properties.getValue("customRestSecs");
            if (r instanceof Number) {
                rest = clamp(r, 0, 3600);
            }
        } catch (e) {}
        var pat = phonePattern();
        return {
            :label  => Lang.format("$1$ x $2$ | $3$", [sets, mmss(work), mmss(rest)]),
            :sets   => sets,
            :work   => work,
            :rest   => rest,
            :beatsA => pat[0],
            :beatsB => pat[1],
            :custom => true
        };
    }

    function clamp(v as Number, lo as Number, hi as Number) as Number {
        if (v < lo) {
            return lo;
        }
        if (v > hi) {
            return hi;
        }
        return v;
    }

    function mmss(total as Number) as String {
        return Lang.format("$1$:$2$", [total / 60, (total % 60).format("%02d")]);
    }
}
