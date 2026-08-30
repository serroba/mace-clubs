# End-to-end UI testing

A BDD-style e2e framework that drives the real Garmin Connect IQ simulator on
macOS and Linux, across several watches, and asserts on what's actually on screen - not a render-logic unit
test (see `MaceClubsViewRenderTest.mc`), a real running app. Lives in
`tools/e2e/`, built on `node:test` (already used throughout `tools/`), plus
two purpose-built pieces:

- **`tools/e2e/simulator.ts`** - a small Playwright-flavored driver
  (`Simulator.launch()`, `.press()`, `.screenshot()`, `.readText()`,
  `.close()`) for an app with no official automation API. Every mechanic in
  it (which key code maps to which button, where the watch screen sits
  within the window, why focus needs an explicit click) was found
  empirically and is documented at the top of the file.
- **OCR via `tools/e2e/ocr.swift`** - `Simulator.readText()` reads the
  screen's text using macOS's built-in Vision framework, no extra
  dependency to install. Prefer this for asserting **what state the app is
  in** - it survives font-hinting noise that would flake a pixel diff, and
  a failure message like `expected "REST" on screen: [...]` is far more
  readable than a screenshot diff.

Screenshot baselines (`tools/e2e/screen-matcher.ts`, backed by
`pixelmatch` - the same library Playwright uses internally for
`toHaveScreenshot()`) are still available for asserting **layout**, but only
fits a screen whose content is genuinely static run to run. See
`equipment-picker.e2e.test.ts` (static menu text - screenshot baseline) vs
`rest-screen.e2e.test.ts` (live wall clock + countdown - OCR only) for both
patterns side by side.

## Running it

```sh
cd tools
npm run test:e2e
```

Requires macOS with **Screen Recording** and **Accessibility** permission
granted to whatever terminal/app runs this (System Settings > Privacy &
Security), **and an awake, unlocked display session** - a sleeping or
locked screen produces the same symptom as a missing permission (solid
black `screencapture` output) plus every `Simulator.launch()` timing out
waiting for a window, since the app can't actually paint one without a
live WindowServer session. Confirmed via `ioreg -c IOHIDSystem`'s
`HIDIdleTime` (seconds since the last real keyboard/mouse input) reading
in the thousands right before a run like this fails - check that before
suspecting memory pressure or a driver regression. Not part of
`make check` or CI - there's no GUI to drive there, the same reason
`tools/visual_check.sh`'s Linux/Xvfb approach isn't either.

`npm run test:e2e` runs `tools/e2e/run-e2e.ts`, which runs each
`*.e2e.test.ts` file as its own `node --test` process, one at a time.
**This matters**: `node --test a.ts b.ts` runs separate files concurrently
by default, and two files' `Simulator.launch()` calls will race to kill and
relaunch the one simulator instance both need exclusive use of -
`--test-concurrency=1` did not reliably prevent this in practice. Don't glob
multiple e2e files directly into `node --test`; add new files to this
directory and `run-e2e.ts` picks them up automatically.

## Writing a new test

Copy the shape of `rest-screen.e2e.test.ts` or `equipment-picker.e2e.test.ts`:

```ts
import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { Simulator } from "./simulator.ts";

void describe("Some screen", () => {
    let sim: Simulator;

    before(async () => {
        sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg" });
    });

    after(() => {
        sim.close();
    });

    it("does the thing", async () => {
        await sim.press("select"); // or "back" / "up" / "down", await sim.hold("menu")
        const lines = await sim.readText();
        assert.match(lines.join(" "), /whatever text should be there/);
    });
});
```

- `sim.pressUntilChanged("select")` instead of a single `press()` when
  you're not sure a screen has finished a reveal animation yet - it retries
  a few times, comparing screenshots with a pixel-tolerance (not exact byte
  equality, which flakes on capture/PNG-encoding jitter).
- For a **known fixed-duration** animation (the "GET READY" 5-second
  countdown), use a plain `setTimeout` sleep, not `waitForStable()` -
  `waitForStable()` polls for two consecutive identical-looking frames,
  which a value that changes exactly once a second can satisfy by chance
  between ticks, ending the wait early.
- Reach for `expectScreenshotMatches()` only when the screen's content is
  genuinely static. First run for a given name writes the baseline (review
  `tools/e2e/baselines/<name>.png` once, then commit it); subsequent runs
  compare against it. Delete the baseline (or set `UPDATE_BASELINES=1`) to
  intentionally recapture it after a real UI change.

