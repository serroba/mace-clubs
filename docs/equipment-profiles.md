# Equipment profiles

Mace & Clubs stores an equipment description with each activity so training
volume and smoothness trends have meaningful context.

## What the profile holds

The on-watch settings and the Garmin Connect app settings define:

- **implement**: mace, clubs, bulava, or mudgar
- **club count**: one or two. Every other implement is recorded one at a time.
  A mudgar is swung as a pair in the Indian tradition as often as singly, and
  the app does not model that yet — quantity is part of the smoothness history
  key, so adding it later starts new histories rather than rewriting old ones.
- **a default weight per implement**, each under its own property, so changing
  your mace does not change what the app thinks your clubs weigh:

  | Implement | Property | Initial weight |
  |---|---|---|
  | Mace | `maceWeightGrams` | 4 kg |
  | Club (each) | `clubWeightGrams` | 4 kg |
  | Bulava | `bulavaWeightGrams` | 6 kg |
  | Mudgar | `mudgarWeightGrams` | 5 kg |

  Those are starting points for someone who has not set their own, not
  recommendations. They live in `resources/settings/properties.xml`, which is
  what a watch actually reads; `Equipment.startingGramsFor` carries the same
  figures as a fallback for a build whose properties have not been written.

The watch displays and edits weight using its configured metric or statute
weight units, while storing canonical grams. Weight is per implement:
`Clubs: 2 x 2.5 kg` means two 2.5 kg clubs, not 2.5 kg combined.

## Choosing one

After choosing an interval preset, the athlete picks an implement — mace, one
club, two clubs, bulava, or mudgar — and then a movement. Only then does the
five-second start countdown begin. The movement list follows the implement:
360 and 10-to-2 for the mace, mill and shield cast for clubs, the combination
set and its parts for the bulava, and 360 and mill for the mudgar. Flow/other
is available for all of them.

The app uses the resulting profile as the activity name.

## What reaches the FIT file

Type, count, and weight are written as session-level FIT developer fields.
`implement_type` carries the `Equipment.TYPE_*` value:

| Value | Implement |
|---|---|
| 0 | Mace |
| 1 | Clubs |
| 2 | Bulava |
| 3 | Mudgar |

Values are appended rather than reordered, so the `implement_type` already
written into an existing activity keeps its meaning.

**This table is the legend, and it has to be.** A developer field's `units`
string is short, and the SDK does not document how short. `"0=mace 1=clubs"`
(14 characters) has always worked; extending it to
`"0=mace 1=clubs 2=bulava 3=mudgar"` (32) made `createField` throw a System
Error — which happens on the first started workout, not at build time, so
nothing catches it except the simulator test suite. That is also why the
legend still read `"0=mace 1=clubs"` for as long as it did after the bulava
was added. The field now carries `"implement code"` and points here.

## Comparing like with like

Smoothness histories are keyed by the exact profile. A score recorded with a
mace is never compared with clubs, and changing implement, quantity, or weight
starts a separate comparison history. Data remains in the user's local app
storage and FIT activity; the project does not operate a collection service or
private cloud.
