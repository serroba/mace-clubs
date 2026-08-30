import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Screen geometry for the app-drawn views.
//
// Every offset in this app was originally measured on the Instinct 3 Solar's
// 176x176 screen - the smallest display we ship. Vertical positions were
// expressed as percentages of height and scale fine; horizontal offsets and
// font choices were hardcoded pixels and did not. Fonts, meanwhile, scale
// with the display: FONT_NUMBER_HOT is 30px tall on the Instinct and 131px on
// a 454px Venu 3, and FONT_MEDIUM goes from 20px to 49px. Two things broke on
// every large screen as a result:
//
//   - the three-column footer drawn at a fixed cx +- 50 collapsed into
//     itself, rendering "sets" "rnds" "hr" as an unreadable "setrndshr"
//   - FONT_NUMBER_HOT overran the 24%-of-height slot the layout gave it and
//     drew straight through its own label
//
// Both are confirmed on device skins in the simulator, on venu3 / fr965 /
// venux1 / vivoactive6 - roughly a third of the catalogue is 390px or wider.
//
// Everything here derives from the Dc's real dimensions and the device's real
// font metrics instead of a pixel count that only ever suited one watch.
module Layout {
    // The Instinct 3 Solar screen the app's original offsets were measured
    // against. Reference lengths below are in its pixels, so the Instinct
    // keeps its hand-tuned layout exactly and every other device scales off
    // it rather than off a fresh set of magic numbers.
    const REFERENCE_WIDTH = 176;

    // Gap between a value and the label sitting under it, at reference scale.
    const LABEL_GAP = 2;

    // Gap between footer columns, in reference pixels - columnX scales these
    // to the actual screen. The subwindow variants are wider because those
    // layouts carry two columns rather than three.
    const COLUMN_PITCH = 50;
    const SUBWINDOW_COLUMN_PITCH = 70;
    const SUBWINDOW_FREE_COLUMN_PITCH = 60;

    // Screen dimensions are passed in rather than read off the Dc so the
    // geometry stays testable at any device size: a unit test's offscreen
    // buffered bitmap has to stay small (a full 454x454 16bpp buffer is
    // 403KB, more than venusq's entire 128KB app memory), while font metrics
    // come from the device and are the same whatever the bitmap measures.
    // LayoutTest therefore asserts real-screen geometry using real fonts.

    // Scales a length measured on the reference screen to this screen width.
    function scaled(screenWidth as Number, referencePixels as Number) as Number {
        return referencePixels * screenWidth / REFERENCE_WIDTH;
    }

    // Centre x of column `index` of `count`, spread symmetrically about the
    // screen centre with `referencePitch` between neighbours on the Instinct.
    // Columns are clamped into the usable width at `y` so the outermost pair
    // cannot slide under a round screen's bezel on a wide layout.
    function columnX(
        screenWidth as Number,
        screenHeight as Number,
        index as Number,
        count as Number,
        referencePitch as Number,
        y as Number
    ) as Number {
        var centre = screenWidth / 2;
        if (count <= 1) {
            return centre;
        }
        var pitch = scaled(screenWidth, referencePitch);
        var offset = (index - (count - 1) / 2.0) * pitch;
        var limit = usableHalfWidth(screenWidth, screenHeight, y) - pitch / 2;
        if (offset > limit) {
            offset = limit;
        } else if (offset < -limit) {
            offset = -limit;
        }
        return centre + offset.toNumber();
    }

    // Half the drawable width at vertical position `y`. A round screen's
    // usable width is the chord at that height, not the full diameter, so
    // rows near the top and bottom have much less room than the middle.
    // Semi-octagon (Instinct) and rectangle screens are treated as full
    // width: the Instinct's corners are only clipped diagonally and its
    // layout already dodges the subwindow explicitly.
    function usableHalfWidth(screenWidth as Number, screenHeight as Number, y as Number) as Number {
        var halfWidth = screenWidth / 2;
        if (!isRound()) {
            return halfWidth;
        }
        var halfHeight = screenHeight / 2;
        var dy = (y - halfHeight).abs();
        if (dy >= halfHeight) {
            return 0;
        }
        // Chord half-width of the inscribed circle at this height.
        var chord = Math.sqrt((halfHeight * halfHeight - dy * dy).toDouble());
        return chord.toNumber();
    }

    function isRound() as Boolean {
        if (!(System has :SCREEN_SHAPE_ROUND)) {
            return false;
        }
        return System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND;
    }

    // The largest of `fonts` (largest first) that renders `text` inside
    // maxWidth x maxHeight. Returns the last entry when nothing fits, so the
    // caller always gets something drawable rather than null.
    //
    // This is what keeps the headline number honest across the range: on the
    // Instinct FONT_NUMBER_HOT fits its slot and is chosen exactly as before,
    // while on a 454px AMOLED - where the same font is 29% of screen height -
    // it steps down instead of overdrawing the label beneath it.
    function fitFont(
        dc as Dc,
        text as String,
        fonts as Array<Graphics.FontDefinition>,
        maxWidth as Number,
        maxHeight as Number
    ) as Graphics.FontDefinition {
        for (var i = 0; i < fonts.size(); i++) {
            var dims = dc.getTextDimensions(text, fonts[i]);
            if (dims[0] <= maxWidth && dims[1] <= maxHeight) {
                return fonts[i];
            }
        }
        return fonts[fonts.size() - 1];
    }

    // Number fonts, largest first - for a headline value that is only digits
    // and separators. Number faces are digit-only, so any value containing
    // letters must use textFonts() instead.
    function numberFonts() as Array<Graphics.FontDefinition> {
        return [
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_LARGE
        ] as Array<Graphics.FontDefinition>;
    }

    // Text faces, largest first - for a headline value with letters in it
    // (combo status, "42 sw", "load 1.2k").
    function textFonts() as Array<Graphics.FontDefinition> {
        return [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY] as Array<Graphics.FontDefinition>;
    }

    // y of a label drawn under a value: directly below the value's real
    // rendered height rather than at a fixed percentage that a tall font
    // would overrun.
    //
    // Graphics.getFontHeight is the module-level one, not Dc's - font metrics
    // are a property of the device, so this needs no drawing context. That
    // matters for the tests: CI's Linux simulator cannot rasterize device
    // fonts into an offscreen bitmap at all (see RenderTestSupport), so
    // anything requiring a Dc can only be asserted locally.
    function labelBelow(screenWidth as Number, valueY as Number, valueFont as Graphics.FontDefinition) as Number {
        return valueY + Graphics.getFontHeight(valueFont) + scaled(screenWidth, LABEL_GAP);
    }
}
