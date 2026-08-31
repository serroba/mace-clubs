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

**Badge** — the mark in paper `#F0EADC` with an ember `#DB542F` ball, on a
forest `#1F382D` rounded square. Used everywhere the background belongs to
someone else: the Connect IQ Store's grid, a browser tab, a phone home screen.
The silhouette is invisible in all three, because a white glyph on transparency
disappears the moment the backdrop is light.

| File | Size | For |
|---|---|---|
| `docs/brand/mace-clubs-mark.svg` | vector | The master silhouette, `currentColor` |
| `docs/brand/mace-clubs-icon.svg` | vector | The badge |
| `docs/brand/icon-1024.png` | 1024 | Connect IQ Store icon upload |
| `docs/brand/apple-touch-icon-180.png` | 180 | Phone home screen |
| `docs/favicon.svg`, `docs/favicon-32.png` | vector, 32 | Website |

### Colours

Taken from the website's custom properties, so the icon and the page it sits on
cannot drift apart. `render-brand-assets.ts` re-exports them as `PALETTE`.

| Token | Hex | Role |
|---|---|---|
| forest | `#1F382D` | Badge ground, dark sections |
| paper | `#F0EADC` | The mark on the badge, page background |
| ember | `#DB542F` | The mace's ball, links, accents |

### Known gap

`launcher_icon.png` is a single 62×62 bitmap, but the 120 devices in the
manifest want fifteen different sizes, from 26×26 to 70×70, and one of them is
not square (40×33). It is therefore rescaled by the runtime on 93 of them — 51
devices alone are 40×40, a downscale that aliases a thin white diagonal badly.
Rendering per-size icons and wiring them through the jungle's resource
qualifiers is now a mechanical job, since the geometry is vector. It has not
been done.

## What the app does not name

The recorded activity is **not** called "Mace & Clubs". `WorkoutSession.mc`
passes `Equipment.labelFor(...)` as the session `:name`, so an activity lands in
Garmin Connect under its implement and weight — `Mace 4kg`, `Clubs 2x1kg` — and
the app name appears only as the recording app. Describe it that way; claiming
otherwise sends people looking for an activity title that never appears.
