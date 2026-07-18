# Local smoothness score: physics and interpretation

## Purpose and privacy boundary

The smoothness score is an on-watch estimate of how repeatable the athlete's
wrist motion is during one workout. Raw accelerometer samples never leave the
watch through this feature. The app keeps only compact session summaries in
Connect IQ application storage; saving the activity can still include the
existing opt-in one-second motion fields in the user's FIT file.

The score is not a measurement of mace-head force, joint loading, technique,
or injury risk. A watch measures the acceleration of the wrist and is affected
by strap fit, watch orientation, grip, exercise choice, hand changes, and
deliberate changes in range of motion.

## Sensor model

For each 25 Hz, one-second window, the accelerometer reports a vector

```text
a_measured(t) = a_linear(t) + g(t) + noise(t)
```

where `g(t)` is gravity expressed in the rotating watch frame. Simply using
the magnitude `|a_measured|` leaves a roughly 1 g offset and makes orientation
changes look like effort changes. The app therefore estimates the slowly
varying component with the per-axis window mean and subtracts it:

```text
a_dynamic(t) = a_measured(t) - mean_window(a_measured)
```

This is a deliberately cheap high-pass approximation suitable for older
Connect IQ devices. It suppresses constant gravity but cannot perfectly
separate gravity from linear acceleration during a fast rotation.

Each valid window produces three orientation-resistant summaries:

- dynamic RMS: `sqrt(mean(|a_dynamic|^2))`, a proxy for typical wrist effort;
- dynamic peak: `max(|a_dynamic|)`, a proxy for the strongest transient; and
- crossing count: sign changes of demeaned `|a_measured|`, a coarse timing and
  periodicity proxy.

No athlete mass, mace mass, lever arm, or angular velocity is available, so
the app intentionally does not label any value as force or torque. Computing
`F = m a` would be misleading because the measured acceleration is at the
wrist, not at the mace centre of mass, and the required masses and geometry
are unknown.

## Repeatability score

After a short warm-up of four valid one-second windows, the app compares each
new window with an exponentially weighted reference for the same session.
For metric `x`, the normalized difference is:

```text
d(x, reference) = |x - reference| / max(|reference|, floor)
```

Floors prevent noise near zero from dominating. Dynamic RMS, dynamic peak,
and crossing count use weights 45%, 35%, and 20%. The weighted difference is
mapped to a bounded score:

```text
window_score = clamp(100 - 100 * weighted_difference, 0, 100)
```

The displayed session score is the arithmetic mean of scored windows. The
reference adapts slowly (20% new observation, 80% previous reference), so it
can follow fatigue or a planned tempo change without treating a single odd
swing as the new normal. Pauses and the five-second start delay do not add
samples because sensor capture begins with the recorded workout.

This first version measures consistency between one-second windows. It does
not yet align individual swing waveforms to beats, distinguish left and right
hands, or compare acceleration at the exact start and end of each swing.
Those require validated cycle segmentation and should be added only after
examining the watch-local results against labelled practice sessions.

## Progress over time

When a workout is saved, the app stores at most twelve summaries on the watch:
the session score and number of scored windows. It shows the current or most
recent score plus the difference from the preceding saved session. No account,
network request, private cloud, or cross-user dataset is involved.

Scores are comparable only when the exercise, hand, tempo, implement, watch
placement, and strap tightness are reasonably consistent. A higher score means
"more similar to this session's recent wrist-motion pattern," not universally
better technique. The algorithm and storage format should remain versioned so
future physics changes do not silently masquerade as athlete progress.

## Validation plan

1. Repeat one movement at fixed tempo and check that the score stabilizes.
2. Introduce controlled timing and amplitude changes and verify that the score
   decreases without saturating at zero.
3. Repeat with different strap tightness, hands, and mace weights to quantify
   sensitivity to conditions.
4. Compare one-second summaries with manually labelled video or beat timing
   before implementing per-swing phase, start/end symmetry, or force language.
