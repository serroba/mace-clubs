# Connect IQ Store listing — DRAFT (review before submitting)

Upload file: `mace-clubs.iq` from the v0.9.0 GitHub release.

Note: the store renders these fields as plain text — no markdown emphasis.

## App name
Mace and Clubs

## Summary (one line)
Metronome, interval timer, and swing tracking for mace, club, and bulava training.

## Description
Keep your swing cadence without watching the screen. Mace and Clubs is a
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
continuous swinging with an on-watch swing counter powered by the
accelerometer. Detected swings show live while you work and are saved with
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
- Optional motion-capture logging records accelerometer data each second
  for offline swing analysis

## What's new — v0.9.0
Mace and Clubs now trains the way the traditions do.

Pick your implement, then your movement. The mace offers the 360 and the
10-to-2, clubs the mill and shield cast, and the new bulava (single heavy
club) the mill, reverse mill, bullwhip, and the traditional Combo. Your
movement is saved with every set.

The Combo calls its sequence on your wrist: an accented pulse on each
movement change and a double pulse when it is time to switch hands, with
the current hand and movement on screen. Beats per movement are
configurable (default 4-4-2).

During any rest, hold MENU to switch movement or working side for the next
set. Single-side sets are tallied per hand and the workout summary shows an
L/R balance, following the tradition of giving each hand the same number
of sets.

New Challenge presets: 5:00 or 10:00 of continuous swinging, scored by a
new accelerometer swing counter. Detected swings replace metronome rounds
on screen and are saved with the activity per set and in total. The counter
can also be enabled for regular sessions from Settings.

Also: each implement keeps its own default weight (including the new
bulava), and the training screens were reworked to stay clear of the
Instinct subwindow.

Hero image: `docs/store-assets/hero-v0.4.0.png` (1440×720 PNG, under 2 MB) —
consider refreshing for v0.9.0.

## Category
Health & Fitness

## Permissions (shown to users)
- Records activities (FIT) and writes custom FIT data fields
- Sensor / accelerometer access (for heart rate and optional motion capture)

## Support
- 120 Connect IQ devices, API 3.1+
- Language: English

## Screenshots (need at least one)
Capture from the simulator or watch:
1. Start screen — workout name + `50 bpm | 4-2`
2. Movement picker after choosing an implement
3. In-workout — timer, bpm, rounds / HR
4. Combo work screen — `L REV MILL` with bpm below
5. Challenge screen — swing count in place of rounds
6. Paused summary — sets, L/R balance, per-set line
