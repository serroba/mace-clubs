import Toybox.Lang;
import Toybox.Test;

// Renders every MaceClubsView screen state into an offscreen bitmap. These
// tests assert the draw paths complete without runtime errors across idle,
// countdown, paused, interval, free-training, rep, and combo states; pixel
// placement is reviewed on-device and in the simulator.

// The recording lifecycle needs a live FIT session, so a stub stands in for
// a started workout without touching ActivityRecording.
(:test)
class StartedWorkoutStub extends WorkoutSession {
    function initialize() {
        WorkoutSession.initialize();
    }

    function isStarted() as Boolean {
        return true;
    }
}

(:test)
function testIdleIntervalScreenRenders(logger as Test.Logger) as Boolean {
    var view = new MaceClubsView();
    RenderTestSupport.render(view);
    view.cyclePreset(1);
    RenderTestSupport.render(view);
    Test.assertMessage(!view.isStarting(), "idle screen leaves the countdown off");
    return true;
}

(:test)
function testStartCountdownScreenRenders(logger as Test.Logger) as Boolean {
    var view = new MaceClubsView();
    view.startWorkout();
    Test.assertMessage(view.isStarting(), "SELECT arms the five-second countdown");
    Test.assertMessage(view.getStartCountdownRemaining() > 0, "countdown reports remaining seconds");
    RenderTestSupport.render(view);
    view.cancelStartCountdown();
    Test.assertMessage(!view.isStarting(), "BACK cancels the countdown");
    Test.assertMessage(view.getStartCountdownRemaining() == 0, "no countdown remains after cancel");
    return true;
}

(:test)
function testPausedAndDoneSummariesRender(logger as Test.Logger) as Boolean {
    var view = new MaceClubsView();
    view.workout.selectWorkingSide(Movement.SIDE_LEFT);
    view.workout.addSetWithDuration(120);
    view.workout.endRestLapWithDuration(60);
    view.workout.addSetWithDuration(90);
    view.paused = true;
    RenderTestSupport.render(view);
    view.cycleSummary(1);
    view.cycleSummary(-1);
    RenderTestSupport.render(view);
    view.done = true;
    RenderTestSupport.render(view);
    return true;
}

(:test)
function testIntervalWorkoutScreenRenders(logger as Test.Logger) as Boolean {
    var view = new MaceClubsView();
    view.workout = new StartedWorkoutStub();
    view.plan = new Intervals.Plan(3, 120, 60);
    RenderTestSupport.render(view);
    return true;
}

(:test)
function testFreeTrainingScreensRender(logger as Test.Logger) as Boolean {
    var view = new MaceClubsView();
    view.workout = new StartedWorkoutStub();
    view.plan = null;
    view.freePhase = FreeTraining.PHASE_WORK;
    RenderTestSupport.render(view);
    Test.assertMessage(!view.isFreeResting(), "work phase is not a free rest");
    view.advanceFreeTraining();
    Test.assertMessage(view.isFreeResting(), "SELECT advances work into rest");
    RenderTestSupport.render(view);
    view.advanceFreeTraining();
    Test.assertMessage(!view.isFreeResting(), "SELECT advances rest into the next set");
    return true;
}

(:test)
function testComboWorkScreenRenders(logger as Test.Logger) as Boolean {
    var view = new MaceClubsView();
    var workout = new StartedWorkoutStub();
    workout.selectEquipment(Equipment.TYPE_BULAVA, 1);
    workout.selectMovement(Movement.TYPE_COMBO);
    view.workout = workout;
    view.plan = null;
    view.freePhase = FreeTraining.PHASE_WORK;
    RenderTestSupport.render(view);
    return true;
}

(:test)
function testDiscardResetsTheViewState(logger as Test.Logger) as Boolean {
    var view = new MaceClubsView();
    view.workout.addSetWithDuration(60);
    view.paused = true;
    view.done = true;
    view.discardWorkout();
    Test.assertMessage(!view.paused, "discard clears the paused flag");
    Test.assertMessage(!view.done, "discard clears the done flag");
    Test.assertMessage(view.plan == null, "discard drops the interval plan");
    RenderTestSupport.render(view);
    return true;
}

(:test)
function testRepCountAdjustmentsAreGuarded(logger as Test.Logger) as Boolean {
    var view = new MaceClubsView();
    // Rep-count corrections apply only in rep mode with the counter live;
    // outside it the call must be a safe no-op.
    view.adjustRepCount(1);
    Test.assertEqualMessage(view.workout.getCurrentSetSwings(), 0, "no counter, no correction");
    return true;
}
