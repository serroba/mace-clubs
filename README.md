# Mace & Clubs

[![CI](https://github.com/serroba/mace-clubs/actions/workflows/ci.yml/badge.svg)](https://github.com/serroba/mace-clubs/actions/workflows/ci.yml)

**Website:** [serroba.github.io/mace-clubs](https://serroba.github.io/mace-clubs/) ·
**Downloads:** [GitHub Releases](https://github.com/serroba/mace-clubs/releases)

A Garmin watch app for steel mace, Indian club, and bulava training, shaped by
the way these implements are actually trained.

Set your tempo and the watch holds it with a wrist buzz, so you keep your
cadence without looking at your arm. Pick your implement and it offers that
implement's movements — 360s and 10-to-2s for the mace, mills and casts for
clubs, the traditional combination set for the bulava. Each hand's sets are
counted separately, because the tradition says they should be. Finish, and the
session is in Garmin Connect with every set labelled by what you actually did.

**Runs on 120 Connect IQ watches. Swing counting is validated on the Instinct 3
Solar 45 mm.** Everything else — the metronome, intervals, movement and side
tracking, and activity recording — behaves the same on every one of them. Swing
counting is the exception: its detector is tuned against labelled recordings
from that one watch and its 25 Hz gyroscope. Elsewhere it still runs, falling
back to the accelerometer where there is no gyroscope, but the counts have not
been checked against known-correct numbers. Contributing a recording from your
own watch is the thing that changes that — see
[CONTRIBUTING.md](CONTRIBUTING.md#calibration-recordings).

## What it does

**Keeps the tempo.** A metronome from 5 to 240 bpm, adjustable mid-workout,
with tone and vibration cues and an accent on the first beat of each loop. For
the bulava combo it calls the whole sequence: a pulse on each movement change,
a double pulse on the hand switch.

**Runs the session.** Interval presets with work and rest, free training with
explicit work/rest phases, a custom shape set from the phone or the watch, and
5:00 and 10:00 Challenge presets after the traditional timed gada competitions.
Five-second start countdown, and a warning before each work interval.

**Counts the swings.** An optional gyroscope-primary swing counter, always on
for challenges, with detected swings shown live and saved per set and in total.
Rep mode makes that count the primary metric, with UP/DOWN correction before a
set is committed.

**Remembers the practice.** Your last 20 sessions stay on the watch, browsable
from Settings with each session's per-set scores and implement. An optional
Rhythm Score tracks how repeatable your motion is across a 12-session trend —
no account, no network request, nothing uploaded.

**Records what you did.** Work sets and timed rests become separate lap
boundaries, each carrying its movement, working side, implement weight,
duration, and Rhythm Score. Optional per-second charts in Garmin Connect cover
cumulative swings, swing cadence, and wrist-motion intensity.

**Measures exposure, carefully.** An optional per-set record of wrist motion —
exposure, peak, active seconds, weight-volume. These are descriptive proxies
for what your wrist did, not estimates of tendon force, and
[docs/load-exposure.md](docs/load-exposure.md) says exactly what they are.

## Controls

| Button | Idle | Recording | Paused |
|---|---|---|---|
| SELECT | Start workout | Free/Rep mode: switch work/rest | Save & exit |
| BACK | Quit | Pause | Resume (unless finished) |
| UP / DOWN | Choose workout preset | Tempo ±5 bpm; Rep mode: count ±1 | Browse sets |
| MENU | Settings | Free rest: movement/side/discard menu; otherwise discard and return home | Discard and return home |

In free training, SELECT ends the current set and enters REST; SELECT again
begins the next work phase. BACK stays a true whole-session pause, separate
from that boundary. During a rest, MENU switches the movement or working side
for the next set, so a left/right ladder needs one press per rest.

What each workout shape does, how movements and sides are chosen and recorded,
and what reaches Garmin Connect are in
[docs/training-reference.md](docs/training-reference.md).

## Development

Requires:

- Node.js 22.8+ for the local FIT tooling and its type stripping
  (`npm ci --prefix tools` once, then `make tools-check` runs the TypeScript
  typecheck, lint, and tests);
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

### Local workout report

Garmin's original FIT export contains the app's opt-in per-second motion
features even though Garmin Connect does not graph them. Generate a private,
self-contained report locally from either the downloaded ZIP or a raw FIT file:

```sh
npm ci --prefix tools
node --experimental-strip-types tools/report-fit.ts ~/Downloads/activity.zip
node --experimental-strip-types tools/validate-workout.ts ~/Downloads/activity.zip
```

The resulting HTML stays on your computer and combines motion intensity, heart
rate, swing cadence, individual swing markers, work/rest phases, normalized set
rhythm, per-set Rhythm Score, and its rolling form where the FIT file contains
it. Enabling both the local Rhythm Score and motion research export records
the rolling score for Garmin Connect and this report. Motion exposure is a wrist-motion
measurement, not an estimate of tendon force. The validator reports structural
errors, missing series, metadata gaps, and a transparent data-quality score; use
`--json` for automation. Its findings describe recording quality, not injury risk.

For labelled calibration recordings, tune and verify the shared gyro detector
against independently known per-set counts with:

```sh
node --experimental-strip-types tools/tune-swing-counter.ts
```

The current shared model reproduces the labelled mace sets `[5, 5, 10, 10]`
and `[60, 60]`. These fixtures test detector replay; a fresh physical-watch
workout remains the final check for live sensor behavior.


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

See [CONTRIBUTING.md](CONTRIBUTING.md) for PR conventions and how to contribute a
calibration recording. The model behind the Rhythm Score, its privacy boundary, equations, assumptions, and validation
plan are documented in [docs/smoothness-physics.md](docs/smoothness-physics.md).
The exercise-aware load fields and their interpretation are documented in
[docs/load-exposure.md](docs/load-exposure.md). The gyro-primary mace swing
detector, its tuning evidence, and how to replay-test a change against real
recordings are documented in [docs/swing-counting.md](docs/swing-counting.md).
A BDD-style e2e framework drives the real simulator on macOS and asserts on
what's on screen (OCR + screenshot baselines) - see
[docs/e2e-testing.md](docs/e2e-testing.md).

- Small, focused PRs — one feature or concern per PR, stacked when they depend on each other.
- TDD where the code is testable: unit tests (`(:test)` functions) accompany or precede the
  logic they cover. UI and session recording are verified in the simulator.
