# Mace & Clubs

[![CI](https://github.com/serroba/mace-clubs/actions/workflows/ci.yml/badge.svg)](https://github.com/serroba/mace-clubs/actions/workflows/ci.yml)

**Website:** [serroba.github.io/mace-clubs](https://serroba.github.io/mace-clubs/) ·
**Downloads:** [GitHub Releases](https://github.com/serroba/mace-clubs/releases)

A Garmin Connect IQ workout app for steel mace and Indian club training. Primary
target is the **Instinct 3 Solar**; the manifest supports 120 Garmin wearables
(Connect IQ API 3.1+), and CI compiles every one of them.

## Features

- Records a "Mace & Clubs" activity to Garmin Connect (sport: Training / Strength)
- Configurable metronome (20–240 bpm) with tone and vibration cues
- Set counter written to the FIT file as a developer field
- Tempo, tone, and vibration configurable from the Garmin Connect phone app

## Controls

| Button | Idle | Recording | Paused |
|---|---|---|---|
| SELECT | Start workout | Mark a set (free training) | Save & exit |
| BACK | Quit | Pause | Resume (unless finished) |
| UP / DOWN | Choose workout preset | Tempo ±5 bpm | — |

Interval presets (e.g. 5 × 2:00 work / 1:00 rest) call work and rest with tone and
vibration cues, run the metronome only during work, and count sets automatically.

## Development

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) (install via
the SDK Manager, which also provides the Instinct 3 device files) and a developer key
(`Connect IQ: Generate a Developer Key` in the VS Code extension, or `openssl`).

```sh
# Build
monkeyc -f monkey.jungle -d instinct3solar45mm -o bin/mace-clubs.prg -y /path/to/developer_key

# Run in the simulator (start `connectiq` first)
monkeydo bin/mace-clubs.prg instinct3solar45mm

# Unit tests
monkeyc -f monkey.jungle -d instinct3solar45mm -o bin/mace-clubs-test.prg -y /path/to/developer_key --unit-test
monkeydo bin/mace-clubs-test.prg instinct3solar45mm -t
```

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

- Small, focused PRs — one feature or concern per PR, stacked when they depend on each other.
- TDD where the code is testable: unit tests (`(:test)` functions) accompany or precede the
  logic they cover. UI and session recording are verified in the simulator.
