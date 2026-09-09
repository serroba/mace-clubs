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
  so they are not interchangeable. `instinct3solar45mm`, `fenix7` and `venu3`
  have both their macOS and Linux baselines committed; `instinct2` has Linux
  baselines only. The other four reduced devices have none yet and will seed
  them on their first run of the reduced workflow.

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

The suite runs on **Linux**, headlessly, on GitHub-hosted runners, as two
workflows over two device groups.

`.github/workflows/e2e-linux.yml` runs the **full** suite - what 115 of the
120 devices ship:

| Width | Device | Display | Input |
| --- | --- | --- | --- |
| 176 | `instinct3solar45mm` | semi-octagon MIP, 1bpp, subwindow | keys |
| 208 | `fr55` | round MIP, 4bpp | keys |
| 218 | `vivoactive4s` | round MIP, 8bpp | touch, no UP/DOWN |
| 240 | `fr945` | round MIP, 8bpp | keys |
| 260 | `fenix7` | round MIP, 8bpp | touch with keys |
| 280 | `fenix8solar51mm` | round MIP, 8bpp | touch with keys |
| 390 | `vivoactive5` | round AMOLED, 16bpp | touch, no UP/DOWN |
| 454 | `venu3` | round AMOLED, 16bpp | touch, no UP/DOWN |
| 454 | `venu445mm` | round AMOLED, 16bpp | touch, **no MENU key** - 4 of 7 files |

`.github/workflows/e2e-linux-reduced.yml` runs the **reduced** suite over
`instinct2`, `instinct2s`, `instinct2x` and `descentg1`. The whole app does not fit in
96KB, so the reduced build compiles out the history browser, the on-watch
workout editor, motion export and calibration logging, and shortens the
rest-options rows and the discard prompt that their older Menu2 font clips
off a 176px screen.

Five devices ship that build, not four. Which ones is decided by
`tools/reduced-devices.ts` from each device's own memory limit, and all five
start and run; the one missing from the matrix is staged the same way as the
widths below:

| Device | Screen | Status |
| --- | --- | --- |
| `instinctcrossover` | 176x176 | 6 of 7. The workout summary's middle rows sit under the watch's **physical hands**. The app now parks them while that screen is up (`WorkoutSummaryView.onShow`), which fixes it for owners - but the simulator paints its hands on regardless of what the app asks, so the rows stay covered here and the test stays unassertable |

That last one was filed as a device property that the app could not do
anything about, and that was wrong: `WatchUi.View.setClockHandPosition` has
existed since API 3.3.0 and moves the hands. It is fixed. What remains is
only that the simulator cannot show the fix working, so the device stays at
6 of 7 for a reason about the test harness rather than about the watch.

Everything else about that watch is covered - it starts, records, and passes
the other six files.

That is not a crash. The watch starts, runs a workout and records it; what
is missing is UI coverage, which is why it is staged rather than blocking.

`instinct2s` is worth a note as the shape of mistake this suite invites. Its
side row read as `eet he`, which looks exactly like the clipped text we had
just fixed twice, and the fix looked obvious: shorten the label again. It
was not clipped. Only two rows fit above the fold on a 156px-tall screen and
the assertion was reading half of a row at the bottom edge - the test needed
to scroll to it, as it already did for the row below. A screenshot of the
scrolled screen settled in one run what the wording change would have
shipped as a permanent product change to five watches.

### Two suites, not one suite with conditionals

Most screens render the same everywhere and live in `tools/e2e/`; both
workflows run them. The two that differ have a file each in
`tools/e2e/full/` and `tools/e2e/reduced/`, selected by `MACE_E2E_SUITE`:

| Shared | Full only | Reduced only |
| --- | --- | --- |
| discard-confirmation | settings-menu | settings-menu |
| equipment-picker | rest-options-menu | rest-options-menu |
| movement-picker | | |
| rest-screen | | |
| workout-summary | | |

This started as a conditional inside the shared files, asking a helper
whether the device under test had a given feature compiled out. It read
fine and was wrong in a way worth remembering: it put the jungle's device
list inside an assertion, so the same fact had to stay right in two places,
and "this device has no history row" and "the history row is broken" became
the same green result. A file per variant says what its build shows and
nothing else.

