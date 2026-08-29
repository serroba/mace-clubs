# Contributing

## Code changes

Small, focused PRs — one feature or concern per PR, stacked when they depend on each other.
`make check` (format, lint, build, unit tests, FIT schema validation) and `make simulator-test`
should both pass. See the [PR template](.github/PULL_REQUEST_TEMPLATE.md) for what a PR
description should cover.

## Calibration recordings

Swing counting is tuned and validated against real recorded workouts (`tools/fixtures/`),
not synthetic data — see [docs/swing-counting.md](docs/swing-counting.md) for how that
works. More recordings, especially covering equipment, movements, or swing styles the
existing fixtures don't, directly help. There are two ways to contribute one.

**Before submitting either way:**

- Only submit your own recording.
- **Don't record with GPS/location enabled.** Recordings with position data are rejected
  (automatically, if submitted via the issue path below).
- Count your real per-set swings as accurately as you can — reviewing a video afterward is
  more reliable than counting live.
- Anything submitted becomes part of this public repository under its license.

**Trust model:** every contributed recording lands in `tools/fixtures/index.json`'s
`unlabelledFixtures` array — a raw profile, not ground truth — regardless of how confident
the claimed count is. Nothing there is used for tuning or accuracy claims. A maintainer
promotes a recording to the trusted `fixtures` array (renaming the claim to
`realSwingsPerSet`) only after reviewing it — comparing the on-device count against the
claim, checking the notes for caveats, and deciding it's trustworthy. This is deliberate:
self-reported counts from a recording a maintainer never watched shouldn't silently
influence tuning.

### Option A: open a PR directly

1. Record a workout with **Settings → Advanced → Swing calibration logging** enabled — this
   captures the raw accelerometer/gyroscope data the tuning tools need. Export the FIT file
   (via Garmin Connect, or however you normally get files off the watch).
2. Copy it into `tools/fixtures/` and add an entry to `tools/fixtures/index.json`'s
   `unlabelledFixtures` array with your claimed `realSwingsPerSet` (per work set, in order),
   equipment, movement, and any caveats in `notes`. Follow the shape of an existing entry.
3. Open a PR. `.gitignore`'s blanket `*.fit` has a `!tools/fixtures/*.fit` exception, so the
   file will be picked up.

This is the most direct path if you're comfortable with git — no waiting on automation.

### Option B: open a "Calibration recording" issue

If you'd rather not touch git, [open a Calibration recording
issue](https://github.com/serroba/mace-clubs/issues/new?template=calibration-recording.yml).
All that's actually required: attach your FIT file, say how many swings you really did per
set, and check the two consent boxes — equipment, movement, and weight are read straight out
of the file, so you only need to fill those in if the automated detection gets something
wrong. A bot (`.github/workflows/calibration-intake.yml`, running
`tools/process-calibration-issue.ts`) validates it within a few minutes and comments back:

- **On a problem** (missing consent, no attachment, GPS data detected, unparseable FIT),
  it explains what to fix — edit the issue and it re-checks automatically.
- **On success**, it opens a draft PR adding the recording as an `unlabelledFixtures` entry,
  with a chart comparing the on-device detected count against your claimed count so a
  reviewer can see at a glance whether it's worth a closer look.

Nothing is auto-merged either way — a maintainer always reviews the draft PR before anything
lands on `main`.
