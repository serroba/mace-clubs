import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class MaceClubsApp extends Application.AppBase {
    private var _view as MaceClubsView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        // Pre-warms AppFont's (:testFont) resource load at startup rather
        // than lazily on the first onUpdate() draw call - loading a custom
        // FontResource from inside onUpdate() crashes the Linux simulator
        // on the very next screen transition (segfault, reproduced on both
        // QEMU-emulated and real x86_64 runners). No-op pass-through in
        // real builds, which exclude :testFont.
        AppFont.get(Graphics.FONT_TINY);
    }

    function onStop(state as Dictionary?) as Void {}

    // Called when settings are changed from the Garmin Connect phone app
    // while this app is running.
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.loadSettings();
        }
        WatchUi.requestUpdate();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new MaceClubsView();
        _view = view;
        return [view, new MaceClubsDelegate(view)];
    }
}
