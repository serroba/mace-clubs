import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Routes every Graphics.FONT_* usage in app-drawn onUpdate() code through
// this indirection so the Linux e2e pipeline's CI-only build (see
// tools/e2e/testfont/README.md, monkey.e2e.jungle) can substitute a
// bundled open-source bitmap font. Linux CI runners have no licensed
// Garmin device fonts, and the real simulator fatally crashes
// ("Invalid Font Specified") the instant onUpdate() calls dc.drawText()
// with a missing device font - so this isn't cosmetic, screens are
// unreachable on that pipeline without it. Real builds and local dev use
// monkey.jungle/monkey.local.jungle, which exclude :testFont, so get()
// resolves to the plain pass-through below and device fonts are used
// exactly as before.
module AppFont {
    (:testFont)
    var custom as WatchUi.FontResource? = null;

    (:testFont)
    function get(deviceFont as Graphics.FontDefinition) as Graphics.FontDefinition {
        if (custom == null) {
            custom = WatchUi.loadResource(Rez.Fonts.id_font_testfont) as WatchUi.FontResource;
        }
        return custom as Graphics.FontDefinition;
    }

    (:noTestFont)
    function get(deviceFont as Graphics.FontDefinition) as Graphics.FontDefinition {
        return deviceFont;
    }
}