## Choosing a device

The driver is device-parametric. Set `MACE_E2E_DEVICE` to any device the
SDK has files for:

```sh
MACE_E2E_DEVICE=venu3 npm run test:e2e --prefix tools
```

It defaults to `instinct3solar45mm`. Nothing about a device is hardcoded:
`tools/e2e/device-profile.ts` reads the screenshot crop, the MENU button
hotspot and the skin size out of that device's own `simulator.json`, which
the SDK already ships. This is what makes the suite worth running at all
beyond one watch - the layout defects it exists to catch (a footer whose
labels overlap into `setrndshr`, a headline number drawn through its own
caption) are invisible at the Instinct's 176px and obvious at 454px.

Two consequences worth knowing:

- **Baselines are per platform *and* per device**, under
  `tools/e2e/baselines/<platform>/<device>/`. Screen sizes differ outright,
  so they are not interchangeable. All three matrix devices have both their
  macOS and Linux baselines committed.

  Adding a *new* device is two steps, because its baselines do not exist yet:
  the first run **seeds** them and compares nothing (it says so, as a
  `::warning::` in CI), and the job uploads them as the
  `e2e-baselines-<device>` artifact. Download that, look at the PNGs, and
  commit them - only then is the layout actually being checked. Seeding is
  deliberately loud precisely because a seeded run is a green run that
  verified nothing.
- **Tests that need MENU skip themselves** where the device has no MENU key
  (`deviceProfile().menuHotspot === null` - the venu 4 family, venux1,
  vivoactive6, the vivoactive3 variants). There is no hotspot to hold there;
  the app's on-screen tap target covers the same route on those watches.

## Running in CI

The suite runs on **Linux**, headlessly, on GitHub-hosted runners -
`.github/workflows/e2e-linux.yml` - as a matrix over
`instinct3solar45mm`, `fenix7` and `venu3`: one per layout class the app
renders differently (semi-octagon with a subwindow, plain round MIP, large
round AMOLED). The same test files run on every platform and device; only
the driver's backend differs (see "Two platforms, one driver" below).
Device fonts and skins are fetched at job time through Garmin's own
authenticated API (see `tools/e2e/linux/README.md`), so nothing
proprietary lives in an image or this repo.

When it runs:

- **PRs and pushes to `main`**, but only when the change can actually
  affect what's on the watch screen or how it's driven - `source/`,
  `resources/`, `manifest.xml`, the jungles, `tools/e2e/`, the driver's
  dependencies, or the workflow itself. The suite takes ~8 minutes and
  most changes here are to the FIT/report tooling, docs, or video
  analysis, which can't move a pixel on the watch.
- **Every `v*` tag push, unfiltered.** GitHub skips path evaluation
  entirely for tag pushes, so a tagged release always gets a full run
  whatever its commit touched - which is the behavior we want, and worth
  knowing before adding path filters anywhere else.
- **On demand** via `workflow_dispatch`.

PRs **from forks** are the one exclusion: GitHub withholds secrets from
them, so the font fetch can't work, and they skip cleanly via the job's
`if` rather than failing on a missing credential.

The release-tag run is informational, not a gate - `release.yml` triggers
on the same tag and runs alongside it, so it can't stop a release that's
already tagged. The `pre-push` hook below is the actual gate.

**macOS in CI is a different story** and remains out of scope - it would
need a logged-in GUI session (AppleScript's `System Events` can't work over
a headless shell), pre-granted Screen Recording and Accessibility TCC
permissions (no supported non-interactive way to approve them, and a
GitHub-hosted `macos-*` runner is torn down after every job), and a
scripted SDK install (no prebuilt macOS image exists - the
`connectiq-tester` one is Linux-only). That means a **self-hosted macOS
runner**: standing infrastructure to own, not a config change. The Linux
job covers the same assertions, so there's no need for it.

Releases are additionally gated locally: the `pre-push` hook
(`.githooks/pre-push`, enabled via `make install-hooks`) runs the suite
whenever a `v*` tag is pushed - the push that triggers the release
workflow - under `caffeinate` so the display can't sleep mid-run. It still
needs the screen unlocked when the push starts.

## Two platforms, one driver

`simulator.ts` holds the platform-agnostic orchestration (launch
sequencing and retries, settle-waiting, press-until-changed) and delegates
the OS-specific primitives to the `Platform` seam in `platform.ts`:

