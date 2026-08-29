#!/usr/bin/env bash
# Feasibility probe (NOT the real driver): proves the Garmin BDD e2e
# mechanics work headlessly on Linux - compiles the real app, boots the
# real simulator under Xvfb, drives it with xdotool, screenshots with
# ImageMagick, and OCRs with Tesseract. See README.md in this directory for
# what this confirmed and the two mechanics that differ from the macOS
# driver (tools/e2e/simulator.ts).
#
# Run via tools/e2e/linux/README.md's "Reproducing" section - needs fonts
# mounted from a locally-licensed SDK install (see README.md for why).
set -uo pipefail
export DISPLAY=:1
export HOME=/root

echo "=== compiling instinct3solar45mm ==="
mkdir -p /tmp/build
openssl genrsa -out /tmp/key.pem 4096 2>/dev/null
openssl pkcs8 -topk8 -inform PEM -outform DER -in /tmp/key.pem -out /tmp/key.der -nocrypt
monkeyc -f monkey.jungle -d instinct3solar45mm -o /tmp/build/app.prg -y /tmp/key.der -l 3 2>&1 | tail -10

echo "=== starting Xvfb + openbox + simulator ==="
Xvfb "$DISPLAY" -screen 0 1280x1024x24 > /tmp/xvfb.log 2>&1 &
sleep 3
openbox > /tmp/openbox.log 2>&1 &
sleep 2
simulator > /tmp/sim.log 2>&1 &
sleep 5

echo "=== launching app ==="
launched=false
for i in $(seq 1 8); do
    monkeydo /tmp/build/app.prg instinct3solar45mm > /tmp/monkeydo.log 2>&1 &
    sleep 6
    if ! grep -q "Unable to connect" /tmp/monkeydo.log; then
        launched=true
        break
    fi
done
echo "launched=$launched"

window=""
for i in $(seq 1 20); do
    window="$(xdotool search --name "CIQ Simulator" 2>/dev/null | head -1 || true)"
    [ -n "$window" ] && break
    sleep 2
done
echo "window=$window"
sleep 8

ocr_screen() {
    import -window "$window" /tmp/raw.png
    convert /tmp/raw.png -crop 176x176+102+189 /tmp/crop.png
    tesseract /tmp/crop.png - 2>/dev/null
}

# Global-focus key press (NOT --window targeted - confirmed ignored by this
# app, see README.md), retrying up to 6 times like the macOS driver's
# pressUntilChanged() since the app can swallow the first press or two
# after a transition.
press_until_changed() {
    local before after attempt
    before="$(ocr_screen)"
    for attempt in 1 2 3 4 5 6; do
        xdotool windowactivate --sync "$window"
        xdotool key --clearmodifiers Return
        sleep 2
        after="$(ocr_screen)"
        if [ "$after" != "$before" ]; then
            echo "$after"
            return 0
        fi
        before="$after"
    done
    echo "NO CHANGE AFTER 6 ATTEMPTS: $after"
    return 1
}

echo "=== idle screen ==="
ocr_screen
echo "=== press -> equipment picker ==="
press_until_changed
echo "=== press -> movement picker ==="
press_until_changed
