# Linux e2e feasibility image (local only - do not push)

**Confirmed working** (2026-08-30, `probe.sh`): the Garmin BDD e2e suite
(currently macOS-only, see `docs/e2e-testing.md`) CAN run headlessly on
Linux - Xvfb for the display, `xdotool` for key injection, ImageMagick for
screenshots, and Tesseract for OCR, in place of
AppleScript/`screencapture`/Vision. Verified end to end: compiled the real
app, booted the real simulator, launched it, and OCR'd real on-screen text
off a live screenshot (`"SELECT to start"`, then navigated
idle -> equipment picker -> movement picker, each confirmed via OCR).

Two mechanics differ from macOS and matter for a real driver port:

- **`xdotool key --window <id> ...` is ignored by this app** - matches
  `tools/visual_check.sh`'s existing note that synthetic `--window` events
  don't register. Use `xdotool windowactivate --sync <id>` followed by a
  plain (non-`--window`) `xdotool key` instead - global input focus, not
  event targeting.
- **The first press or two after a screen transition can still be
  swallowed**, same as macOS - `pressUntilChanged()`'s retry-and-compare
  pattern already handles this; a Linux backend needs the same retry loop,
  not a single press.

This is a feasibility spike (`probe.sh`), not the real backend - a proper
Linux `Simulator` implementation living behind the same `press`/
`screenshot`/`readText`/`close` interface as `tools/e2e/simulator.ts` is
still a separate follow-up.

**This image is for local feasibility testing only. Never push it to a
registry.** It's built FROM `ghcr.io/matco/connectiq-tester` (already used
elsewhere in this repo's CI) plus open-source packages - fine to share.
Device **fonts** are the one piece it can't legitimately bundle: Garmin's
Connect IQ SDK EULA prohibits redistributing the SDK "in whole or in part",
and fonts aren't in the base image at all (confirmed - `find` turns up
nothing). The official SDK Manager fetches them from an authenticated
Garmin API (`.../ciq-product-onboarding/fonts/font?fontName=...` on
`api.gcs.garmin.com`, returns 401 without a session) - not something to
automate into CI without Garmin's own tooling doing the auth.

So: mount your own locally-licensed copy in read-only at `docker run` time
instead of baking it into the image. Nothing proprietary ever enters a
Docker layer, gets committed to git, or gets pushed anywhere.

A real CI job still needs its own answer for fonts, since GitHub-hosted
runners have no locally-licensed SDK to mount from - two non-authenticated
options worth exploring next: (a) design a small open-license bitmap font
good enough for OCR (doesn't need to look like Garmin's shipped fonts,
just needs the driver to prove screen state), or (b) accept no on-screen
text in CI and assert via pixel-region/color checks instead. Neither is
built yet - see `docs/e2e-testing.md`.

## Reproducing

```sh
docker build -t mace-clubs-e2e-linux:local -f tools/e2e/linux/Dockerfile .

docker run --rm --entrypoint bash \
  -v "$HOME/Library/Application Support/Garmin/ConnectIQ/Fonts:/root/.Garmin/ConnectIQ/Fonts:ro" \
  -v "$(pwd):/workspace" -w /workspace \
  mace-clubs-e2e-linux:local /workspace/tools/e2e/linux/probe.sh
```

(Linux host: fonts are usually at `~/.Garmin/ConnectIQ/Fonts` already, no
mount needed if the SDK Manager was installed on the same machine. Note
the base image's own `ENTRYPOINT` is `tester.sh` - `--entrypoint bash` is
required or your script's path gets swallowed as `tester.sh`'s device-id
argument instead of being executed.)

## Debugging a crash

`probe-debug.sh` is what root-caused the `Menu2`+custom-font segfault
documented in `tools/e2e/testfont/README.md` - it captures a real core
dump and pulls a `gdb` backtrace instead of guessing from log output.

```sh
docker build -t mace-clubs-e2e-linux-debug:local -f tools/e2e/linux/Dockerfile.debug .

docker run --rm --privileged --entrypoint bash \
  -v "$(pwd):/workspace" -w /workspace \
  mace-clubs-e2e-linux-debug:local /workspace/tools/e2e/linux/probe-debug.sh
```

Cores land in `.debug-cores/` on the bind mount (not `/tmp`) so they
survive the container being torn down by `--rm`. Two core files show up
per crash - **use the `qemu_<prog>_<timestamp>_<pid>.core` one, not the
plain `core`**: under local QEMU (this repo's dev machines are arm64,
the image is amd64-only), the kernel's own core dump captures QEMU's ARM64
*host* process, not the emulated x86_64 guest, and `gdb` can't make sense
of it (`malformed note`, garbled registers). QEMU's own core dump is the
real x86_64 guest state and loads cleanly against the actual `simulator`
binary. `--privileged` is required for core dumps to write successfully
inside the container.
