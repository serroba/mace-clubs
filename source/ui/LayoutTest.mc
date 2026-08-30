import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Geometry assertions against the real screen and the real device fonts.
//
// These are the tests that would have caught the layout breaking on every
// large watch. The render tests next door only assert that a draw path
// completes without throwing - drawing two strings on top of each other
// throws nothing, so both large-screen defects sailed through a green suite:
// the three-column footer collapsing into an unreadable "setrndshr", and
// FONT_NUMBER_HOT (131px on a 454px watch against 30px on the Instinct)
// overdrawing its own caption.
//
// Every device in CI's unit-test matrix runs this file, so one representative
// per screen size / shape / display technology is covered: instinct3solar45mm
// (176 semi-octagon), instinct2 (176, 96KB memory), fenix5 (240, oldest API),
// fenix7 (260), fr965 and venu3 (454 AMOLED), venusq (rectangle) and
// vivoactive6 (390).
//
// Deliberately three dense test functions rather than a dozen small ones with
// helpers: a --unit-test build may define at most 253 module-level symbols and
// this suite already sits at 249 on venusq/instinct2/fenix5, so every new
// global test function or helper spends part of a four-symbol budget.
// Assertions are grouped and the loops inlined for that reason.
//
// Screen size is read from DeviceSettings, not from a Dc: a full-screen
// buffered bitmap would be 403KB on a 454px 16bpp device, more than venusq's
// entire 128KB app memory, so the offscreen Dc the render tests use stays
// small.
//
// The split between the two annotations is about *device fonts*, not about
// drawing. CI's unit-test container ships none at all, and every font query
// throws "Invalid Font Specified" there - the module-level
// Graphics.getFontHeight included, not just Dc methods. So anything touching
// font metrics carries :offscreenRender and runs where the fonts exist
// (locally, and the Linux e2e job which downloads them); the pure geometry -
// column spread, the round-screen chord, the clamp - runs on every device in
// the CI matrix, which is where the cross-device coverage comes from.

// Screen geometry that needs no font metrics, so it runs on every device in
// the CI unit-test matrix.
(:test)
function testLayoutFitsThisScreen(logger as Test.Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var footerY = h * 68 / 100;

    // The footer must spread with the screen rather than huddle in the middle:
    // the reference screen spans 100 of 176px (56%), and a footer squeezed
    // into the middle third is the regression being guarded.
    var left = Layout.columnX(w, h, 0, 3, Layout.COLUMN_PITCH, footerY);
    var right = Layout.columnX(w, h, 2, 3, Layout.COLUMN_PITCH, footerY);
    Test.assertMessage(
        (right - left) * 100 / w >= 40,
        Lang.format("footer spans only $1$% of a $2$px screen", [(right - left) * 100 / w, w])
    );

    // Every column centre stays inside the drawable width - on a round screen
    // that is the chord at the row's height, not the full diameter.
    var rows = [h * 68 / 100, h * 84 / 100, h * 72 / 100, h * 87 / 100] as Array<Number>;
    for (var r = 0; r < rows.size(); r++) {
        var half = Layout.usableHalfWidth(w, h, rows[r]);
        for (var c = 0; c < 3; c++) {
            var x = Layout.columnX(w, h, c, 3, Layout.COLUMN_PITCH, rows[r]);
            Test.assertMessage(
                x >= w / 2 - half && x <= w / 2 + half,
                Lang.format("column $1$ centre $2$ is outside the drawable width at y=$3$", [c, x, rows[r]])
            );
        }
    }

    // The chord maths itself: a round screen narrows towards the bottom, a
    // rectangle or semi-octagon does not.
    var middle = Layout.usableHalfWidth(w, h, h / 2);
    var nearBottom = Layout.usableHalfWidth(w, h, h * 92 / 100);
    Test.assertEqualMessage(middle, w / 2, "the widest row is the full half-width");
    if (Layout.isRound()) {
        Test.assertMessage(
            nearBottom < middle,
            Lang.format("a round screen must narrow towards the bottom ($1$ vs $2$)", [nearBottom, middle])
        );
    } else {
        Test.assertEqualMessage(nearBottom, w / 2, "a non-round screen keeps full width at every row");
    }
    return true;
}

// The Instinct's hand-tuned layout is the reference everything else scales
// from, so it has to land exactly where it always did: columns at cx +- 50.
// Pure arithmetic on the reference width, so it runs on every device and pins
// the reference regardless of which one is executing it.
(:test)
function testReferenceScreenLayoutIsUnchanged(logger as Test.Logger) as Boolean {
    var reference = Layout.REFERENCE_WIDTH;
    var mid = reference / 2;
    Test.assertEqualMessage(
        Layout.scaled(reference, 50),
        50,
        "reference-width scaling is the identity - the Instinct layout must not move"
    );
    Test.assertEqualMessage(
        Layout.columnX(reference, reference, 0, 3, 50, mid),
        mid - 50,
        "left column unchanged"
    );
    Test.assertEqualMessage(
        Layout.columnX(reference, reference, 1, 3, 50, mid),
        mid,
        "centre column unchanged"
    );
    Test.assertEqualMessage(
        Layout.columnX(reference, reference, 2, 3, 50, mid),
        mid + 50,
        "right column unchanged"
    );
    Test.assertEqualMessage(
        Layout.scaled(2 * reference, 50),
        100,
        "a screen twice as wide gets twice the column pitch"
    );
    return true;
}

