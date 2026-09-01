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

It used to be otherwise, and the history is worth keeping. This image
carried no fonts because Garmin's SDK EULA forbids redistributing the SDK in
whole or in part; locally you mounted a licensed copy, and CI fetched them
per job through Garmin's authenticated API via
[connect-iq-sdk-manager-cli](https://github.com/lindell/connect-iq-sdk-manager-cli)
using `GARMIN_USERNAME`/`GARMIN_PASSWORD` secrets. Upstream bundled them
after this project reported that the simulator renders nothing without them
(matco/connectiq-tester, fixed in 3aaae84 / v2.10.0).

Two consequences worth naming. CI no longer holds Garmin credentials at all,
and **fork PRs now run the full UI suite** - they were skipped before purely
because GitHub withholds secrets from them. And the licensing judgement moved
upstream: bundling Garmin content is the image publisher's call, and this repo
consumes the result rather than making it. If that ever needs reversing, the
mount-and-fetch approach is in this file's history.

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

The device's own SDK files must be present under
`$HOME/.Garmin/ConnectIQ/Devices/<id>/` - `run-suite.sh` compiles for that
device and the driver reads its screenshot crop, MENU hotspot and skin size
out of its `simulator.json`. In CI both the fonts and the device files come
from the same `connect-iq-sdk-manager device download --include-fonts` call
and are cached per device.
