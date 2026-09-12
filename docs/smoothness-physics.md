# The Rhythm Score: physics and interpretation

> **Naming.** Users see this as the **Rhythm Score**. In the code it is still
> smoothness — `Smoothness.mc`, `SmoothnessLog.mc`, `smoothnessEnabled`,
> `FitSmoothness` — because that is what the quantity is, and renaming the
> internals buys nothing. This document is about the quantity, so it says
> smoothness throughout. See [brand.md](brand.md).

## Purpose and privacy boundary

The Rhythm Score is an on-watch estimate of how evenly the athlete's swings
are spaced during one workout. Raw accelerometer and gyroscope samples never
leave the watch through this feature. The app keeps only compact session
summaries in Connect IQ application storage; saving the activity can still
include the existing opt-in one-second motion fields in the user's FIT file.

The score is not a measurement of mace-head force, joint loading, technique,
or injury risk. It is the timing of detected swings and nothing more, and it
inherits whatever the detector gets wrong: a missed swing lengthens a gap, and
a false one splits it.

## What it measures

The gaps between detected swings, and how evenly they are spaced.

For a span of swings at times `t0 < t1 < ... < tn`, the gaps are
`g_i = t_i - t_(i-1)`, and the score is the coefficient of variation of those
gaps, inverted onto 0-100:

```text
score = clamp(100 - 100 * sd(g) / mean(g), 0, 100)
```

100 is a metronome. Scatter over mean is the right shape because it is
scale-free: swinging slowly and evenly scores the same as swinging quickly and
evenly, which is what makes this a rhythm score rather than a pace one. Gaps
are quantised to the one-second record interval, and more than one swing in a
second is treated as evenly spaced inside the gap that closed - only reachable
above 60 swings a minute, where calling that gap zero would score a burst as
perfect rhythm.

Two gaps are discarded rather than scored. Anything longer than ten seconds is
a pause, not rhythm - a dropped implement, a rest taken mid-set, a run the
detector missed - and counting it would report a break in training as a break
in timing. Fewer than three gaps says more about the detector than the
athlete, and reports no score at all.

The score therefore requires swing detection. Turning the Rhythm Score on
turns the swing counter on with it (`WorkoutSession.startCapture`), because
without detected swings there are no gaps to measure. The gyroscope costs
battery: a measured 59-minute session spent 1.0%.

### What this replaced, and why

Until September 2026 the score compared each one-second window of wrist
acceleration - dynamic RMS, dynamic peak, and zero crossings, weighted
45/35/20 - against an exponentially weighted reference for the session, and
scored the difference. Two things were wrong with it, and both are visible in
the 12-set session recorded in `fit-files/24302940509_ACTIVITY.fit`:

**It ran against effort.** A swing is impulsive. At 20 swings a minute some
one-second windows hold a swing and some hold the gap between two, so the
window-to-window difference grows with how hard the athlete swings. Across
those 12 sets the old score correlated **-0.70** with the swing count: the
hardest sets scored worst.

| set | 3 | 9 | 10 | 12 |
| --- | --- | --- | --- | --- |
| peak acceleration (mg) | 1838 | 1838 | 1644 | 1614 |
| swings | 85 | 77 | 49 | 46 |
| old score | 39 | 40 | 48 | 42 |

**It could not fall with fatigue, by construction.** The reference adapted at
20% per window, so an athlete slowing down was compared against their own
slowing. Softer, slower movement also varies less second to second, so the
score rose. Sets 10-12 of that session were confirmed as genuine fatigue by
the athlete, and scored 48/45/42 against 39-40 when fresh - while swing count,
peak acceleration and load exposure all fell together.

Interval steadiness inverts both. On the same session it correlates **+0.69**
with the swing count, and reads 51/52/51 while fresh, 55/55/56 at the
athlete's best, and 44/50/47 through the three fatigued sets: the gaps both
lengthen (2.2s to 4.1s) and scatter (sd 1.07 to 2.14). Tiredness shows up as
raggedness, which is what a practitioner means by losing their rhythm.

The old model is gone rather than deprecated - `Smoothness.Tracker`,
`windowScore` and `normalizedDifference` were deleted, and removing them gave
the 96KB watches 328 bytes back.

## Per-set summaries

A set opens a scoring span when its work phase begins and closes it when the
set is marked complete, so the gap spanning a rest is never counted as rhythm.
The set score is the steadiness of that span's gaps; the session score is the
steadiness of every gap in the session, which is not the mean of the set
scores and is not meant to be.

A set with fewer than three gaps displays `not enough swings` rather than a
low-confidence number.

## Progress over time

When a workout is saved, the app stores at most twelve summaries on the watch:
the session score and number of scored windows. It shows the current or most
recent score plus the difference from the preceding saved session. No account,
network request, private cloud, or cross-user dataset is involved.

Scores are comparable only when the exercise, hand, tempo, implement, watch
placement, and strap tightness are reasonably consistent. A higher score means
"more evenly spaced swings", not universally better technique - a deliberately
slow set is not less steady than a fast one, only a less even one is.

The model is versioned in both stores, because two different quantities that
both land in 0-100 cannot be told apart by looking. The per-equipment trend
key gained an `_r2` suffix, so a delta never subtracts a windowed score from a
gap-steadiness one; the saved session log marks each record with the model
that wrote it (`SmoothnessLog.DETAIL_MAGIC` 20260912, against 20260816 for the
windowed model, readable through `scoredByWindows()`). Sessions saved before
the change keep their detail and their scores, and simply never contribute to
a trend across the boundary.

## Validation

What has been done, on `fit-files/24302940509_ACTIVITY.fit` - 12 sets of club
work whose per-set counts and fatigue the athlete confirmed:

- the score correlates +0.69 with swing count, where the old model correlated
  -0.70;
- it falls across the three sets confirmed as fatigue, which the old model
  rewarded.

What has not, and would strengthen it:

1. A second labelled recording. One athlete, one session, one implement is a
   direction, not a calibration.
2. A synthetic waveform the swing counter actually bites on. `SyntheticMotion`
   was built for the windowed model and produces fewer than three gaps per
   span, so the production pipeline no longer has an end-to-end rhythm
   assertion - the model is tested directly against controlled gap sequences
   instead.
3. Fixed-tempo work against a metronome, to see how close to 100 a human gets
   and whether the scale needs stretching: this session sat between 44 and 56,
   which is a narrow band to show an athlete.
4. Whether raggedness or lengthening should dominate. They move together under
   fatigue here, and a coefficient of variation deliberately ignores the
   lengthening.
