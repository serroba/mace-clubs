# Releasing

```sh
make release-assets VERSION=0.15.2      # generate notes, listing, screenshots
git add docs/ source/app/AppVersion.mc
git commit -m "Prepare version 0.15.2"
git tag v0.15.2 && git push origin main v0.15.2
```

The tag push is what triggers `release.yml`. The `pre-push` hook checks the
release is actually ready before letting it through.

## What gets generated

| Command | Output |
|---|---|
| `make release-docs VERSION=x.y.z` | `docs/product-updates/vx.y.z.md`, and the generated regions of `docs/store-listing.md` |
| `make release-shots VERSION=x.y.z` | `docs/store-assets/vx.y.z/<device>/*.png` and `manifest.json` |
| `make release-assets VERSION=x.y.z` | both |
| `make release-check VERSION=x.y.z` | what the hook runs, so you can check before tagging |

**Product-update notes** come from the commits between the previous tag and
the release, split into *On the watch* and *Tooling and tests* by which paths
each change touched. Version bumps are dropped, and a non-squash merge's title
is taken from its body rather than its "Merge pull request #N from …" subject.
These are fully generated — regenerate rather than editing.

**The store listing** is *not* fully generated. Its prose is hand-written
marketing copy worth keeping, so only the parts that go stale are machine
owned, between `<!-- generated:… -->` markers: the upload line and the What's
new section. Edit anything outside those freely.

**Screenshots** drive the real simulator, so this step needs an awake,
unlocked screen on macOS — the same requirement as the e2e suite, and the same
symptom if you forget (a timeout waiting for the simulator window). Captures
are downscaled to each watch's native resolution: macOS grabs a Retina display
at 2x, which is neither what the store wants nor worth 4x the bytes in git.

Four of the seven screenshots in the store listing are captured automatically.
The other three need state a fresh simulator does not have — a bulava Combo
selection, a Challenge preset, saved history — and `manifest.json` lists them
under `manual_still_required` so they are not quietly forgotten.

## The gate

`pre-push` refuses a `v*` tag when the notes are missing, the listing does not
mention the version, the screenshots are absent, or any of it is uncommitted.
It runs before the e2e suite deliberately: it fails in about a second, where
the suite takes minutes.

This exists because remembering was the part that failed. Before it, 19 of the
first 26 tags shipped with no product-update doc at all, `store-listing.md`
still advertised the version before the one that had shipped, and
`store-assets/` held screenshots from eleven releases earlier.

Deleting a tag skips the gate — it does not re-release anything.

## Why there is no tag hook

Git has no `pre-tag` hook; the hook set is fixed and nothing fires on
`git tag`. `pre-push` is the closest real point, and by then the tagged commit
already exists — which is why the generated docs have to be committed *before*
tagging rather than produced during it. `reference-transaction` does fire on
tag creation, but it fires on every ref update including fetches, and anything
it wrote would still land after the commit being tagged.
