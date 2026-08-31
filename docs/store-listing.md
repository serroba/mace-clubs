# Connect IQ Store listing — DRAFT (review before submitting)

<!-- generated:upload -->
Upload file: `mace-clubs.iq` from the v0.16.0 GitHub release.
<!-- /generated:upload -->

Note: the store renders these fields as plain text — no markdown emphasis.

## App name
Mace and Clubs

## Summary (one line)
Metronome, interval timer, and swing tracking for mace, club, and bulava training.

## Description
Keep your swing cadence without watching the screen. Mace & Clubs is a
metronome and interval timer built for steel mace, Indian club, and bulava
training, shaped by the way these implements are traditionally trained.

Set your tempo and the watch holds it with a wrist buzz (and an optional
beep). The first beat of each loop is accented, so you feel when to switch
sides instead of reading the screen.

Pick your implement, then your movement: 360 and 10-to-2 for the mace, mill
and shield cast for clubs, and mill, reverse mill, bullwhip, or the
traditional combination set for the bulava. Your choice is saved with every
work set in the activity.

The bulava Combo calls the whole sequence for you: mill, reverse mill, and
bullwhip on one hand, then the other. Each movement change gets an accented
pulse and the hand switch gets a distinct double pulse, with the current
hand and movement on screen. Beats per movement are configurable from your
phone.

Training the old way means giving each hand the same work: switch movement
or working side during any rest without leaving the session, and the
summary shows a left/right set balance at a glance.

Challenge presets bring the traditional timed test: 5 or 10 minutes of
continuous mace swinging with an on-watch swing counter powered primarily by
the gyroscope. Detected swings show live while you work and are saved with
the activity per set and in total.

Also included:
- Metronome from 5 to 240 bpm, adjustable mid-workout; steady cadence or
  the classic club 4-2 pattern
- Interval presets with work and rest, free training with explicit
  work/rest phases, or a custom shape set from your phone or the watch
- Five-second start countdown and an advance warning before each work
  interval
- Rounds, heart rate, and set count on screen while you train
- Saves to Garmin Connect as a strength activity: per-set movement, side,
  implement weight, durations, and set count
- Optional on-watch smoothness score with a private 12-session trend;
  nothing is uploaded
- Browse your last 20 sessions on the watch, with per-set smoothness scores
  and the implement each was recorded with
- Optional per-set load exposure from wrist motion: exposure, peak, active
  seconds, and weight-volume, saved with the activity
- Optional calibration logging records accelerometer and gyroscope data
  for private offline swing analysis

<!-- generated:whatsnew -->
## What's new — v0.16.0

- Stop the paused headline hiding behind the Instinct's subwindow
- Make the app-drawn screens scale to the device, and adapt the controls to it
- Fix the app crashing on workout start on every CIQ 3.1 device
<!-- /generated:whatsnew -->

## Category
Health & Fitness

## Permissions (shown to users)
- Records activities (FIT) and writes custom FIT data fields
- Sensor access (for heart rate, gyroscope swing counting, and optional motion capture)

## Support
- Instinct 3 Solar 45 mm, the physically validated 25 Hz gyroscope target
- Language: English

## Screenshots (need at least one)
`make release-shots VERSION=x.y.z` captures items 1-3 and 6 automatically for
instinct3solar45mm, fenix7 and venu3 into `docs/store-assets/v<version>/`; its
manifest.json lists which of the below still need a hand capture and why.

1. Start screen — workout name + `50 bpm | 4-2`
2. Movement picker after choosing an implement
3. In-workout — timer, bpm, rounds / HR
4. Combo work screen — `L REV MILL` with bpm below
5. Challenge screen — swing count in place of rounds
6. Paused summary — sets, L/R balance, per-set line
7. History list — saved sessions with dates and scores
