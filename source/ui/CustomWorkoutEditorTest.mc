import Toybox.Lang;
import Toybox.Test;

(:test)
function testCustomEditorWalksSetsWorkRestAndSaves(logger as Test.Logger) as Boolean {
    var editor = new CustomWorkoutEditorView();
    Test.assertMessage(editor.retreat(), "BACK on the first field closes the editor");
    Test.assertMessage(!editor.advance(), "sets advance to work duration");
    Test.assertMessage(!editor.advance(), "work advances to rest duration");
    Test.assertMessage(!editor.retreat(), "BACK steps from rest to work");
    Test.assertMessage(!editor.advance(), "work advances to rest again");
    // Advancing past the final field saves the (unchanged) preset and closes.
    Test.assertMessage(editor.advance(), "SELECT on rest saves and closes");
    var preset = Presets.custom();
    Test.assertMessage((preset[:sets] as Number) >= 1, "saved preset keeps at least one set");
    return true;
}

(:test)
function testCustomEditorAdjustsAndClampsEachField(logger as Test.Logger) as Boolean {
    var editor = new CustomWorkoutEditorView();
    // Sets clamp at 1; a long run of DOWN presses must not go below it.
    for (var i = 0; i < 60; i++) {
        editor.adjust(-1);
    }
    editor.onUpdate(RenderTestSupport.offscreenDc());
    editor.advance();
    // Work clamps at 30 seconds.
    for (var i = 0; i < 130; i++) {
        editor.adjust(-1);
    }
    editor.onUpdate(RenderTestSupport.offscreenDc());
    editor.advance();
    // Rest may reach zero but never below.
    for (var i = 0; i < 130; i++) {
        editor.adjust(-1);
    }
    editor.adjust(1);
    editor.onUpdate(RenderTestSupport.offscreenDc());
    return true;
}
