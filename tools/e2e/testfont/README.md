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

## Status: blocked on a Linux simulator segfault (root-caused, unresolved)

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
Root-caused via `tools/e2e/linux/probe-debug.sh` (a `gdb`-enabled fork of
the base image, `Dockerfile.debug`-style layer adding `gdb`/`binutils`) by
capturing a real core dump and disassembling the crash site:

- **The kernel's own core dump is useless here** - under local QEMU
  (arm64 host emulating this amd64 image), the kernel captures QEMU's own
  ARM64 host process, not the emulated x86_64 guest state, and gdb can't
  make sense of it (`malformed note`, garbled register state). **QEMU's
  own core dump** (`qemu_<prog>_<timestamp>_<pid>.core`, written
  alongside the kernel one) is the real x86_64 guest state and loads
  cleanly against the actual `simulator` binary.
- **The crashing instruction**: `movzwl 0x0(%rbp),%esi` with `rbp = 0x0`
  - a null-pointer read of a UTF-16 code unit. Reproduces at the exact
    same instruction address across every variant tried below, so it's
    one fixed bug, not several.
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
- **Independent of drawn content**: reproduces identically (same crash
  address) whether the idle screen's text uses `Lang.format()` or plain
  string concatenation - initially looked like it might be
  `Lang.format()`-placeholder-scanning code (the following instructions
  compare the loaded character against `0x24`/`'$'` and `0x40`/`'@'`),
  but changing the string content changes nothing.
- **Independent of whether the font is ever drawn with at all**: the
  decisive test - skip every `dc.drawText()` call on the idle screen
  entirely (icon only, pre-warmed font resource sitting unused in memory)
  - still segfaults, identically, on the next `Menu2` push. This
    supersedes an earlier, incorrect read of a messier experiment that
    seemed to show the crash needed the outgoing view to have drawn with
    the font; it doesn't.

**Root cause, fully isolated:** merely having a custom `FontResource`
loaded via `WatchUi.loadResource()` anywhere in the app - never mind
whether it's ever drawn with - crashes the Linux simulator natively on
the very next `Menu2` push. Not fixable by adjusting the font (size,
format, timing) or the drawn content; this is a bug/limitation in
Garmin's simulator binary itself.

**Why this kills the current approach:** the app's navigation requires
two `Menu2` pushes (equipment picker, movement picker) before reaching
any app-drawn screen, and further `Menu2`/`Confirmation` pushes happen
throughout a real session (settings, rest options, discard confirmation).
There is no point in the app's flow where the font could be loaded that
isn't followed by another such push - so this isn't a matter of finding
the right place to load it. A real fix would mean avoiding `Menu2`
(and `WatchUi.Confirmation`, likely the same native-widget class of bug)
entirely in this build variant - app-drawn menus and confirmations
instead of Garmin's system ones - which is a materially larger rewrite
than a font substitution, and hasn't been attempted.
