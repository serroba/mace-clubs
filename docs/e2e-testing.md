# End-to-end UI testing

A BDD-style e2e framework that drives the real Garmin Connect IQ simulator on
macOS and asserts on what's actually on screen - not a render-logic unit
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

## Running in CI

Not wired up, deliberately - it needs more than a workflow file:

- **A logged-in macOS GUI session.** The driver controls windows and sends
  key events via AppleScript's `System Events`, which needs a real
  WindowServer session, not a headless SSH-style shell.
- **Screen Recording + Accessibility permission, pre-granted.** These are
  per-machine TCC grants with no supported non-interactive way to approve
  them - no profile or `tccutil` incantation grants them on a fresh,
  ephemeral runner. A GitHub-hosted `macos-*` runner is torn down after
  every job, so there's never a persistent grant to build on.
- **The Connect IQ SDK and device files installed.** Unlike the Linux CI
  jobs above, there's no prebuilt macOS image with these preinstalled
  (`ghcr.io/matco/connectiq-tester` is Linux-only); the SDK Manager would
  need to be scripted fresh, and slowly, on every run.

The realistic path is a **self-hosted macOS runner** - a real, persistently
logged-in Mac added to the repo's Actions runners - where Screen Recording
and Accessibility are granted once by hand and then persist across runs the
same way they do for local development. That's a standing piece of
infrastructure to own (a dedicated always-on machine), not a config change,
so it's out of scope until there's an actual need for it; this suite stays a
local, pre-merge/manual-verification tool for now, same as
`tools/visual_check.sh`.

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

## Known issue: `Simulator.hold()` doesn't actually hold

`hold()` is supposed to synthesize a real held button-press (MENU is a
long-press of UP on this device - see `simulator.ts`'s comment), but its
current implementation - AppleScript's `key down`/`key up` commands - is a
silent no-op against this app. Confirmed with a deliberately unambiguous
test (Select, whose single-press effect - advancing off the idle screen -
is used and proven by every other passing test): a `key down 36` / `key up
36` pair produces literally no effect, while the working `press()`'s
single `key code 36` command reliably advances the screen every time.

Eight approaches were tried and ruled out, all with the same "zero
observable effect" result except where noted:

- AppleScript `key down`/`key up` (the current, broken implementation).
- Raw `CGEventPost` to `.cghidEventTap`, both as a single down/up pair and
  as a repeated keyDown "autorepeat train" (in case the app's hold
  detection watches for the OS's real autorepeat mechanism rather than
  wall-clock time between one down and one up).
- The same repeat-train approach against `.cgSessionEventTap`.
- `CGEventPostToPid`, targeting the simulator's own process directly
  (Java/AWT apps have a history of only reliably picking up synthetic
  input targeted at their own PID rather than posted to whatever the OS
  considers globally frontmost) - still nothing.
- The same, with the event's Unicode string explicitly set to the arrow
  keys' NSEvent function-key codepoints (`0xF700`/`0xF701`) - a
  bare `CGEventCreateKeyboardEvent` doesn't populate this the way
  AppleScript's `key code` does, and some AWT input paths need it to
  translate an event at all - still nothing.
- The same, with an explicit `.combinedSessionState` event source instead
  of the default - still nothing.
- Rapidly repeating the *working* `key code` command in a tight loop, on
  the theory that the app might treat a fast-enough burst as a hold: it
  doesn't - confirmed observably, since 20 rapid `key code 126` presses
  cycled the idle preset selector 20 separate times (each one a discrete
  tap-and-release), never triggering the hold-only Settings menu.

So `key code` (AppleScript's own synthesized press) is the only mechanism
proven to reach this app at all, and it only ever produces a tap, never a
hold - `discard-confirmation.e2e.test.ts`, `rest-options-menu.e2e.test.ts`,
and `settings-menu.e2e.test.ts` are written and typecheck-clean but
currently skipped (`describe.skip`) pending a real fix. Worth trying next:
comparing exactly what fields/state AppleScript's `key code` sets on its
underlying event (e.g. via a capturing `CGEventTap` listener script) against
what a manually-constructed one has, since something concrete is clearly
different between the two and blind parameter guessing didn't find it.
