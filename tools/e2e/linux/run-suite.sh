#!/usr/bin/env bash
# Runs the real e2e suite (tools/e2e/*.e2e.test.ts, via the same
# run-e2e.ts entrypoint macOS uses) inside the Linux container - the
# platform-linux.ts backend replaces AppleScript/screencapture/Vision with
# xdotool/ImageMagick/Tesseract.
#
# Needs device fonts present at /root/.Garmin/ConnectIQ/Fonts (mounted from
# a locally-licensed install, or fetched in CI - see README.md). Xvfb and
# openbox are started by the driver itself, not here.
set -euo pipefail
export DISPLAY="${DISPLAY:-:1}"
export HOME=/root

echo "=== building the app under test ==="
mkdir -p bin
openssl genrsa -out /tmp/key.pem 4096 2>/dev/null
openssl pkcs8 -topk8 -inform PEM -outform DER -in /tmp/key.pem -out /tmp/key.der -nocrypt
monkeyc -f monkey.jungle -d instinct3solar45mm -o bin/mace-clubs.prg -y /tmp/key.der -l 3

echo "=== running the e2e suite ==="
exec node --experimental-strip-types --disable-warning=ExperimentalWarning tools/e2e/run-e2e.ts