// Text-width assertions need a Dc to measure with. This is the check that
// catches "setrndshr" directly: at the old fixed 50px pitch, "sets" "rnds"
// "hr" overlap on any screen much wider than the Instinct's.
(:test, :offscreenRender)
function testRenderedTextDoesNotCollide(logger as Test.Logger) as Boolean {
    var dc = RenderTestSupport.offscreenDc();
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;

    // Each row: y, pitch, font, widest realistic content per slot. "888"
    // covers a three-digit swing count or heart rate.
    var valueY = h * 68 / 100;
    var rows = [
        [valueY, Layout.COLUMN_PITCH, Graphics.FONT_MEDIUM, ["888", "888", "888"]],
        [
            Layout.labelBelow(w, valueY, Graphics.FONT_MEDIUM),
            Layout.COLUMN_PITCH,
            Graphics.FONT_TINY,
            ["sets", "rnds", "hr"]
        ],
        [h * 87 / 100, Layout.SUBWINDOW_COLUMN_PITCH, Graphics.FONT_TINY, ["total", "hr"]],
        [h * 84 / 100, Layout.SUBWINDOW_FREE_COLUMN_PITCH, Graphics.FONT_TINY, ["sets", "swng"]]
    ] as Array<Array>;

    for (var r = 0; r < rows.size(); r++) {
        var y = rows[r][0] as Number;
        var pitch = rows[r][1] as Number;
        var font = rows[r][2] as Graphics.FontDefinition;
        var texts = rows[r][3] as Array<String>;
        var half = Layout.usableHalfWidth(w, h, y);
        var previousRight = 0;
        for (var i = 0; i < texts.size(); i++) {
            var centre = Layout.columnX(w, h, i, texts.size(), pitch, y);
            var width = dc.getTextDimensions(texts[i], font)[0];
            var boxLeft = centre - width / 2;
            var boxRight = centre + width / 2;
            if (i > 0) {
                Test.assertMessage(
                    boxLeft >= previousRight,
                    Lang.format(
                        "row $1$: \"$2$\" starts at $3$ but the column before ends at $4$ ($5$px screen)",
                        [r, texts[i], boxLeft, previousRight, w]
                    )
                );
            }
            Test.assertMessage(
                boxLeft >= w / 2 - half && boxRight <= w / 2 + half,
                Lang.format(
                    "row $1$: \"$2$\" spans $3$..$4$, outside the drawable width at y=$5$",
                    [r, texts[i], boxLeft, boxRight, y]
                )
            );
            previousRight = boxRight;
        }
    }

    // Every candidate headline face must leave its caption clear, and the
    // smallest must fit the slot at all - the venu3 defect was
    // FONT_NUMBER_HOT at 131px against a 109px slot, drawn through "bpm".
    var fonts = Layout.numberFonts();
    for (var f = 0; f < fonts.size(); f++) {
        Test.assertMessage(
            h * 32 / 100 + Graphics.getFontHeight(fonts[f]) <= Layout.labelBelow(w, h * 32 / 100, fonts[f]),
            Lang.format("headline face $1$ overruns its own caption", [f])
        );
    }
    var slotForSmallest = h * 68 / 100
        - h * 32 / 100
        - Graphics.getFontHeight(Graphics.FONT_TINY)
        - Layout.scaled(w, Layout.LABEL_GAP);
    var smallest = Graphics.getFontHeight(fonts[fonts.size() - 1]);
    Test.assertMessage(
        smallest <= slotForSmallest,
        Lang.format(
            "smallest headline face is $1$px against a $2$px slot on a $3$px screen",
            [smallest, slotForSmallest, w]
        )
    );

    // The paused screen's headline sits level with the subwindow's lower
    // edge, so on an Instinct its right-hand end vanishes behind the cut-out
    // - "1 set 0:02 work" (115px against 113px of clear width) lost the "rk",
    // caught by the release screenshots. Shrinking cannot save it: FONT_XTINY
    // and FONT_TINY measure identically on this device, so the view drops the
    // redundant "work" suffix instead. These are the forms it can then draw.
    var clear = Layout.clearWidthBesideSubwindow(w);
    if (clear < w) {
        var headlines = ["1 set  0:02", "10 sets  12:34", "3 sets  L2/R1"] as Array<String>;
        for (var i = 0; i < headlines.size(); i++) {
            Test.assertMessage(
                dc.getTextDimensions(headlines[i], Graphics.FONT_TINY)[0] <= clear,
                Lang.format(
                    "paused headline \"$1$\" is wider than the $2$px clear of the subwindow",
                    [headlines[i], clear]
                )
            );
        }
    }

    // The headline face fitFont picks must fit its slot by width as well as
    // height, for the numeric values and the lettered rest-page ones alike.
    var topY = h * 32 / 100;
    var slot = h * 68 / 100
        - topY
        - Graphics.getFontHeight(Graphics.FONT_TINY)
        - Layout.scaled(w, Layout.LABEL_GAP);
    var maxWidth = 2 * Layout.usableHalfWidth(w, h, topY);
    var values = ["0:00", "88:88", "888", "load 1.2k"] as Array<String>;
    for (var v = 0; v < values.size(); v++) {
        var face = Layout.fitFont(
            dc,
            values[v],
            v < 3 ? Layout.numberFonts() : Layout.textFonts(),
            maxWidth,
            slot
        );
        Test.assertMessage(
            dc.getTextDimensions(values[v], face)[0] <= maxWidth,
            Lang.format("headline \"$1$\" is wider than the $2$px available", [values[v], maxWidth])
        );
        Test.assertMessage(
            topY + Graphics.getFontHeight(face) <= Layout.labelBelow(w, topY, face),
            Lang.format("headline \"$1$\" overruns its caption", [values[v]])
        );
    }
    return true;
}
