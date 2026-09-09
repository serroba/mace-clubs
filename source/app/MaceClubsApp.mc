import Toybox.Application;
import Toybox.Lang;
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

    // Two versions rather than one that calls an empty helper. The first
    // attempt kept a single body with two reportMemory() calls compiled to
    // nothing, and that was not free: it turned the reduced e2e suite red on
    // descentg1, instinct2 and instinct2x, which have 7-8KB to spare. On this
    // shape the shipped build has no call site, no helper and no extra local,
    // and compiles to a .prg identical to the one before the probe existed.
    (:noMemoryProbe)
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new MaceClubsView();
        _view = view;
        return [view, new MaceClubsDelegate(view)];
    }

    // The same thing, plus what the app has left on either side of building
    // its first screen, printed for tools/memory-headroom.ts to read back.
    //
    // Compiled by monkey.probe.jungle and nothing else. The app grew past the
    // Instinct 2's 96KB in v0.13.4 and crashed here, before drawing a frame,
    // for four months and a 1-star review - and nothing in the repo measured
    // this, so nothing could have said which release did it.
    //
    // Toybox.System is spelled out rather than imported because an import is
    // file-scope and cannot be annotated away.
    (:memoryProbe)
    function getInitialView() as [Views] or [Views, InputDelegates] {
        reportMemory("entry");
        var view = new MaceClubsView();
        _view = view;
        var delegate = new MaceClubsDelegate(view);
        reportMemory("ready");
        reportPeak();
        return [view, delegate];
    }

    // What is left with the settings menu built on top of the first screen.
    //
    // "ready" is not the number that decides whether a watch can run this
    // app. The 208-byte regression in #188 started fine on descentg1,
    // instinct2 and instinct2x and then died opening settings - the screen
    // that allocates most on top of the main view - which a check reading
    // only the first screen cannot see. Garmin's own advice is about peak
    // memory for this reason.
    //
    // Built and dropped rather than shown: SettingsMenu.build() is a pure
    // function, so this is the real allocation without needing anything to
    // drive the watch's buttons. It is a proxy for the peak, not the peak
    // itself - showing the menu costs a little more - so treat it as the
    // heaviest thing this can measure without an input driver, and keep the
    // e2e suite as the thing that actually opens it.
    (:memoryProbe)
    private function reportPeak() as Void {
        var menu = SettingsMenu.build();
        if (menu != null) {
            reportMemory("peak");
        }
    }

    (:memoryProbe)
    private function reportMemory(stage as String) as Void {
        var stats = Toybox.System.getSystemStats();
        Toybox.System.println(
            Lang.format(
                "MEMPROBE $1$ total=$2$ used=$3$ free=$4$",
                [stage, stats.totalMemory, stats.usedMemory, stats.freeMemory]
            )
        );
    }
}