Which devices are reduced is not written down in either workflow as the
source of truth. `tools/reduced-devices.ts` derives it from each device's
own `compiler.json` and fails CI when the jungles disagree - because the
first fix for this listed three devices by hand and left two more crashing
in the store.

### Why not one simulator, and why not more jobs

Each test file starts its own simulator, which is about thirty seconds in CI
before an assertion runs - most of a ten-minute job across seven files. The
obvious saving is to start one simulator and reload the app per file, and it
is the wrong one: the app persists `movementType` and `workingSide`
mid-workout (`MaceClubsView`), among twenty `Properties`/`Storage` writes,
and the pickers assert on those defaults. A shared simulator would leak one
file's state into the next file's assertions. Restarting per file is buying
isolation, not just simplicity.

Splitting the suite across two jobs per device keeps that isolation and does
shorten each job - the runner supports it, `MACE_E2E_SHARD` with
`MACE_E2E_SHARD_COUNT`, and it is useful locally for running part of the
suite. **CI does not use it, because it was measured and it was slower.**

At nine devices the e2e jobs started within five seconds of each other and
parallelism was free. Two shards each makes 18 jobs, plus 8 reduced and 25 in
`ci.yml`: 51 at once, which is past what the runners give us. The slowest job
fell from 654s to 458s and jobs began queueing for up to 348s, so the run as
a whole went from ten minutes to eleven.

That is the shape of the constraint: the wall clock is set by how many jobs
can start at once, not by how long any one of them takes. More jobs is not a
lever here; a shorter job is. Anything that adds jobs should be measured
against the queue delay rather than the job duration.

### Nothing is staged any more

Every device the store's device report names is now driven, across the two
workflows, and every screen width with it. Two of them are worth knowing
about rather than reading off the count:

| Device | Runs | Why not all seven |
| --- | --- | --- |
| `venu445mm` | 6 of 7 | No MENU key at all, so the settings menu and the rest options menu are reached by tapping the hint band on their screens - `openSettingsMenu` and `openRestOptions` do what the watch's own hints tell an owner to do. Only `discard-confirmation` skips: it holds MENU mid-work, and on these watches you pause first and then discard, which the paused screen offers and the suite covers through `workout-summary`. |
| `instinctcrossover` | 6 of 7 | The summary's rows sit under the watch's physical hands. The app now parks them (`WorkoutSummaryView.onShow`), which fixes it on a wrist, but the simulator paints its hands on regardless, so the test cannot see the fix. |

### How the no-MENU watches reach a menu

`venu441mm`, `venu445mm`, `venux1`, `vivoactive6` and the three
`vivoactive3` variants have no MENU key, so every menu they can open is
opened by tapping a band the screen advertises: `TAP opens settings` when
idle, `TAP options` while free-resting, `TAP discard` when paused. Taps are
routed by position rather than taken wholesale, because a tap and the
physical SELECT key are indistinguishable to the simulator and each of those
screens offers both - `SELECT: work` sits beside `TAP options`.

`openSettingsMenu` and `openRestOptions` in `tools/e2e/open-menu.ts` pick the
hold or the tap per device, so the tests read the same on every watch.

The one route those watches still do not have is MENU held mid-work, which
elsewhere goes straight to the discard confirmation. They pause first and
discard from there. `discard-confirmation` skips accordingly; the paused
route it stands in for is covered by `workout-summary`.

### Compiling is not running

`ci.yml`'s build sweep proves all 120 devices compile. It says nothing about
whether a watch can hold what it compiled, and that gap is how the app spent
four months unable to start on 11.94% of installs.

`make memory-headroom` measures what is left at the app's peak, per device, by
running it with `MaceClubsApp`'s `memoryProbe` annotation compiled in - the one
build that has it, `monkey.probe.jungle`. The numbers are not close:

| Tier | Devices | Free at the peak |
| --- | --- | --- |
| 96KB | 5 | ~4.8KB |
| 128KB | 15 | 21-47KB |
| 512KB and up | 100 | 702KB (fenix7, the one recorded) |

So the pull-request check covers everything at or below 128KB - the tier where
the answer can change - and a nightly run covers all 120, which is what
catches that reasoning being wrong. A device that crashes or drops under 1KB
fails; under 4KB warns, which nothing currently does.

