import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class MaceClubsApp extends Application.AppBase {
    private var _view as MaceClubsView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {}

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
        reportMemory("entry");
        var view = new MaceClubsView();
        _view = view;
        var delegate = new MaceClubsDelegate(view);
        reportMemory("ready");
        return [view, delegate];
    }

    // What the app has left after it has built its first screen, printed for
    // tools/memory-headroom.ts to read back.
    //
    // Compiled out of every build but that one. The app grew past the
    // Instinct 2's 96KB in v0.13.4 and crashed here, before drawing a frame,
    // for four months and a 1-star review - and nothing in the repo measured
    // this, so nothing could have said which release did it. Two println
    // calls behind an annotation is a cheap way never to repeat that.
    (:memoryProbe)
    private function reportMemory(stage as String) as Void {
        var stats = System.getSystemStats();
        System.println(
            Lang.format(
                "MEMPROBE $1$ total=$2$ used=$3$ free=$4$",
                [stage, stats.totalMemory, stats.usedMemory, stats.freeMemory]
            )
        );
    }

    (:noMemoryProbe)
    private function reportMemory(stage as String) as Void {}
}
