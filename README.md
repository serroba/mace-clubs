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
- Optional accelerometer swing counter, plus 5:00 and 10:00 Challenge presets
  (after the traditional timed max-swing gada competitions) where counting is
  always on and detected swings replace metronome rounds on screen
- Watch-wrist and equipment metadata written into each FIT session
- Set total written to the FIT session, with work sets and timed rests recorded
  as separate lap boundaries for analysis in Garmin Connect and exported FIT files
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
flow/other; clubs: mill, shield cast, flow/other) and the choice is saved with
every work block. During a free-training rest, MENU offers switching the
movement or working side for the next set, so left/right ladders only need one
press per rest. Working side is also configurable in Settings, separately from
watch wrist. Single-side work sets are tallied per hand and the paused and
completed summaries show a `hands L3 / R2` balance line, following the
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
```

The Makefile generates an ignored local developer key when `developer_key.der` is
absent. Override `DEVICE`, `DEVELOPER_KEY`, `MONKEYC`, or `MONKEYDO` when needed.

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

- Small, focused PRs — one feature or concern per PR, stacked when they depend on each other.
- TDD where the code is testable: unit tests (`(:test)` functions) accompany or precede the
  logic they cover. UI and session recording are verified in the simulator.
