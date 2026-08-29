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

## Status

A single fixed-size bitmap font can't replicate the actual per-size
layout of `Graphics.FONT_LARGE`/`FONT_TINY`/etc., so `AppFont.get()`
returns the same resource for every request - this build variant trades
layout fidelity for "screens don't crash and text OCRs," which is what
this pipeline needs.

Verified so far: the idle screen renders real glyphs from this font
(OCR read back garbled-but-real text, confirmed via
`tools/e2e/linux/probe-testfont.sh` under local QEMU-emulated Docker).
A screen *transition* immediately afterward currently segfaults the
simulator's native binary - under investigation, see
`.github/workflows/e2e-testfont-probe.yml` (scratch workflow probing
whether this is QEMU/arm64-emulation-specific or a genuine font issue).
