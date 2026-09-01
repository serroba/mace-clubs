# Running the e2e suite on Linux

The e2e UI suite runs headlessly on Linux as well as macOS - same test
files, same `Simulator` API, different backend underneath
(`tools/e2e/platform-linux.ts`: Xvfb, `xdotool`, ImageMagick, Tesseract in
place of AppleScript, `screencapture`, Vision). This directory holds the
image and entrypoint that make that possible. See `docs/e2e-testing.md`
for the driver architecture and the platform findings behind it.

CI runs exactly this: `.github/workflows/e2e-linux.yml`, on pushes to
`main` and on demand.

## Running it locally

```sh
docker build -t mace-clubs-e2e-linux:local -f tools/e2e/linux/Dockerfile .

docker run --rm --entrypoint bash \
  -v "$(pwd):/workspace" -w /workspace \
  mace-clubs-e2e-linux:local /workspace/tools/e2e/linux/run-suite.sh
```

No SDK install and no Garmin account are needed: the base image carries the
device files and, since v2.10.0, the device fonts.

Two gotchas worth knowing:

- The base image's own `ENTRYPOINT` is `tester.sh`, so `--entrypoint bash`
  is required - without it your script path is swallowed as `tester.sh`'s
  device-id argument instead of being executed.
- On a Colima/macOS host, bind-mounting a script from `/tmp` can surface
  as an empty *directory* inside the container. Keep scripts inside the
  repo mount.

## Fonts

Device fonts are needed for any on-screen text, and therefore for OCR. They
now ship in the base image (1378 files at `/root/.Garmin/ConnectIQ/Fonts`,
since v2.10.0), so nothing here mounts or fetches them.

Because they do, **fork PRs run the full UI suite** - they were skipped
before, when the fonts needed a credential the fork could not have.

Worth knowing that bundling Garmin content is the image publisher's call, not
this repo's: the SDK's licence forbids redistributing it, so this image
deliberately carried no fonts of its own until upstream added them. Nothing
here redistributes anything, but the judgement now sits with the base image.

An earlier alternative - bundling an open-source bitmap font as a
substitute - is dead-ended by an upstream bug: loading any custom
`FontResource` crashes the Linux simulator natively on the next `Menu2`
push (root-caused with a core dump on branch
`explore/e2e-testfont-probe`). With real device fonts no custom
`FontResource` is ever loaded, so that bug never comes into play.

## Driving a different watch

`MACE_E2E_DEVICE` selects the device, defaulting to `instinct3solar45mm`:

```sh
MACE_E2E_DEVICE=venu3 bash tools/e2e/linux/run-suite.sh
```

The device's own SDK files have to be present under
`$HOME/.Garmin/ConnectIQ/Devices/<id>/` - `run-suite.sh` compiles for that
device and the driver reads its screenshot crop, MENU hotspot and skin size
out of its `simulator.json`. The base image carries 173 of them, so any
device the SDK has a skin for works without extra setup.
