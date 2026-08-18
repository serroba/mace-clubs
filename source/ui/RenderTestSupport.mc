import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Offscreen drawing context for exercising onUpdate render paths in unit
// tests. CIQ 3.2+ hands out buffered bitmaps through the graphics pool
// factory; 3.1 devices still construct them directly.
(:test)
module RenderTestSupport {
    function offscreenDc() as Graphics.Dc {
        var options = {:width => 176, :height => 176};
        var bitmap;
        if (Graphics has :createBufferedBitmap) {
            bitmap = Graphics.createBufferedBitmap(options).get() as Graphics.BufferedBitmap;
        } else {
            bitmap = new Graphics.BufferedBitmap(options);
        }
        return bitmap.getDc();
    }

    // The Linux simulator cannot rasterize device fonts into an offscreen
    // bitmap ("Invalid Font Specified" - a fatal error no test can catch);
    // macOS and Windows simulators can. The jungle picks the implementation:
    // monkey.jungle (used by the Linux CI action) excludes :offscreenRender,
    // while monkey.local.jungle (make test-build / simulator-test) excludes
    // :noOffscreenRender so local suites exercise the full draw paths. The
    // state assertions around every render() call run on both platforms.
    (:offscreenRender)
    function render(view as WatchUi.View) as Void {
        view.onUpdate(offscreenDc());
    }

    (:noOffscreenRender)
    function render(view as WatchUi.View) as Void {}
}
