# Test-only bitmap font (CI-only build variant)

**Why this exists:** on a bare Linux CI runner there's no licensed Garmin
device font available (see `tools/e2e/linux/README.md`), and it's not just
an OCR-legibility problem - the real Connect IQ simulator **fatally
crashes** ("Invalid Font Specified") the instant an app-drawn `onUpdate()`
calls `dc.drawText()` with a missing device font. Confirmed by running the
real app with zero fonts present: the `Menu2`-based pickers survive (they
render with no visible text), but the first app-drawn screen
(`MaceClubsView`'s "GET READY" countdown) crashes the whole process.

**What this is:** a real, open-source, redistributable font (JetBrains
Mono, OFL-1.1) rasterized into Garmin's own BMFont bitmap-font format
(`.fnt` + single-channel grayscale PNG - confirmed via
`How_Do_I_Use_Custom_Fonts.html` and by inspecting the SDK's own bundled
`Analog` sample font), routed through every `Graphics.FONT_*` call site in
the app's onUpdate() code via `source/ui/AppFont.mc`'s `(:testFont)`
variant. `monkey.e2e.jungle` is the only jungle that compiles it in; real
builds (`monkey.jungle`, `monkey.local.jungle`, `monkey.tuning.jungle`)
exclude `:testFont` and use actual device fonts exactly as before.

## Regenerating

```sh
python3 -m venv /tmp/fontenv && /tmp/fontenv/bin/pip install Pillow
brew install --cask font-jetbrains-mono   # or point FONT_PATH at any TTF
/tmp/fontenv/bin/python3 tools/e2e/testfont/generate.py
```

Writes `resources-testfont/fonts/testfont.fnt` + `testfont_0.png`, and a
`preview.png` here for a quick visual check. The atlas is single-channel
8-bit grayscale and kept within 256x256 - matching the SDK's own
`blackdiamond_0.png` sample exactly (an RGBA atlas compiles fine but fails
at *runtime* with a native, stack-trace-free "Invalid Font Specified"
crash - Garmin's custom-font format is single-channel only).

## Status: blocked on a Linux simulator segfault (unresolved)

A single fixed-size bitmap font can't replicate the actual per-size
layout of `Graphics.FONT_LARGE`/`FONT_TINY`/etc., so `AppFont.get()`
returns the same resource for every request - this build variant trades
layout fidelity for "screens don't crash and text OCRs," which is what
this pipeline needs.

**What works:** the idle screen renders real glyphs from this font (OCR
read back garbled-but-real text). This proves the original problem this
font exists to solve - the app fatally crashing on Linux the instant an
app-drawn screen calls `dc.drawText()` with a missing device font - is
solved for a screen that never transitions.

**What's still broken:** the moment the app transitions from the idle
screen to the equipment-picker `Menu2`, the simulator's native binary
segfaults (not a catchable Monkey C exception - the whole process dies).
Confirmed via `tools/e2e/linux/probe-testfont.sh`:

- **Reproduces identically on real x86_64 hardware**, not just local
  QEMU/arm64 emulation (verified via `.github/workflows/e2e-testfont-probe.yml`,
  a scratch branch-scoped workflow - ruled out emulation as the cause).
- **Independent of font size**: reproduces at both 22px and 14px line
  height, ruling out a GTK-layout-overflow theory (the pre-existing
  `gtk_distribute_natural_allocation: assertion 'extra_space >= 0' failed`
  warning, present even in known-working runs, isn't the cause either -
  or at least not one this font's metrics control).
- **Independent of load timing**: reproduces whether the font resource is
  lazily loaded on first draw or pre-warmed in `MaceClubsApp.onStart()`
  before any rendering happens.
- **Requires the outgoing view to have actually drawn with the custom
  font**: bypassing `AppFont.get()` on the idle screen (reverting it to
  the real, missing device font) does NOT segfault - it instead crashes
  immediately and catchably with the original "Invalid Font Specified"
  Monkey C exception, before ever reaching a Menu2 push. So the trigger
  isn't merely "a custom FontResource is loaded somewhere" - it's tied to
  the outgoing view having actually rendered pixels with it right before
  a `Menu2` push replaces it.

Current best explanation: a genuine bug/limitation in the Linux build of
Garmin's simulator when a loaded custom `FontResource` has been drawn
with and a `Menu2` is then pushed - not something fixable by adjusting
the font itself. A real fix would likely mean avoiding `Menu2` entirely
in this build variant (app-drawn menus instead), which is a materially
larger change than this font substitution.
