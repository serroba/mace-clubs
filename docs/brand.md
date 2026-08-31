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

## What the app does not name

The recorded activity is **not** called "Mace & Clubs". `WorkoutSession.mc`
passes `Equipment.labelFor(...)` as the session `:name`, so an activity lands in
Garmin Connect under its implement and weight — `Mace 4kg`, `Clubs 2x1kg` — and
the app name appears only as the recording app. Describe it that way; claiming
otherwise sends people looking for an activity title that never appears.
