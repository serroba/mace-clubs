## Summary
- What changed and why — the motivation, not just a restatement of the diff.

## Release note
If this changes anything a user can see, add a `Release-note:` trailer to the
squash-merge commit — one sentence, in their words, no repo vocabulary:

```
Release-note: Fixed the paused screen on Instinct watches.
```

That line is what the Connect IQ Store's "What's new" shows. Without it the
store quotes the commit subject, which is written for us, not for them.
Skip this for tooling, tests, CI, and docs.

## Screenshots
Required for anything that changes what's on screen (new UI, layout tweaks, a new device screen). A simulator capture is fine — see `tools/visual_check.sh` and the workflow used in #102/#103 for driving the simulator under Xvfb and grabbing a screenshot. Embed images with an absolute URL, e.g. `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/path/to/image.png` — relative paths don't render in a PR description.

Mark this section "N/A" for changes with no visual surface (release prep, CI/tooling, refactors, docs).

## Test plan
- [ ] `make check` passes (format, lint, build, unit tests, FIT schema validation)
- [ ] `make simulator-test` passes
- [ ] Live visual check in a real simulator, if this touches a rendered screen
