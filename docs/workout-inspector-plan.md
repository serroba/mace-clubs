# Workout Inspector plan

## Purpose

Garmin Connect preserves the activity but does not present every Mace & Clubs
developer field or explain when a recording is incomplete. Workout Inspector is
a local-first companion that turns an exported FIT file into an auditable view
of workout quality and training trends. It must never describe wrist motion as
measured tendon force or diagnose injury risk.

## Principles

- Process FIT/ZIP exports locally by default; uploading personal data is optional.
- Separate measured values, derived values, and interpretation in every output.
- Explain every warning and every score deduction.
- Reuse the same parsing and analysis code for real workouts and CI fixtures.
- Treat CI as the software contract and real exports as user-controlled evidence.

## Roadmap

### 1. FIT integrity and data-quality validator — complete

- Validate session, lap, set, phase, sensor-series, and custom-field consistency.
- Detect missing samples, invalid ranges, overlapping laps, and implausible motion.
- Produce human-readable and JSON output with a transparent quality score.
- Return a failing exit status for structural errors.
- Run the deterministic synthetic workout through the validator in CI.

Exit criterion: a user can inspect an exported FIT/ZIP file and distinguish a
healthy recording, a usable recording with gaps, and a structurally invalid one.

### 2. Inspector report — complete

- Add the findings and score to the existing self-contained HTML report.
- Link every warning to the affected interval or set.
- Add measured/derived labels and data-availability explanations.
- Add visual regression fixtures for healthy and degraded recordings.

Exit criterion: the self-contained report explains recording quality, distinguishes
measured and derived values, and links each actionable finding to its timeline,
lap, or set. CI covers both a healthy synthetic export and a degraded report.

### 3. Within-session safety signals — complete

- Show smoothness drift, late-session peak changes, left/right balance, and sensor
  dropout without converting them into medical or injury predictions.
- Establish minimum sample sizes and confidence labels for every signal.
- Validate calculations with synthetic fatigue, spike, and dropout scenarios.

Exit criterion: every signal states its sample size and confidence, declines to
interpret insufficient data, and is covered by deterministic decline, spike,
balance, and dropout scenarios. Outputs remain descriptive and explicitly avoid
tendon-force, injury-risk, or readiness claims.

### 4. History and workload trends — complete

- Import multiple exports into a private local history.
- Compare motion exposure, active time, volume, peaks, and smoothness with recent
  personal baselines.
- Highlight abrupt load changes and repeated high-load sessions as review prompts.
- Document retention, deletion, export, and backup behavior.

Current CLI usage:

```sh
node --experimental-strip-types tools/workout-history.ts --database ~/mace-history.json import activity.fit export.zip
node --experimental-strip-types tools/workout-history.ts --database ~/mace-history.json show
node --experimental-strip-types tools/workout-history.ts --database ~/mace-history.json delete WORKOUT_ID
node --experimental-strip-types tools/workout-history.ts --database ~/mace-history.json export backup.json
node --experimental-strip-types tools/workout-history.ts --database ~/mace-history.json clear
```

The database is never uploaded, stores workout summaries rather than per-second
sensor records, has no automatic retention deadline, and remains wherever the
user selects with `--database`. `delete` removes one imported summary; `clear`
removes all summaries; `export` creates a plain JSON backup under user control.

Exit criterion: the CLI deduplicates and chronologically orders imports, compares
the latest compatible workout against 3–8 prior personal sessions, flags changes
of 50% or more for review, and never substitutes unrelated or missing workouts
into a baseline.

### 5. Installable web experience

- Move parsing and analysis into a browser-capable core where practical.
- Provide drag-and-drop import, offline storage, and an installable PWA.
- Keep a static, self-hostable build; evaluate Garmin integrations separately.
- Add end-to-end tests using the same deterministic FIT fixtures.

## Non-goals

- Estimating tendon force from wrist acceleration alone.
- Diagnosing fatigue, injury, or readiness.
- Replacing Garmin's activity store or requiring a cloud account.
- Hiding missing data behind a single unexplained score.
