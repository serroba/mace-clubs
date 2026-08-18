import Toybox.Lang;

// Pure button routing keeps paused navigation testable without pushing real
// simulator views from the unit-test process.
module Navigation {
    const PREVIOUS_IGNORE = 0;
    const PREVIOUS_HOME = 1;
    const PREVIOUS_TEMPO_UP = 2;
    const PREVIOUS_PRESET = 3;

    function previousPageAction(starting as Boolean, started as Boolean, paused as Boolean) as Number {
        if (starting) {
            return PREVIOUS_IGNORE;
        }
        if (paused) {
            return PREVIOUS_HOME;
        }
        return started ? PREVIOUS_TEMPO_UP : PREVIOUS_PRESET;
    }
}
