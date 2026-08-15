# Exercise-aware load exposure

## Purpose and interpretation

Load exposure is an optional on-watch summary of wrist motion during each work
set. It is designed for like-for-like training review: the same implement,
quantity, weight, movement, and working side. It does not measure tendon force,
tendon strain, joint torque, technique quality, or injury risk.

A wrist accelerometer cannot observe the implement's centre of mass, joint
angles, muscle co-contraction, tendon geometry, or the force shared among
tissues. The app therefore preserves transparent measurements instead of
combining them into a physiological score.

## Per-set measurements

When **Load exposure** is enabled, the existing 25 Hz accelerometer stream is
summarised once per second. A window is active when dynamic RMS is at least 40
mg, matching the motion floor used by the local smoothness feature.

Each completed work block stores:

- `motion_exposure`: the sum of active-window dynamic RMS values, in mg-s;
- `motion_peak`: the largest active-window dynamic peak, in mg;
- `active_seconds`: the number of active one-second windows; and
- `weight_volume`: total implement kilograms multiplied by detected swings.

Weight-volume is zero when swing counting is unavailable. For two clubs, the
configured per-club weight is multiplied by two. Rest, pause, and the pre-start
countdown do not contribute motion exposure.

The paused and completed set browser shows a compact `L` token, such as
`L12.4k`. This is the measured motion exposure, not a universal load score.
The full values are written as FIT lap developer fields.

## Exercise context

Every work block already carries the movement and working side. A bulava Combo
remains one distinct movement even though its metronome sequences mill, reverse
mill, and bullwhip. `Flow / other` is recorded, but sessions using that catch-all
should not be assumed comparable without knowing the actual movements performed.

Future low/typical/high classifications must use matching implement, quantity,
weight, movement, working side, and watch wrist. They should be added only after
collecting labelled sessions and testing repeatability for each movement.
