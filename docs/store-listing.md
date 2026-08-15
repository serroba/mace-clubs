# Connect IQ Store listing — DRAFT (review before submitting)

Upload file: `mace-clubs.iq` from the v0.10.0 GitHub release.

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
- Browse your last 20 sessions on the watch, with per-set smoothness scores
  and the implement each was recorded with
- Optional per-set load exposure from wrist motion: exposure, peak, active
  seconds, and weight-volume, saved with the activity
- Optional motion-capture logging records accelerometer data each second
  for offline swing analysis

## What's new — v0.10.0
Your training history now lives on the watch.

Open History from Settings to browse your last 20 sessions, newest first,
each with the date and its average smoothness score. Open one and UP/DOWN
scrolls through the per-set scores, labelled with the implement, quantity,
and weight they were recorded with, so a 6 kg bulava session is never
compared against a 10 kg mace one. It all stays on the watch.

The idle screen now shows the last comparable session's smoothness and its
trend before you start, so you know what you are chasing. It appears once
there is history for the implement, movement, and side you have selected.

New optional load exposure: with it enabled, each work set records the
dynamic acceleration exposure of your wrist, its peak, how many seconds
were actually active, and weight-volume (implement kilograms times detected
swings). The set browser shows a compact L token and the full values are
saved with the activity for offline analysis. These are descriptive
measurements from a wrist sensor, not tendon force, technique quality, or
injury risk. It uses extra battery and is off by default.

Hero image: `docs/store-assets/hero-v0.4.0.png` (1440×720 PNG, under 2 MB) —
consider refreshing for v0.10.0.

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
7. History list — saved sessions with dates and scores
