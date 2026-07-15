import Toybox.Lang;

// Interval training plans: N sets of work with rest in between.
// State is derived purely from the FIT timer time, so pausing the
// session (which freezes the timer) freezes the plan for free.
module Intervals {

    const PHASE_WORK = 0;
    const PHASE_REST = 1;
    const PHASE_DONE = 2;

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

            if (set >= _sets || (set == _sets - 1 && within >= _workSecs)) {
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

// Built-in workout shapes shown on the idle screen. :sets == 0 is
// free training (no interval plan, manual set marking).
module Presets {
    const LIST = [
        {:label => "Free training", :sets => 0, :work => 0, :rest => 0},
        {:label => "5 x 2:00 | 1:00", :sets => 5, :work => 120, :rest => 60},
        {:label => "5 x 2:00 | 2:00", :sets => 5, :work => 120, :rest => 120},
        {:label => "3 x 2:00 | 1:00", :sets => 3, :work => 120, :rest => 60},
        {:label => "10 x 1:00 | 0:30", :sets => 10, :work => 60, :rest => 30}
    ] as Array<Dictionary>;
}
