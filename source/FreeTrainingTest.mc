import Toybox.Lang;
import Toybox.Test;

(:test)
function testFreeTrainingSelectCompletesWorkAndEntersRest(logger as Test.Logger) as Boolean {
    Test.assertMessage(FreeTraining.completesSet(FreeTraining.PHASE_WORK), "leaving work completes a set");
    Test.assertEqualMessage(
        FreeTraining.nextPhase(FreeTraining.PHASE_WORK),
        FreeTraining.PHASE_REST,
        "SELECT after work enters rest"
    );
    Test.assertMessage(!FreeTraining.metronomeRuns(FreeTraining.PHASE_REST), "rest silences metronome");
    return true;
}

(:test)
function testFreeTrainingSelectLeavesRestWithoutCompletingSet(logger as Test.Logger) as Boolean {
    Test.assertMessage(!FreeTraining.completesSet(FreeTraining.PHASE_REST), "leaving rest does not add a set");
    Test.assertEqualMessage(
        FreeTraining.nextPhase(FreeTraining.PHASE_REST),
        FreeTraining.PHASE_WORK,
        "SELECT after rest begins work"
    );
    Test.assertMessage(FreeTraining.metronomeRuns(FreeTraining.PHASE_WORK), "work runs metronome");
    return true;
}
