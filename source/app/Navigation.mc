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

    /**
     * Whether a tap has to be routed by where it landed rather than taken as
     * a select, on the watches whose only gesture is a tap.
     *
     * Here rather than in the delegate for the reason at the top of this
     * file: the states that matter are ones a unit-test process cannot push
     * a real view into. The state that matters most is a *finished* workout.
     * It used to be excluded - the reasoning being that it "can only be
     * saved" - and that left the seven watches with no MENU key unable to
     * leave a finished session without saving it, because onMenu is exactly
     * the route those watches do not have.
     *
     * `done` is not a parameter because a finished workout is a paused one:
     * MaceClubsView sets both flags together. NavigationTest passes that
     * combination explicitly so the exclusion cannot come back by accident.
    */
    function routesTapsByPosition(
        needsTapTarget as Boolean,
        starting as Boolean,
        started as Boolean,
        paused as Boolean,
        freeResting as Boolean
    ) as Boolean {
        if (!needsTapTarget || starting) {
            return false;
        }
        return !started || paused || freeResting;
    }
}
