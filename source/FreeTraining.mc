import Toybox.Lang;

// Pure state decisions for manual Free training. Rest keeps the activity
// recording; Pause remains a separate whole-session interruption.
module FreeTraining {
    const PHASE_WORK = 0;
    const PHASE_REST = 1;

    function nextPhase(phase as Number) as Number {
        return phase == PHASE_REST ? PHASE_WORK : PHASE_REST;
    }

    function completesSet(phase as Number) as Boolean {
        return phase == PHASE_WORK;
    }

    function metronomeRuns(phase as Number) as Boolean {
        return phase == PHASE_WORK;
    }
}