Those figures come from `tools/memory-baselines.json`, which `make
memory-headroom-record` writes. It is the file to read for what main measures
today; the tables further down record what particular changes cost when they
were made.

### The first screen is not where the app runs out

The probe reads memory three times: entering `getInitialView`, once the first
screen exists, and again with the settings menu built on top of it. The third
is the one that decides, and it is not close to the second:

| instinct2 | free |
| --- | --- |
| entering getInitialView | 13,640 |
| first screen built | 7,296 |
| settings menu on top | **2,064** |

So the real margin on a 96KB watch is about two kilobytes, not seven. That is
why #188's 208 bytes broke three of them, and why they broke *on the settings
menu* rather than at startup. The menu is built and dropped rather than shown
- `SettingsMenu.build()` is a pure function, so this needs nothing to drive
the watch's buttons - which makes it a proxy for the peak rather than the
peak itself.

Two consequences for the thresholds. The floor is 1KB, not 4KB, because
instinct2 ships today at 2,064 and works; a gate red on main is a gate
someone deletes. And a drop is measured as a share of what the device has
(10%, floor 128 bytes), because a flat 2KB threshold can never fire on a
watch with 2KB left - it would be dead before the check spoke. The same
build measured four times running returned the same number to the byte, so
there is no noise to leave room for.

### What the launcher icon costs

The single `loadResource()` call in `MaceClubsView` loads `launcher_icon.png`,
which is 295 bytes on disk and about 2.4KB in app memory - the decoded bitmap
plus the resource tables the first `loadResource()` brings with it. Measured
on instinct2:

| | with the icon | without |
| --- | --- | --- |
| first screen | 7,296 | 9,712 |
| settings menu on top | **2,064** | **4,432** |

More than double the headroom of the five watches that have the least, for a
decoration on one screen, so those five now compile it out
(`launcherIcon` / `noLauncherIcon`) and everything else keeps it. This is the
kind of thing the community advice is about - prefer drawn shapes to bitmaps,
and remember that one `loadResource()` is not free even when the file is
tiny. It was worth checking only because the peak number made the real margin
visible.

That table is the experiment, taken while the change was being made, and it is
the only place it is written down - `MaceClubsView` used to carry its own copy
and the two had drifted 400 bytes apart, which is how you end up unable to say
which figure was real. What main measures today is in
`tools/memory-baselines.json`: instinct2 records 4,832, not the 4,432 above.
The difference has not been chased down and would need re-measuring on a
machine with that device installed; the recorded file is the one to trust,
because a tool wrote it.

### What the nightly is for

The per-PR job checks the twenty devices at or below 128KB on the argument
that nothing above that can plausibly fail. The first nightly run over all
120 confirmed it - the 512KB tier reads about 693KB free with a peak around
702KB, and the 1.2MB devices more than that - which is the point: the
assumption is now checked rather than asserted.

It also found two defects in the check itself, which is the other reason to
run the thing you only think you need.

The simulator died ten devices into one shard, and every device after it
reported "the simulator was not reachable" - and the run announced those five
watches as *"cannot hold the app"*. A measurement failure reported as a
product failure is precisely the lie this check exists to prevent. Those are
now separate verdicts: both fail the run, because a device nobody measured
must never read as a device that passed, but they no longer say the same
thing. And a device that comes back unreachable now restarts the simulator
and retries once, rather than one crash writing off the rest of the shard.

**What this does not cover.** It measures the *probe* build, which carries
the probe, not the `.prg` that ships. #188's own regression lived only in the
shipped build - an empty annotated helper the probe build never had - so this
check would not have caught it. It catches changes to shared code, which is
nearly all of them; the per-device e2e suite remains the thing that actually
opens the menu on the watch.

`tools/memory-baselines.json` records each device's number, so a change that
costs headroom says so on the pull request that costs it. v0.13.4 took about
2.6KB from the Instinct 2 and shipped; that is the size of drop this now
reports. Re-record with `make memory-headroom-record` when a change is worth
its cost, and read the diff before committing it.

The baselines are recorded on the branch that introduced the probe, because
`monkey.probe.jungle` is what produces the numbers and it does not exist
before that branch. They are a floor for future changes, not an independent
blessing of the change that wrote them.

