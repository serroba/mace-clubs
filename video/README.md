# video

Video analysis for mace/gada swing footage, as a companion to the sensor-based
work elsewhere in this repo (`tools/fixtures/`, `tools/replay-swing.ts`).
Starting as a local, computer-only toolkit; may grow into something more
later (its own app, eventually).

## Why

The FIT recordings tell us *when* the accelerometer/gyro crossed a threshold,
but not what the swing actually looked like. Video adds a visual ground truth
- which plane the swing moves in, what a "double" actually looks like, where
pickup/putdown motions happen - that the sensor data alone can't show.

## Goal

Align video footage with the FIT sensor timeline from the same recording, so
a moment in the video ("this swing") can be cross-referenced against the exact
accelerometer/gyro samples and counter decision (counted / rejected / why) at
that instant - and vice versa.

## Layout

- `videos/` - source clips. **Not tracked in git** (gitignored): this repo's
  pre-commit hook hard-blocks any staged file over 1 MiB
  (`tools/pre_commit.sh`), and video clips routinely exceed that. Keep your
  own backup of anything here - git won't have a copy. Only the *analysis*
  (this README, scripts, and once established, alignment metadata) lives in
  version control.
- `frames/` - extracted frame stills and audio visualizations, per video
  (gitignored, regenerate with `scripts/extract.sh`)
- `audio/` - extracted audio tracks (gitignored, same reason)
- `fixtures/` - once a video's FIT-time alignment is established, the
  *metadata* (which FIT fixture, what offset, how it was derived) goes here
  as JSON, same convention as `../tools/fixtures/`. The video file itself
  stays wherever you keep it locally, referenced by path/checksum, not
  copied into the repo.
- `scripts/` - processing scripts (frame extraction, beep detection, etc.)

## Syncing video to FIT time

No shared clock between phone and watch, so alignment has to come from a
signal present in both. Candidate: the watch's audible tone (metronome cue /
beat beep), which the video's audio track should also pick up.

Tried so far (`videos/2026-08-22-recB-segment.mp4`, a ~53s segment of
`tools/fixtures/24071684170_ACTIVITY.fit` (`recB`) - 5/5/10/10
singles-then-doubles):

- `ffmpeg showspectrumpic` on the audio shows a clearly repeating narrow-band
  tonal transient (~3.7kHz fundamental with harmonics near 7.4/11/15kHz),
  visually distinct from the broadband whoosh/impact of the swings themselves
  - promising as a sync signal.
- A naive bandpass (3.2-4.2kHz) + envelope peak-pick gave only 5 sparse,
  unevenly-spaced hits - too noisy, the swing whooshes have energy in that
  band too.
- Isolating the higher harmonic (7-8kHz, further from whoosh energy, which is
  low-frequency dominant) gave 34 candidates with inconsistent spacing and no
  clean periodicity - still not a reliable detector.

**Confirmed (2026-08-23):** user confirmed the cue mode was "cycle top, once
per loop." Autocorrelation of the narrowband (3550-3950Hz) envelope found a
strong, consistent periodicity at **~4.8s** - matching exactly what the
app's default settings (50 bpm, 4 beats/loop -> 4 x 60/50 = 4.8s) would
produce. Extracting a template from one confident instance (~21.08s) and
cross-correlating the full track against it gave 11 clean, evenly-spaced
detections (intervals 4.66-4.99s, mean ~4.83s) - a solid, repeatable
detector for *this* recording's cue tone. `Attention.playTone()` itself uses
Connect IQ's device-defined tone constants (`TONE_LOUD_BEEP` etc.), so the
exact frequency/waveform is firmware, not something read from source - the
template has to come from the recording itself each time, not a fixed
reference.

**Still open - this doesn't fully close the loop yet:** knowing the cue
*period* isn't the same as knowing its absolute *phase*. The video is a
~53s segment of a longer session with no embedded creation timestamp
(WhatsApp strips it on send/compress - confirmed via `ffprobe`, no
`creation_time` tag), and the metronome's cue timing is not written to any
FIT field, so there's no independent anchor tying "cue N in the video" to
"cue N since session start" in FIT time. Two ways to actually close it:

1. **Align on the swings themselves, not the cue.** The real shared event
   between video and FIT is the swing impact/whoosh, visible in the frames
   and audible in the track, and directly recorded as accel peaks in the
   FIT file. Matching the *pattern* of swing timestamps (video) against the
   accel peak pattern (FIT) - e.g. cross-correlating inter-swing-interval
   sequences - doesn't need any phase assumption, since both come from the
   same physical events. Likely the more robust path.
2. **Or, get an anchor deliberately on the next recording:** e.g. start the
   video recording before the workout starts and catch the very first cue
   or the start-countdown vibration/tone on camera, or have the phone's
   clock and the FIT start_time compared directly (needs a video app that
   doesn't strip creation_time, unlike WhatsApp's re-encode).

## Next steps

1. Try approach 1 above: extract swing-impact timestamps from the video
   (audio transient + frame motion) and cross-correlate against this
   segment's accel-peak pattern from the `recB` FIT fixture.
2. If that converges, add this video (with its resolved FIT-time offset) to
   `fixtures/` as a video+FIT+offset triple, same convention as
   `../tools/fixtures/`.
3. For future recordings: avoid sharing via WhatsApp if possible (strips
   metadata) - AirDrop/cable transfer keeps `creation_time`, which would
   make anchoring trivial.
