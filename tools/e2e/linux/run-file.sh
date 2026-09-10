#!/usr/bin/env bash
# Runs ONE e2e file in the Linux container, for when you are iterating on it.
#
#   docker run --rm --entrypoint bash -v "$(pwd):/workspace" -w /workspace \
#     mace-clubs-e2e-linux:local \
#     /workspace/tools/e2e/linux/run-file.sh full/weight-editor.e2e.test.ts
#
# run-suite.sh next door runs all of them, which is what CI wants and what a
# five-minute feedback loop does not: writing full/weight-editor took six runs
# to get the navigation right, and seven other files have nothing to say about
# whether that one works.
#
# The other reason to reach for this rather than the macOS driver: the mac
# simulator needs an awake, unlocked display, and caffeinate cannot unlock one.
# A container does not care what the screen is doing.
#
# MACE_E2E_DEVICE selects the watch, as everywhere else. MACE_E2E_PRG and
# MACE_E2E_COVERAGE_LOG are honoured too, so this is also how to capture
# coverage for one file against an instrumented build (see `make coverage-e2e`
# for what builds one, and docs/e2e-testing.md for what the numbers mean).
set -euo pipefail
export DISPLAY="${DISPLAY:-:1}"
export HOME=/root
export MACE_E2E_DEVICE="${MACE_E2E_DEVICE:-instinct3solar45mm}"

FILE="${1:?usage: run-file.sh <path relative to tools/e2e, e.g. full/settings-menu.e2e.test.ts>}"

# Same reasoning as run-suite.sh: a bind-mounted repo usually brings the host's
# node_modules, a fresh checkout does not. Probing for a package rather than
# the directory, because an empty node_modules exists but resolves nothing.
if [ ! -d tools/node_modules/pixelmatch ]; then
    echo "=== installing driver dependencies ==="
    npm ci --prefix tools
fi

# Skipped when MACE_E2E_PRG already names a build to drive - a coverage run
# passes the instrumented .prg, and rebuilding the shipping one over it would
# measure nothing.
if [ -z "${MACE_E2E_PRG:-}" ]; then
    echo "=== building the app under test for $MACE_E2E_DEVICE ==="
    mkdir -p bin
    openssl genrsa -out /tmp/key.pem 4096 2>/dev/null
    openssl pkcs8 -topk8 -inform PEM -outform DER -in /tmp/key.pem -out /tmp/key.der -nocrypt
    monkeyc -f monkey.jungle -d "$MACE_E2E_DEVICE" -o bin/mace-clubs.prg -y /tmp/key.der -l 3
fi

echo "=== running $FILE on $MACE_E2E_DEVICE ==="
# From tools/e2e, because run-e2e.ts spawns each file with that working
# directory and the file paths are relative to it.
cd tools/e2e
exec node --experimental-strip-types --disable-warning=ExperimentalWarning --test "$FILE"
