# Equipment profiles

Mace & Clubs stores an equipment description with each activity so training
volume and smoothness trends have meaningful context.

The Garmin Connect app settings define:

- implement: mace or clubs
- club count: one or two (a mace always counts as one)
- weight of each implement in grams

The weight is per implement: `Clubs: 2 x 2.5 kg` means two 2.5 kg clubs, not
2.5 kg combined. The app displays this profile before a workout, uses it as the
activity name, and writes type, count, and weight as session-level FIT developer
fields.

Smoothness histories are keyed by the exact profile. A score recorded with a
mace is never compared with clubs, and changing quantity or weight starts a
separate comparison history. Data remains in the user's local app storage and
FIT activity; the project does not operate a collection service or private
cloud.
