# Mace & Clubs

[![CI](https://github.com/serroba/mace-clubs/actions/workflows/ci.yml/badge.svg)](https://github.com/serroba/mace-clubs/actions/workflows/ci.yml)

**Website:** [serroba.github.io/mace-clubs](https://serroba.github.io/mace-clubs/) ·
**Downloads:** [GitHub Releases](https://github.com/serroba/mace-clubs/releases)

A Garmin Connect IQ workout app for steel mace and Indian club training. Primary
target is the **Instinct 3 Solar**; the manifest supports 120 Garmin wearables
(Connect IQ API 3.1+), and CI compiles every one of them.

## Features

- Records a "Mace & Clubs" activity to Garmin Connect (sport: Training / Strength)
- Configurable metronome (5–240 bpm) with tone and vibration cues
- Five-second start delay and advance warning before each new work interval
- Optional on-watch smoothness score with a 12-session local trend; no account,
  network request, or smoothness data upload
- On-watch history of the last 20 sessions, browsable from Settings with the
  per-set scores and the implement each session was recorded with
- Optional accelerometer swing counter, plus 5:00 and 10:00 Challenge presets
  (after the traditional timed max-swing gada competitions) where counting is
  always on and detected swings replace metronome rounds on screen
- Optional per-set exercise load exposure from wrist motion, recording dynamic
  acceleration exposure, peak, active seconds, and weight-volume when swing
  counting is also enabled; values are descriptive proxies, not tendon force
- Optional one-second wrist-motion intensity and peak charts in Garmin Connect;
  enable Motion charts in Settings (additional battery use)
- Watch-wrist and equipment metadata written into each FIT session
- Set total written to the FIT session, with work sets and timed rests recorded
  as separate lap boundaries for analysis in Garmin Connect and exported FIT files

## Local workout report

Garmin's original FIT export contains the app's opt-in per-second motion
features even though Garmin Connect does not graph them. Generate a private,
self-contained report locally from either the downloaded ZIP or a raw FIT file:

```sh
python3 -m venv tools/.venv
tools/.venv/bin/pip install -r tools/requirements.txt
tools/.venv/bin/python tools/report_fit.py ~/Downloads/activity.zip
```

The resulting HTML stays on your computer and combines motion intensity, heart
rate, work/rest phases, and per-set smoothness. Motion exposure is a wrist-motion
measurement, not an estimate of tendon force.
- Tempo, tone, and vibration configurable from the Garmin Connect phone app

## Controls

| Button | Idle | Recording | Paused |
|---|---|---|---|
| SELECT | Start workout | Free training: switch work/rest | Save & exit |
| BACK | Quit | Pause | Resume (unless finished) |
| UP / DOWN | Choose workout preset | Tempo ±5 bpm | UP: discard and return home |
| MENU | Settings | Free rest: movement/side/discard menu; otherwise discard and return home | Discard and return home |

Interval presets (e.g. 5 × 2:00 work / 1:00 rest) call work and rest with tone and
vibration cues, run the metronome only during work, and count sets automatically.
Challenge presets are one continuous work interval with no rest; swing counting
is forced on, total swings are written to the session (`total_swings`) and each
work lap (`swing_count`), and swings during rest or pause never count.
The Custom preset defaults to 5 × 2:00 work / 2:00 rest. Configure it directly
on the watch from MENU → Settings → Custom workout, or from the Garmin Connect
phone app. The on-watch editor walks through sets, work duration, and rest
duration; duration controls move in 30-second steps.
In Free training, SELECT completes the current set and enters REST; press SELECT
again to begin the next WORK phase. Rest keeps activity and heart-rate recording
running. BACK remains a true whole-session pause/resume control.
Garmin may label recorded set and rest boundaries as laps or splits. Work laps
carry their one-based `set_number`; rest laps carry zero. Each boundary also
records its work/rest phase, duration, implement weight, watch wrist, and
set smoothness where available. Starting a workout asks for equipment and then
movement; the movement list follows the implement (mace: 360, 10-to-2,
flow/other; clubs: mill, shield cast, flow/other; bulava: combo, mill,
reverse mill, bullwhip, flow/other) and the choice is saved with every work
block. The bulava **Combo** is the traditional combination set — mill,
reverse mill, bullwhip on one hand, then the other. The metronome calls the
sequence: an accent on each movement change, a double pulse on the hand
switch, and the screen shows the current hand and movement (e.g. `L REV
MILL`). Beats per movement are phone-configurable (default 4-4-2), and combo
sets always record an alternating working side. During a free-training rest, MENU offers switching the
movement or working side for the next set, so left/right ladders only need one
press per rest. Working side is also configurable in Settings, separately from
watch wrist. Single-side work sets are tallied per hand and the paused and
completed summaries show an `L3/R2` balance tag, following the
traditional convention of giving each hand the same number of sets. The paused and completed screens provide an
on-watch set summary; use UP/DOWN to inspect individual work/rest durations.
Connect IQ does not
expose Garmin's native strength-set message type, so the Strength summary can
still show `-- Sets`.

## Development

Requires:

- a Java runtime available to the shell (`java -version` must succeed; a Homebrew
  OpenJDK install works even when macOS's `/usr/libexec/java_home` cannot find it);
- the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/), installed via SDK
  Manager with the Instinct 3 Solar 45 mm device files; and
- a developer key (`Connect IQ: Generate a Developer Key` in the VS Code extension,
  or generate one with `openssl`).

`monkeyc`, `monkeydo`, and `connectiq` must be on `PATH`. SDK Manager does not always
add them automatically. On macOS, add the selected SDK's `bin` directory for the
current shell (replace the example with the directory installed on your machine):

```sh
export PATH="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0/bin:$PATH"
```

```sh
# Build
monkeyc -f monkey.jungle -d instinct3solar45mm -o bin/mace-clubs.prg -y /path/to/developer_key

# In another terminal, launch the simulator and leave it running
connectiq

# Build, then load the app into the running simulator
monkeydo bin/mace-clubs.prg instinct3solar45mm

# Unit tests
monkeyc -f monkey.jungle -d instinct3solar45mm -o bin/mace-clubs-test.prg -y /path/to/developer_key --unit-test
monkeydo bin/mace-clubs-test.prg instinct3solar45mm -t
```

If `monkeyc` reports that it cannot locate a Java runtime but Java is installed, ensure
the JDK's `bin` directory precedes `/usr/bin` on `PATH` and re-run `java -version`
before retrying. Homebrew's default location on Apple Silicon is
`/opt/homebrew/opt/openjdk/bin`. If `monkeydo` cannot connect, confirm that the Connect
IQ simulator is already open and has finished starting.

For the complete pre-push quality check, install the formatter and linter described
below, then run:

```sh
make check              # XML, formatting, lint, app build, and test build
make simulator-test     # also execute the tests in a running simulator
make coverage           # function coverage of the unit tests (see below)
```

Enable the repository's version-controlled Git hooks once per clone:

```sh
make install-hooks
```

The pre-commit hook checks only relevant staged files: XML well-formedness, the
FIT XSD/Schematron contract, Monkey C formatting and linting, GitHub workflow
syntax with `actionlint`, whitespace errors, unexpectedly large files, and
private-key material. Install `actionlint` with `brew install actionlint` before
editing workflows. The pre-push hook runs the complete `make check` suite. Hooks
provide fast local feedback but can be bypassed, so CI repeats the authoritative
checks.

`make check` validates `resources/fitfields.xml` against the official
`resources.xsd` bundled with the selected Connect IQ SDK. It then applies the
declarative Schematron rules in `tools/schemas/fitfields.sch` for field-id,
display-target, ordering, localization, and chart presentation constraints.
The normal Monkey C builds remain the native check that localized resources
resolve and the declared FIT fields integrate with Garmin's compiler.

The Monkey C suite also runs a deterministic 50-second workout containing
stillness, smooth swings, rest, irregular swings, and a deliberate acceleration
spike. Those curves are generated on-watch and traverse the same production
feature, smoothness, exposure, and swing-counting path as real sensor samples.
Behavioral assertions cover phase totals, rest exclusion, smoothness contrast,
and peak retention. Python is limited to building a reviewable FIT/HTML/SVG
fixture for the presentation contract; those artifacts are attached to each CI
run as `synthetic-workout-visuals`.

`make coverage` reports which functions the unit tests actually execute. It
requires `monkey-c-coverage` on `PATH` (from the same monkey-c-rs project as
the formatter and linter; until it is upstream, install with
`cargo install --path <monkey-c-rs>/monkey-c-coverage`) and a running
simulator. View and delegate code intentionally reports near zero — that
layer is verified in the simulator, not by unit tests.

The Makefile generates an ignored local developer key when `developer_key.der` is
absent. It discovers a working Java runtime, finds `monkeyc` and `monkeydo` from
`PATH` or Garmin SDK Manager's `current-sdk.cfg`, and finds the Rust formatter,
linter, and `rafiki` in either `PATH` or `~/.cargo/bin`. This keeps `make check`
working in non-interactive shells that have not loaded your shell profile.
Override `DEVICE`, `DEVELOPER_KEY`, `JAVA`, `MONKEYC`, `MONKEYDO`, `FORMATTER`,
`LINTER`, or `RAFIKI` when needed.

### Formatting and linting

Source is formatted with [monkey-c-formatter and linted with monkey-c-linter](https://github.com/bombsimon/monkey-c-rs)
(install with `cargo install --git https://github.com/bombsimon/monkey-c-rs monkey-c-formatter monkey-c-linter`).
CI enforces both:

```sh
monkey-c-formatter source        # format in place
monkey-c-linter --fix source     # lint with auto-fixes
```

### Releases

Pushing a `v*` tag builds the store-ready `.iq` (signed with the developer key from
the `CIQ_DEVELOPER_KEY` repo secret) plus an Instinct 3 sideload `.prg`, and attaches
both to a GitHub Release:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

## Workflow

The smoothness model, privacy boundary, equations, assumptions, and validation
plan are documented in [docs/smoothness-physics.md](docs/smoothness-physics.md).
The exercise-aware load fields and their interpretation are documented in
[docs/load-exposure.md](docs/load-exposure.md).

- Small, focused PRs — one feature or concern per PR, stacked when they depend on each other.
- TDD where the code is testable: unit tests (`(:test)` functions) accompany or precede the
  logic they cover. UI and session recording are verified in the simulator.
