#!/usr/bin/env bash
# Captures the interval running screen for one device, headlessly.
#
# Exists because the question "does a two-colour Instinct render the accent
# white or black?" cannot be answered by reasoning, only by looking - and the
# macOS simulator cannot be driven when the host screen is locked. This runs
# the same driver against the same simulator under Xvfb, where there is no
# screen to lock.
#
#   MACE_E2E_DEVICE=instinct3solar45mm bash tools/e2e/linux/capture-work-screen.sh
#
# Writes tmp/work-<device>.png inside the repo mount.
set -euo pipefail
export DISPLAY="${DISPLAY:-:1}"
export HOME=/root
export MACE_E2E_DEVICE="${MACE_E2E_DEVICE:-instinct3solar45mm}"

if [ ! -d tools/node_modules/pixelmatch ]; then
    npm ci --prefix tools
fi

mkdir -p bin tmp
openssl genrsa -out /tmp/key.pem 4096 2>/dev/null
openssl pkcs8 -topk8 -inform PEM -outform DER -in /tmp/key.pem -out /tmp/key.der -nocrypt
monkeyc -f monkey.jungle -d "$MACE_E2E_DEVICE" -o bin/mace-clubs.prg -y /tmp/key.der -l 3

exec node --experimental-strip-types --disable-warning=ExperimentalWarning \
    tools/e2e/linux/capture-work-screen.ts
