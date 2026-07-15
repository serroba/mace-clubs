# Mace & Clubs

A Garmin Connect IQ workout app for steel mace and Indian club training, targeting the
**Instinct 3 Solar** (45mm / 50mm).

## Features

- Records a "Mace & Clubs" activity to Garmin Connect (sport: Training / Strength)
- Configurable metronome (20–240 bpm) with tone and vibration cues
- Set counter written to the FIT file as a developer field
- Tempo, tone, and vibration configurable from the Garmin Connect phone app

## Controls

| Button | Idle | Recording | Paused |
|---|---|---|---|
| SELECT | Start workout | Mark a set | Save & exit |
| BACK | Quit | Pause | Resume |
| UP / DOWN | Tempo ±5 bpm | Tempo ±5 bpm | — |

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

## Workflow

- Small, focused PRs — one feature or concern per PR, stacked when they depend on each other.
- TDD where the code is testable: unit tests (`(:test)` functions) accompany or precede the
  logic they cover. UI and session recording are verified in the simulator.
