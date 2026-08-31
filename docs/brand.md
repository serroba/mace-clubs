# Brand

The one place to check before writing the app's name anywhere users see it.
Later sections cover the icon, the device-support claim, and the voice to write
in; this file is the source those all get copied from, so fix it here first.

## The name

The wordmark is **Mace & Clubs**, with an ampersand. Use it in the README, on
the website, in release notes, in the store description body, and in any text
the app draws itself.

There is one exception, and it is forced. The Connect IQ compiler rejects an
application name resource containing an ampersand:

```
ERROR: Invalid application name resource. Please remove the XML entity
reference '&' from the string resource.
```

So `@Strings.AppName` is **Mace and Clubs**, spelled out. That string is what
the watch shows in its app list and what the Connect IQ Store shows as the App
name field, and both must match the published listing. Do not try to "fix" it —
`make build` fails immediately, which is how this was found.

Everything the app draws with its own text is unaffected, because that is
ordinary string data rather than a name resource. `SettingsMenu.aboutLabel()`
renders `Mace & Clubs v0.16.0`, and that is correct.

Summary of which spelling goes where:

| Surface | Spelling | Why |
|---|---|---|
| `resources/strings/strings.xml` `AppName` | Mace and Clubs | Compiler forbids `&` |
| Connect IQ Store — App name field | Mace and Clubs | Must match the shipped resource |
| Connect IQ Store — description body | Mace & Clubs | Free text |
| App-drawn text (e.g. Settings → About) | Mace & Clubs | Free text |
| README, website, release notes | Mace & Clubs | Free text |
| Repository, branches, binaries | `mace-clubs` | Slug, not the wordmark |

`MaceClubsView`, `MaceClubsApp` and friends are code identifiers. They follow
the language's conventions, not the wordmark, and need no changing.

## The mark

The mark is a **mace crossed with an Indian club**: the mace's ball top-right
with its shaft running down to a pommel bottom-left, the club crossing it the
other way, thin handle top-left widening into its bulb bottom-right. It says
what the app is for without a word of text, which is why it survives at 26px.

`tools/brand-mark.ts` holds it as geometry — one circle and two tapered
capsules. That file is the master. It was fitted to the shipped 62×62
`launcher_icon.png` rather than redrawn, and `brand-mark.test.ts` asserts a
re-render still reproduces that bitmap (currently 99.1% of pixels; the rest is
anti-aliasing fringe). Change the geometry and that test fails, which is the
point: the app is live and the mark is recognisable.

Run `make brand-assets` to re-render everything downstream of it.

### Which variant goes where

There are two, and the difference is whether we control the background.

**Silhouette** — white, transparent, no backdrop. Used by
`resources/drawables/launcher_icon.png`, which is both the watch's app-list icon
and what `MaceClubsView` draws on the start screen. Both are black, so a white
silhouette is correct and this file is left exactly as it is.

**Badge** — the mark in chalk `#E8DCC8` with a brass `#C08A3E` ball, on a clay
`#16100B` rounded square. Used everywhere the background belongs to someone
else: the Connect IQ Store's grid, a browser tab, a phone home screen. The
silhouette is invisible in all three, because a white glyph on transparency
disappears the moment the backdrop is light.

| File | Size | For |
|---|---|---|
| `docs/brand/mace-clubs-mark.svg` | vector | The master silhouette, `currentColor` |
| `docs/brand/mace-clubs-icon.svg` | vector | The badge |
| `docs/brand/icon-1024.png` | 1024 | Connect IQ Store icon upload |
| `docs/brand/apple-touch-icon-180.png` | 180 | Phone home screen |
| `docs/favicon.svg`, `docs/favicon-32.png` | vector, 32 | Website |

### Colours

The website's own `:root` custom properties are the source. The three the icon
uses are re-exported by `render-brand-assets.ts` as `PALETTE`, and
`brand-mark.test.ts` reads them back out of `docs/index.html` and fails if the
two disagree — so changing the site's palette without re-running `make
brand-assets` is now a test failure rather than a green favicon above a brown
page, which is exactly what happened the first time.

| Token | Hex | Role |
|---|---|---|
| pit | `#16100B` | Page ground, badge ground |
| chalk | `#E8DCC8` | Body text, the mark on the badge |
| brass | `#C08A3E` | The mace's ball, links, rules, accents |
| lamp | `#E8B45F` | Brass highlight, hover, the accented beat |
| ash | `#9A8B78` | Secondary text |
| pit-raised | `#1F1710` | Panels sitting above the ground |

