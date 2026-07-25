import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Three-step on-watch editor for the Custom preset:
// sets -> work duration -> rest duration.
class CustomWorkoutEditorView extends WatchUi.View {
    const FIELD_SETS = 0;
    const FIELD_WORK = 1;
    const FIELD_REST = 2;
    const DURATION_STEP_SECONDS = 30;

    private var _field as Number = FIELD_SETS;
    private var _sets as Number;
    private var _workSeconds as Number;
    private var _restSeconds as Number;

    function initialize() {
        View.initialize();
        var preset = Presets.custom();
        _sets = preset[:sets] as Number;
        _workSeconds = preset[:work] as Number;
        _restSeconds = preset[:rest] as Number;
    }

    function adjust(direction as Number) as Void {
        if (_field == FIELD_SETS) {
            _sets = Presets.clamp(_sets + direction, 1, 50);
        } else if (_field == FIELD_WORK) {
            _workSeconds = Presets.clamp(_workSeconds + direction * DURATION_STEP_SECONDS, 30, 3600);
        } else {
            _restSeconds = Presets.clamp(_restSeconds + direction * DURATION_STEP_SECONDS, 0, 3600);
        }
        WatchUi.requestUpdate();
    }

    // Returns true after the final field has been saved.
    function advance() as Boolean {
        if (_field < FIELD_REST) {
            _field++;
            WatchUi.requestUpdate();
            return false;
        }
        save();
        return true;
    }

    // Returns true when BACK should close the editor.
    function retreat() as Boolean {
        if (_field == FIELD_SETS) {
            return true;
        }
        _field--;
        WatchUi.requestUpdate();
        return false;
    }

    function save() as Void {
        Application.Properties.setValue("customSets", _sets);
        Application.Properties.setValue("customWorkMinutes", _workSeconds / 60);
        Application.Properties.setValue("customWorkSeconds", _workSeconds % 60);
        Application.Properties.setValue("customRestMinutes", _restSeconds / 60);
        Application.Properties.setValue("customRestSeconds", _restSeconds % 60);
    }

    private function title() as String {
        if (_field == FIELD_WORK) {
            return "WORK DURATION";
        }
        if (_field == FIELD_REST) {
            return "REST DURATION";
        }
        return "NUMBER OF SETS";
    }

    private function value() as String {
        if (_field == FIELD_WORK) {
            return Presets.mmss(_workSeconds);
        }
        if (_field == FIELD_REST) {
            return Presets.mmss(_restSeconds);
        }
        return _sets.toString();
    }

    private function stepLabel() as String {
        return _field == FIELD_SETS ? "UP/DOWN: 1" : "UP/DOWN: 0:30";
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();
        dc.drawText(cx, h * 18 / 100, Graphics.FONT_SMALL, title(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 40 / 100, Graphics.FONT_NUMBER_MEDIUM, value(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 68 / 100, Graphics.FONT_TINY, stepLabel(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(
            cx,
            h * 80 / 100,
            Graphics.FONT_TINY,
            _field == FIELD_REST ? "SELECT: save" : "SELECT: next",
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }
}
