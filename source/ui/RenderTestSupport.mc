import Toybox.Graphics;
import Toybox.Lang;

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
}
