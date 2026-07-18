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
- Set counter written to the FIT file as a developer field
- Tempo, tone, and vibration configurable from the Garmin Connect phone app

## Controls

| Button | Idle | Recording | Paused |
|---|---|---|---|
| SELECT | Start workout | Mark a set (free training) | Save & exit |
| BACK | Quit | Pause | Resume (unless finished) |
| UP / DOWN | Choose workout preset | Tempo ±5 bpm | — |
| MENU | Settings | Discard and return home | Discard and return home |

Interval presets (e.g. 5 × 2:00 work / 1:00 rest) call work and rest with tone and
vibration cues, run the metronome only during work, and count sets automatically.

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