Only `pit`, `chalk` and `brass` reach the icon; the rest are the site's alone.

### The one asset that is not generated

`docs/brand/og-image.jpg` is a crop of a hand-made piece (`hero-v0.4.0.png`) —
the mark in white on black with a lit arc behind it. Its arc is ember-orange
rather than brass, so it does not match the palette above, and it is a JPEG the
generator cannot produce. It is kept anyway: it is the best single image the
project has, its near-black ground still reads correctly, and a social card is
seen on its own rather than beside the site. Replace it with something better
rather than with something merely consistent.

### Known gap

`launcher_icon.png` is a single 62×62 bitmap, but the 120 devices in the
manifest want fifteen different sizes, from 26×26 to 70×70, and one of them is
not square (40×33). It is therefore rescaled by the runtime on 93 of them — 51
devices alone are 40×40, a downscale that aliases a thin white diagonal badly.
Rendering per-size icons and wiring them through the jungle's resource
qualifiers is now a mechanical job, since the geometry is vector. It has not
been done.

## The Rhythm Score

The app's one genuinely proprietary metric was called "smoothness score" — a
generic noun, and one nobody repeats. Named metrics are how a measurement
becomes something a coach says out loud: Body Battery, Strain, Training Load.
It is now the **Rhythm Score**, which is also the tagline the website already
leads with, so the two reinforce each other instead of being unrelated.

Capitalised, both words, in prose: the Rhythm Score. On the watch, where there
is no room for either, the label is lowercase `rhythm 82`.

"Flow Score" was the obvious alternative — it is the community's own word,
Dutch Flow Academy and "mace flow" and so on. It was rejected because `Flow /
other` is already a movement name in the app, and a work screen reading
`FLOW / flow 82` helps nobody.

**Only the user-facing name changed.** The code still says smoothness —
`Smoothness.mc`, `SmoothnessLog.mc`, the `smoothnessEnabled` property, the
`FitSmoothness` string id — because that is genuinely what the quantity is, and
churning identifiers buys nothing a reader of the code wants.
[smoothness-physics.md](smoothness-physics.md) describes the quantity and keeps
its own vocabulary.

The rename was free on screen: `smooth` and `rhythm` are both six characters,
and so are `SMOOTH` and `RHYTHM`, which matters because
`WorkoutSummaryView.smoothnessLines()` keeps that heading as short as `PAUSED`
so the Instinct's subwindow cut-out never lands on it.

## The device-support claim

Three surfaces used to say three different things. The website said the app
"runs on 120+ Connect IQ watches", the README said "the supported watch is the
Instinct 3 Solar 45 mm", and v0.15.0's notes said support was *intentionally*
limited to that one watch — while the manifest shipped 120 products. A Fenix
owner reading any two of those comes away misled, and the version that costs
you a one-star review is the one they believe.

Both halves are true; they are about different things. Use this, and keep the
short form intact as one sentence:

> **Runs on 120 Connect IQ watches. Swing counting is validated on the
> Instinct 3 Solar 45 mm.**

Where there is room, the long form follows it:

> Everything else — the metronome, intervals, movement and side tracking, and
> activity recording — behaves the same on all of them. Swing counting is the
> exception: its detector is tuned against labelled recordings from that one
> watch and its 25 Hz gyroscope. On other watches it still runs, falling back
> to the accelerometer where there is no gyroscope, but the counts have not
> been checked against known-correct numbers.

The fallback is real and worth stating, because "not validated" reads as "does
not work" otherwise. `WorkoutSession.startMotionCapture` asks for the
gyroscope, and a device that rejects the combined sensor request drops to the
accelerometer detector rather than counting zero.

What makes the second sentence shorter is labelled recordings from other
watches, which is why every statement of it links to
[CONTRIBUTING.md](../CONTRIBUTING.md#calibration-recordings).

The count is not a slogan — it is `grep -c '<iq:product' manifest.xml`, and
`make manifest-check` reports CIQ 3.1+ wearables the manifest is missing. If
the manifest grows, this number moves with it.

## What the app does not name

The recorded activity is **not** called "Mace & Clubs". `WorkoutSession.mc`
passes `Equipment.labelFor(...)` as the session `:name`, so an activity lands in
Garmin Connect under its implement and weight — `Mace 4kg`, `Clubs 2x1kg` — and
the app name appears only as the recording app. Describe it that way; claiming
otherwise sends people looking for an activity title that never appears.
