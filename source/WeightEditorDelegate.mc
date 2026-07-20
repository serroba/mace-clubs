import Toybox.Lang;
import Toybox.WatchUi;

class WeightEditorDelegate extends WatchUi.BehaviorDelegate {
    private var _editor as WeightEditorView;
    private var _view as MaceClubsView;
    private var _menuItem as WatchUi.MenuItem;
    private var _kind as Number;

    function initialize(
        editor as WeightEditorView,
        view as MaceClubsView,
        menuItem as WatchUi.MenuItem,
        kind as Number
    ) {
        BehaviorDelegate.initialize();
        _editor = editor;
        _view = view;
        _menuItem = menuItem;
        _kind = kind;
    }

    function onPreviousPage() as Boolean {
        _editor.adjust(1);
        return true;
    }

    function onNextPage() as Boolean {
        _editor.adjust(-1);
        return true;
    }

    function onSelect() as Boolean {
        _editor.save();
        _view.loadSettings();
        _menuItem.setLabel(SettingsMenu.equipmentWeightLabel(_kind));
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