**They are Linux numbers, because that is where the gate runs.** The same
build reports different headroom on the two platforms: instinct2 measures
7,408 bytes on macOS and 7,816 in the CI container, and the gap runs from
zero to about 408 bytes depending on the device. Baselines recorded on macOS
and checked on Linux compare two different things, and every pull request
carries a drift line nobody caused - which is how a useful check becomes
noise. So `make memory-headroom` locally is for the absolute number and the
4KB floor; the baseline comparison belongs to CI, and a local run showing a
few hundred bytes of drift is the platform, not the change.

### 208 bytes is enough to break three watches

The probe's own first version cost 208 bytes and turned the reduced e2e
suite red on descentg1, instinct2 and instinct2x. It looked free: the
`memoryProbe` annotation compiled `reportMemory` to an empty body, and the
two calls in `getInitialView` went to nothing. An empty private method and
its call sites are still a method and still call sites.

The failure did not look like memory. Six test files passed, and the seventh
- the settings menu, the screen that allocates most on top of the main view
- read garbage and took the simulator's window with it, which reads exactly
like the OCR flake it was not. What identified it was the split:

| Device | Free at ready | Reduced suite |
| --- | --- | --- |
| descentg1, instinct2, instinct2x | 7,464 | fails |
| instinct2s | 7,592 | passes |

The three that failed are the three with the least headroom, and the one
that passed had 128 bytes more than they did, against a 208-byte
regression. That is the whole margin on these watches.

Two things follow. Annotate the *caller*, not a helper it calls, so the
build that ships has no call site to pay for - `MaceClubsApp` now has two
`getInitialView` bodies rather than one that calls a stub. And check the
claim rather than asserting it: `monkeyc -f monkey.jungle -d instinct2` on
this branch and on `main` produce a `.prg` of exactly the same size, which
is the property worth having. Build both from the same directory when you
do - the `.prg` embeds absolute source paths, so a worktree in a longer
path is 2,752 bytes bigger for no reason at all.

### The simulator is not a reliable process

It fails in at least three ways that have nothing to do with the app, all of
them green on a rerun with nothing changed:

| Symptom | Where |
| --- | --- |
| `monkeydo could not reach the simulator after 8 attempts` | any e2e job |
| `Segmentation fault (core dumped) simulator`, and a 1.8MB `tools/e2e/core` | the coverage job, and locally |
| `test did not finish before its parent and was cancelled` | any e2e job, when the app never paints |

Both entry points now retry, and both retry *only* this. `run-e2e.ts` runs a
file again once when the simulator window has gone; the coverage job runs
`tester.sh` again when the log says the simulator was unreachable. A file or
a suite that fails on its own terms fails immediately, because retrying a
real regression turns it into an intermittent one, which is worse than the
flake.

This matters more the more devices there are. Twelve jobs across two
workflows means a per-job flake rate that is nearly invisible still turns up
somewhere on most pull requests - and a suite that is red for reasons nobody
believes gets rerun by reflex, which is how a real failure eventually gets
waved through.

### What adding a device usually turns out to be

Almost never the OCR. Every menu assertion that named a title, or a row
other than the first, has eventually failed on some watch - and each time
the fix was the assertion:

- **Titles belong to Menu2.** It wraps them (`Rest options` reads as `Rest`
  on a 208px Forerunner 55), truncates them (`Choose e-`), or draws none at
  all (the Instinct Crossover). Assert a row instead.
- **Only the first row is reliably on screen.** A 163x156 Instinct 2S fits
  two. Scroll to the others with `pressUntilVisible`, which also tests the
  list rather than the first screenful of it.
- **The first row is the highlighted one**, which Menu2 draws inverted and
  the OCR reads worst of all - on a Forerunner 945 it vanishes entirely.
  `pressUntilVisible` steps off it, and checks before pressing, so devices
  that can read it in place do not move.

Two attempts went the other way, at the OCR. PR #173 grew 150 lines of TSV
parsing, positional merging and confidence filtering and broke three green
devices before being closed; a later attempt with an extra pass per screen
doubled the suite's runtime and timed out four jobs. Both devices they were
meant to rescue, `fr55` and `fr945`, went green on assertion changes alone.

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
