import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class WeightEditorView extends WatchUi.View {
    private var _kind as Number;
    private var _pounds as Boolean;
    private var _tenths as Number;

    function initialize(kind as Number) {
        View.initialize();
        _kind = kind;
        _pounds = Equipment.usesPounds();
        _tenths = Equipment.editorTenths(Equipment.defaultWeightGrams(kind), _pounds);
    }

    function adjust(direction as Number) as Void {
        // Half-unit steps support common club sizes without making navigation
        // tedious. Internally everything remains grams.
        _tenths += direction * 5;
        if (_tenths < 5) {
            _tenths = 5;
        } else if (_tenths > 1100) {
            _tenths = 1100;
        }
        WatchUi.requestUpdate();
    }

    function save() as Void {
        var key = _kind == Equipment.TYPE_CLUBS ? "clubWeightGrams" : "maceWeightGrams";
        Application.Properties.setValue(key, Equipment.gramsFromEditorTenths(_tenths, _pounds));
    }

    function label() as String {
        return Equipment.decimalLabel(_tenths, _pounds ? "lb" : "kg");
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();
        dc.drawText(
            cx,
            h * 18 / 100,
            Graphics.FONT_SMALL,
            _kind == Equipment.TYPE_CLUBS ? "CLUB WEIGHT" : "MACE WEIGHT",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(cx, h * 40 / 100, Graphics.FONT_NUMBER_MEDIUM, label(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 68 / 100, Graphics.FONT_TINY, "UP/DOWN: 0.5", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 80 / 100, Graphics.FONT_TINY, "SELECT: save", Graphics.TEXT_JUSTIFY_CENTER);
    }
}
