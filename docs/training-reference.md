# Training reference

Everything the README's Controls table is too small to say: what each workout
shape does, how movements and sides are chosen, and what ends up in the
activity. For the model behind the Rhythm Score see
[smoothness-physics.md](smoothness-physics.md); for swing counting see
[swing-counting.md](swing-counting.md).

## Workout shapes

**Interval presets** (e.g. 5 × 2:00 work / 1:00 rest) call work and rest with
tone and vibration cues, run the metronome only during work, and count sets
automatically.

**Challenge presets** are one continuous work interval with no rest, after the
traditional timed max-swing gada competitions. Swing counting is forced on,
total swings are written to the session (`total_swings`) and to each work lap
(`swing_count`), and swings during rest or pause never count.

**The Custom preset** defaults to 5 × 2:00 work / 2:00 rest. Configure it on the
watch from MENU → Settings → Custom workout, or from the Garmin Connect phone
app. The on-watch editor walks through sets, work duration, and rest duration;
duration controls move in 30-second steps.

**Free training** has no prescribed interval. SELECT completes the current set
and enters REST; SELECT again begins the next WORK phase. Rest keeps activity
and heart-rate recording running. BACK remains a true whole-session
pause/resume control, separate from the work/rest boundary.

**Rep mode** is enabled from MENU → Settings → Mode, or from Garmin Connect. It
uses the same manual work/rest flow but keeps the metronome silent and makes the
current set's detected swings the primary metric. Its optional target (0 means
off) gives one cue when reached; on-watch target choices cycle through common
values, while Garmin Connect accepts any value from 0–999. UP/DOWN adds or
removes one rep while working, before SELECT commits that corrected count to the
set summary and the FIT lap.

## Implements, movements, and sides

Starting a workout asks for the implement, then the movement. The movement list
follows the implement:

| Implement | Movements |
|---|---|
| Mace | 360, 10-to-2, flow / other |
| Clubs | Mill, shield cast, flow / other |
| Bulava | Combo, mill, reverse mill, bullwhip, flow / other |

The choice is saved with every work block.

The bulava **Combo** is the traditional combination set — mill, reverse mill,
bullwhip on one hand, then the other. The metronome calls the sequence: an
accent on each movement change, a double pulse on the hand switch, and the
screen shows the current hand and movement (e.g. `L REV MILL`). Beats per
movement are configurable from the phone (default 4-4-2), and combo sets always
record an alternating working side.

During a free-training rest, MENU offers switching the movement or the working
side for the next set, so a left/right ladder needs one press per rest rather
than a trip through Settings. Working side is also configurable in Settings,
separately from which wrist the watch is on.

Single-side work sets are tallied per hand, and the paused and completed
summaries show an `L3/R2` balance tag — the traditional convention being that
each hand gets the same number of sets.

## What reaches Garmin Connect

The activity records under the implement and weight you chose (`Mace 4kg`,
`Clubs 2x1kg`), as sport Training / sub-sport Strength.

Garmin may label recorded set and rest boundaries as laps or as splits. Work
laps carry their one-based `set_number`; rest laps carry zero. Each boundary
also records its work/rest phase, duration, implement weight, watch wrist, and
the set's Rhythm Score where available.

Connect IQ does not expose Garmin's native strength-set message type, so the
Strength summary can still show `-- Sets` even though the set count is written
to the session. That is a platform limit, not a recording failure.

The paused and completed screens carry an on-watch set summary; UP/DOWN inspects
individual work and rest durations.