| | macOS (`platform-macos.ts`) | Linux (`platform-linux.ts`) |
|---|---|---|
| Display | the real session | Xvfb + openbox |
| Input | AppleScript `System Events` | `xdotool` |
| Screenshot | `screencapture` | ImageMagick `import` |
| OCR | Vision framework (`ocr.swift`) | Tesseract |

Tests never see this: they use `Simulator` and the right backend is picked
from `process.platform`. Three findings worth knowing if you touch either:

- **Neither platform can hold a button with a key event.** The simulator
  maps keyboard input to taps only, so `hold()` is a *mouse*
  press-and-hold on the skin's UP-button hotspot on both. See
  `mouse-hold.swift`'s header for the eight keyboard approaches ruled out.
- **`xdotool`'s `--window` targeting works for mouse events but not key
  events** - the app ignores window-targeted synthetic key events
  entirely, so key presses go through `windowactivate` + a global press.
- **Tesseract needs the screen inverted, upscaled, and thresholded** to
  read it at all, and a Menu2's selected row is drawn already-inverted -
  so `ocr()` runs both polarities and merges the lines. Details in
  `platform-linux.ts`.

Screenshot baselines are keyed by platform and device
(`baselines/darwin/instinct3solar45mm/`, `baselines/linux/venu3/`, ...) -
macOS captures at Retina 2x with a different font rasterizer, and screen
sizes differ between devices, so none of them are interchangeable. OCR text assertions are
case-insensitive, since Vision and Tesseract disagree on the case of some
glyphs and these assertions are about *what state the app is in*, not
typography.

## Known flakiness

The Connect IQ simulator is a real (JVM-backed) GUI app with no automation
API, launched fresh for every test file for reliable isolation - expect a
one-time ~10-30s cold-boot cost per file, and note it degrades further under
system memory pressure (a starved JVM GCs constantly, which can push a cold
launch well past that). If a run hangs or times out waiting for the
simulator process/window, check `top`/`memory_pressure` before assuming the
framework itself regressed; `pkill -9 -f "ConnectIQ.app/Contents/MacOS/simulator"`
and a retry after freeing memory is the fastest way to confirm. But check
`ioreg -c IOHIDSystem | grep HIDIdleTime` first if the process is sitting
at ~0% CPU rather than churning - a high idle time (screen asleep/locked)
produces the exact same "window never appears" timeout and is a different
fix (wake and unlock, not free memory).

`run-e2e.ts` cleans up the simulator process on a Ctrl-C, a failed
`Simulator.launch()`, and normal completion, so it shouldn't need that
manual `pkill` in practice - it's there as the fallback for anything that
slips past those (a `kill -9` on the runner itself, for instance).

## How `Simulator.hold()` works (and why it's a mouse event)

MENU is a long-press of UP on the Instinct, and `hold()` synthesizes it as
a **mouse press-and-hold on the device skin's MENU hotspot** (from the same
`simulator.json` `keys` array the crop geometry comes from), via
`mouse-hold.swift`. That's not an implementation quirk - it's the only
mechanism that works, because the simulator maps keyboard input to taps
only. Ten approaches established this (a capturing `CGEventTap` listener
script was the diagnostic turning point - it showed synthetic keyboard
events were reaching the window server all along and let their fields be
diffed against AppleScript's working `key code` events):

- AppleScript's `key down`/`key up` commands: silent no-op, confirmed
  with an unambiguous single-tap test (Select).
- Raw `CGEventPost` keyboard events (any tap point, any event source,
  with or without an explicit Unicode string, targeted globally or at the
  simulator's own PID): silently dropped by the app **unless the
  arrow-key modifier flags (`fn`+`numericPad`, `0xa00000`) are set** -
  `CGEventCreateKeyboardEvent` doesn't populate those the way
  AppleScript's `key code` does, and the app discards arrow-key events
  without them. With the flags set and posted to `.cghidEventTap`, a
  *fast* down/up pair does land - but only ever as a tap.
- Any down/up pair held longer (with or without an OS-style autorepeat
  train between them): ignored outright, not even a tap. The simulator
  simply has no keyboard path to a hold.
- Rapidly repeating the working `key code` command: 20 discrete taps
  (observably - it cycled the idle preset selector 20 times), never a
  hold.

A human triggers MENU in the simulator by press-and-holding the mouse on
the skin's button, so the driver does exactly that. The hotspot is
device-specific, like the screenshot geometry, and both come from
`device-profile.ts` reading the device's `simulator.json`. Where a device
has no MENU key at all the profile reports `menuHotspot === null` and the
tests that need it skip.
