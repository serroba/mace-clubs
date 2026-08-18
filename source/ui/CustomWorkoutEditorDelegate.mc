import Toybox.Lang;
import Toybox.WatchUi;

class CustomWorkoutEditorDelegate extends WatchUi.BehaviorDelegate {
    private var _editor as CustomWorkoutEditorView;
    private var _view as MaceClubsView;
    private var _menuItem as WatchUi.MenuItem;

    function initialize(editor as CustomWorkoutEditorView, view as MaceClubsView, menuItem as WatchUi.MenuItem) {
        BehaviorDelegate.initialize();
        _editor = editor;
        _view = view;
        _menuItem = menuItem;
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
        if (_editor.advance()) {
            _view.loadSettings();
            _menuItem.setLabel(SettingsMenu.customWorkoutLabel());
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }

    function onBack() as Boolean {
        if (_editor.retreat()) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }
}
