#!/usr/bin/env bash
# Scratch probe (NOT committed) - verifies the :testFont CI-only build
# variant (monkey.e2e.jungle, source/ui/AppFont.mc, resources-testfont/)
# survives past the crash point probe-nofont.sh hit and produces
# OCR-legible text on an app-drawn onUpdate() screen - with ZERO device
# fonts mounted, matching a bare GitHub-hosted runner.
set -uo pipefail
export DISPLAY=:1
export HOME=/root

echo "=== fonts present? (should be none) ==="
find /root/.Garmin -iname "*font*" 2>&1

echo "=== compiling instinct3solar45mm with monkey.e2e.jungle ==="
mkdir -p /tmp/build
openssl genrsa -out /tmp/key.pem 4096 2>/dev/null
openssl pkcs8 -topk8 -inform PEM -outform DER -in /tmp/key.pem -out /tmp/key.der -nocrypt
monkeyc -f monkey.e2e.jungle -d instinct3solar45mm -o /tmp/build/app.prg -y /tmp/key.der -l 3 2>&1 | tail -20

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

if [ -z "$window" ]; then
    echo "=== NO SIMULATOR WINDOW FOUND - dumping logs and bailing out ==="
    echo "--- xvfb.log ---"; cat /tmp/xvfb.log 2>&1
    echo "--- openbox.log ---"; cat /tmp/openbox.log 2>&1
    echo "--- sim.log ---"; cat /tmp/sim.log 2>&1
    echo "--- monkeydo.log ---"; cat /tmp/monkeydo.log 2>&1
    echo "--- xdotool search (no filter) ---"; xdotool search --name "" 2>&1
    exit 1
fi
sleep 8

# `import -window ""` blocks forever waiting for an interactive click if
# ever called with no window id - timeout guards against silently hanging
# the whole CI job instead of failing loudly.
ocr_screen() {
    timeout 15 import -window "$window" /tmp/raw.png || {
        echo "import timed out/failed for window=$window"
        return 1
    }
    convert /tmp/raw.png -crop 176x176+102+189 /tmp/crop.png
    cp /tmp/crop.png "tools/e2e/linux/shot-$1.png"
    tesseract /tmp/crop.png - 2>/dev/null
}

press_until_changed() {
    local before after attempt
    before="$(ocr_screen "$1-before")"
    for attempt in 1 2 3 4 5 6; do
        xdotool windowactivate --sync "$window" 2>&1
        xdotool key --clearmodifiers Return
        sleep 2
        after="$(ocr_screen "$1-$attempt")"
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
ocr_screen idle
echo "=== press -> equipment picker (Menu2) ==="
press_until_changed equipment
echo "=== press -> movement picker (Menu2) ==="
press_until_changed movement
echo "=== press -> GET READY countdown (app-drawn onUpdate, custom font) ==="
press_until_changed countdown
echo "--- is simulator still alive? ---"
pgrep -a simulator || echo "simulator PROCESS GONE"

echo "=== waiting through 5s countdown into WORK (app-drawn onUpdate, custom font) ==="
sleep 6
ocr_screen work
echo "--- is simulator still alive after WORK screen? ---"
pgrep -a simulator || echo "simulator PROCESS GONE"

echo "=== final monkeydo.log tail (crash check) ==="
tail -40 /tmp/monkeydo.log
