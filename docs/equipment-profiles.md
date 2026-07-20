# Equipment profiles

Mace & Clubs stores an equipment description with each activity so training
volume and smoothness trends have meaningful context.

The on-watch settings and Garmin Connect app settings define:

- implement: mace or clubs
- club count: one or two (a mace always counts as one)
- separate default mace and per-club weights (4 kg initially)

The watch displays and edits weight using its configured metric or statute
weight units, while storing canonical grams. Weight is per implement:
`Clubs: 2 x 2.5 kg` means two 2.5 kg clubs, not 2.5 kg combined.

After choosing an interval preset, the athlete chooses mace, one club, or two
clubs. Only then does the five-second start countdown begin. The app uses this
profile as the activity name and writes type, count, and weight as session-level
FIT developer fields.

Smoothness histories are keyed by the exact profile. A score recorded with a
mace is never compared with clubs, and changing quantity or weight starts a
separate comparison history. Data remains in the user's local app storage and
FIT activity; the project does not operate a collection service or private
cloud.
