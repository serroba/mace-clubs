import Toybox.Lang;
import Toybox.Test;

// The accent is only safe because it is bright. Eight devices in the manifest
// have a two-colour panel and Connect IQ offers no way to detect them, so the
// app relies on the hardware resolving ACCENT towards white; a dim accent
// would resolve to black and delete the WORK cue on the very watch the app is
// validated against. That reasoning is invisible in a hex literal, so it is
// asserted here instead - anyone picking a moodier accent gets a failure
// rather than a blank line on an Instinct.
(:test)
function testAccentSurvivesATwoColourPanel(logger as Test.Logger) as Boolean {
    var r = Palette.ACCENT >> 16 & 0xFF;
    var g = Palette.ACCENT >> 8 & 0xFF;
    var b = Palette.ACCENT & 0xFF;

    // Squared distance is enough; the comparison is all that matters.
    var toWhite = (255 - r) * (255 - r) + (255 - g) * (255 - g) + (255 - b) * (255 - b);
    var toBlack = r * r + g * g + b * b;
    Test.assertMessage(toWhite < toBlack, "accent must sit nearer white than black on a 2-colour panel");

    // And by a real margin, not a rounding error - at least twice as near.
    Test.assertMessage(toWhite * 2 < toBlack, "accent is too dim to rely on resolving to white");
    return true;
}
