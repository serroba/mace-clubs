import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
function testWeightEditorAdjustsInHalfUnitsAndClamps(logger as Test.Logger) as Boolean {
    var editor = new WeightEditorView(Equipment.TYPE_MACE);
    var initial = editor.label();
    editor.adjust(1);
    Test.assertMessage(!editor.label().equals(initial), "UP moves the weight half a unit");
    editor.adjust(-1);
    Test.assertMessage(editor.label().equals(initial), "DOWN moves back to the starting weight");
    for (var i = 0; i < 300; i++) {
        editor.adjust(-1);
    }
    var floor = editor.label();
    editor.adjust(-1);
    Test.assertMessage(editor.label().equals(floor), "the editor clamps at the minimum weight");
    return true;
}

(:test)
function testWeightEditorSavesTheConfiguredDefault(logger as Test.Logger) as Boolean {
    var editor = new WeightEditorView(Equipment.TYPE_MACE);
    // Saving without adjustment persists the current default, so the test
    // leaves the simulator's settings unchanged.
    editor.save();
    var stored = Application.Properties.getValue(Equipment.weightKeyFor(Equipment.TYPE_MACE));
    Test.assertEqualMessage(
        stored as Number,
        Equipment.defaultWeightGrams(Equipment.TYPE_MACE),
        "save writes the grams value behind the label"
    );
    return true;
}

(:test)
function testWeightEditorScreenRenders(logger as Test.Logger) as Boolean {
    var editor = new WeightEditorView(Equipment.TYPE_CLUBS);
    RenderTestSupport.render(editor);
    return true;
}

(:test)
function testWeightEditorDelegateRoutesPaging(logger as Test.Logger) as Boolean {
    var editor = new WeightEditorView(Equipment.TYPE_MACE);
    var item = new WatchUi.MenuItem("weight", null, "weight", null);
    var delegate = new WeightEditorDelegate(editor, new MaceClubsView(), item, Equipment.TYPE_MACE);
    var before = editor.label();
    Test.assertMessage(delegate.onNextPage(), "DOWN page event is consumed");
    Test.assertMessage(delegate.onPreviousPage(), "UP page event is consumed");
    Test.assertMessage(editor.label().equals(before), "one up and one down cancel out");
    return true;
}
