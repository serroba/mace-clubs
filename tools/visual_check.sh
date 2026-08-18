#!/usr/bin/env bash
# Prototype: watch-UI visual regression against committed screen baselines.
#
# Boots the Connect IQ simulator under Xvfb, launches the app, walks a fixed
# set of screens by clicking the device skin's physical buttons, crops the
# watch screen out of each capture, and compares pixels (not bytes: PNG
# metadata differs run to run) against tools/baselines/screens/.
#
#   tools/visual_check.sh --update   regenerate the baselines
#   tools/visual_check.sh            verify against the baselines
#
# Requirements (the CI container image satisfies all but the last):
#   Xvfb, simulator, monkeyc, monkeydo, imagemagick, xdotool, and the Garmin
#   device fonts in $HOME/.Garmin/ConnectIQ/Fonts. The connectiq-tester image
#   ships WITHOUT the fonts (that is also why it cannot rasterize any device
#   font, see RenderTestSupport); instinct3solar45mm needs a 9.8MB subset of
#   25 .cft files from the SDK manager's Fonts directory.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE=instinct3solar45mm
BASELINES="$repo_root/tools/baselines/screens/$DEVICE"
# Watch screen area within the simulator's 446x700 Instinct skin window
# (calibrated from an idle-vs-menu pixel diff; the LCD is rendered 1:1).
CROP="176x176+102+189"

MODE=check
if [[ "${1:-}" == "--update" ]]; then
    MODE=update
fi

if [[ -z "${DISPLAY:-}" ]]; then
    export DISPLAY=:1
fi

command -v xdotool > /dev/null || { echo "xdotool is required"; exit 1; }
command -v import > /dev/null || { echo "imagemagick is required"; exit 1; }
command -v openbox > /dev/null || { echo "openbox is required (focus needs a window manager)"; exit 1; }
[[ -d "$HOME/.Garmin/ConnectIQ/Fonts" || -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Fonts" ]] \
    || { echo "Garmin device fonts not found; the simulator cannot draw text without them"; exit 1; }

resolve() {
    node --experimental-strip-types --disable-warning=ExperimentalWarning \
        "$repo_root/tools/resolve-tool.ts" "$1" 2>/dev/null || echo "$1"
}

MONKEYC="$(command -v monkeyc || resolve monkeyc)"
MONKEYDO="$(command -v monkeydo || resolve monkeydo)"
SIMULATOR="$(command -v simulator || resolve connectiq)"

workdir="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$workdir"' EXIT

if ! xdpyinfo > /dev/null 2>&1; then
    echo "Starting Xvfb on $DISPLAY..."
    Xvfb "$DISPLAY" -screen 0 1280x1024x24 > /dev/null 2>&1 &
    sleep 3
fi
# Without a window manager the simulator never takes input focus, and
# synthetic (--window) events are ignored; XTEST input needs real focus.
if ! pgrep -x openbox > /dev/null; then
    openbox > /dev/null 2>&1 &
    sleep 2
fi

echo "Compiling $DEVICE build..."
key="$workdir/key.der"
openssl genrsa -out "$workdir/key.pem" 4096 2> /dev/null
openssl pkcs8 -topk8 -inform PEM -outform DER -in "$workdir/key.pem" -out "$key" -nocrypt
"$MONKEYC" -f "$repo_root/monkey.jungle" -d "$DEVICE" -o "$workdir/app.prg" -y "$key" -l 3 > /dev/null

echo "Starting simulator..."
"$SIMULATOR" > /dev/null 2>&1 &

# monkeydo refuses to queue: retry until the (possibly slow-booting)
# simulator accepts the connection.
echo "Launching app..."
launched=false
for _ in $(seq 1 10); do
    sleep 10
    "$MONKEYDO" "$workdir/app.prg" "$DEVICE" > "$workdir/monkeydo.log" 2>&1 &
    sleep 6
    if ! grep -q "Unable to connect" "$workdir/monkeydo.log"; then
        launched=true
        break
    fi
done
if [[ "$launched" != true ]]; then
    echo "monkeydo could not reach the simulator:"
    cat "$workdir/monkeydo.log"
    exit 1
fi

# The simulator can take a while to open the device window, especially under
# emulation; poll rather than guessing a fixed delay.
window=""
for _ in $(seq 1 30); do
    window="$(xdotool search --name "CIQ Simulator" 2>/dev/null | head -1 || true)"
    if [[ -n "$window" ]]; then
        break
    fi
    sleep 3
done
if [[ -z "$window" ]]; then
    echo "Simulator window not found; log follows:"
    cat "$workdir/monkeydo.log"
    exit 1
fi
# Give the app time to draw its first frame.
sleep 10

press_select() {
    xdotool windowactivate --sync "$window"
    xdotool key Return
    sleep 3
}

capture() {
    import -window "$window" "$workdir/raw.png"
    convert "$workdir/raw.png" -crop "$CROP" "$workdir/$1.png"
}

# Screens, in on-watch order: idle, then SELECT into the equipment picker.
# Known gaps for the next iteration: Return does not select inside a Menu2
# (mapping TBD), and workout screens repaint every second (countdown/timers)
# so they need a paused or time-frozen state to baseline.
capture idle
press_select
capture equipment-menu

failures=0
for screen in idle equipment-menu; do
    baseline="$BASELINES/$screen.png"
    if [[ "$MODE" == update ]]; then
        mkdir -p "$BASELINES"
        cp "$workdir/$screen.png" "$baseline"
        echo "updated $baseline"
        continue
    fi
    if [[ ! -f "$baseline" ]]; then
        echo "MISSING baseline for $screen; run with --update"
        failures=$((failures + 1))
        continue
    fi
    pixels="$(compare -metric AE "$baseline" "$workdir/$screen.png" "$workdir/$screen-diff.png" 2>&1 || true)"
    if [[ "$pixels" == "0" ]]; then
        echo "$screen: OK"
    else
        echo "$screen: DIFFERS ($pixels pixels; diff in $workdir/$screen-diff.png)"
        cp "$workdir/$screen.png" "$BASELINES/$screen.actual.png" 2>/dev/null || true
        failures=$((failures + 1))
    fi
done

if [[ "$MODE" == check && "$failures" -gt 0 ]]; then
    echo "Visual check failed: $failures screen(s) differ."
    exit 1
fi
echo "Visual check complete."
