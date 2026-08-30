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
  -v "$HOME/Library/Application Support/Garmin/ConnectIQ/Fonts:/root/.Garmin/ConnectIQ/Fonts:ro" \
  -v "$(pwd):/workspace" -w /workspace \
  mace-clubs-e2e-linux:local /workspace/tools/e2e/linux/run-suite.sh
```

Two gotchas worth knowing:

- The base image's own `ENTRYPOINT` is `tester.sh`, so `--entrypoint bash`
  is required - without it your script path is swallowed as `tester.sh`'s
  device-id argument instead of being executed.
- On a Colima/macOS host, bind-mounting a script from `/tmp` can surface
  as an empty *directory* inside the container. Keep scripts inside the
  repo mount.

(On a Linux host the fonts are usually already at
`~/.Garmin/ConnectIQ/Fonts`, so no mount is needed.)

## Fonts

The image deliberately contains **no Garmin SDK content of its own**.
Garmin's Connect IQ SDK EULA forbids redistributing the SDK in whole or in
part, and device fonts - needed for any on-screen text, and therefore for
OCR - aren't in the base image at all. Locally you mount your own licensed
copy read-only (above).

In CI they're fetched at job time through Garmin's own authenticated font
API via [connect-iq-sdk-manager-cli](https://github.com/lindell/connect-iq-sdk-manager-cli),
a community CLI that speaks Garmin's real SSO flow headlessly, using the
repo's `GARMIN_USERNAME`/`GARMIN_PASSWORD` secrets (54 files for this
device, a few seconds). They're cached via `actions/cache` keyed on device
plus CLI version, so credentials are exercised once per cache key rather
than every run, and they only ever touch the runner's ephemeral disk -
never an image, the repo, or a registry.

An earlier alternative - bundling an open-source bitmap font as a
substitute - is dead-ended by an upstream bug: loading any custom
`FontResource` crashes the Linux simulator natively on the next `Menu2`
push (root-caused with a core dump on branch
`explore/e2e-testfont-probe`). With real device fonts no custom
`FontResource` is ever loaded, so that bug never comes into play.
