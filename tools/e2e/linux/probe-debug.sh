#!/usr/bin/env bash
# Forensics probe that root-caused the Menu2+custom-font segfault documented
# in tools/e2e/testfont/README.md - captures a real core dump and pulls a
# gdb backtrace instead of guessing at black-box hypotheses. Needs a gdb-
# enabled image (Dockerfile.debug layers gdb/binutils/file onto the base
# probe image); see that file and tools/e2e/linux/README.md's "Debugging a
# crash" section for how to run this.
set -uo pipefail
export DISPLAY=:1
export HOME=/root
ulimit -c unlimited
# On the bind mount (not /tmp) so the core survives after --rm tears the
# container down.
mkdir -p /workspace/.debug-cores
cd /workspace/.debug-cores
echo "core_pattern: $(cat /proc/sys/kernel/core_pattern 2>&1)"
SIMULATOR_BIN="$(command -v simulator)"
echo "simulator binary: $SIMULATOR_BIN"
file "$SIMULATOR_BIN" 2>&1

echo "=== compiling instinct3solar45mm with monkey.e2e.jungle ==="
mkdir -p /tmp/build
openssl genrsa -out /tmp/key.pem 4096 2>/dev/null
openssl pkcs8 -topk8 -inform PEM -outform DER -in /tmp/key.pem -out /tmp/key.der -nocrypt
(cd /workspace && monkeyc -f monkey.e2e.jungle -d instinct3solar45mm -o /tmp/build/app.prg -y /tmp/key.der -l 3 2>&1 | tail -20)

echo "=== starting Xvfb + openbox + simulator (cwd=/workspace/.debug-cores so core lands here) ==="
Xvfb "$DISPLAY" -screen 0 1280x1024x24 > /tmp/xvfb.log 2>&1 &
sleep 3
openbox > /tmp/openbox.log 2>&1 &
sleep 2
(cd /workspace/.debug-cores && simulator > /tmp/sim.log 2>&1) &
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

echo "=== idle screen (draws with custom font) ==="
timeout 15 import -window "$window" /tmp/idle.png 2>&1 || echo "import failed (ok, just a screenshot)"

echo "=== pressing Return up to 6 times -> triggers Menu2 push -> expect segfault ==="
for attempt in 1 2 3 4 5 6; do
    xdotool windowactivate --sync "$window" 2>&1
    xdotool key --clearmodifiers Return
    sleep 3
    if ! pgrep simulator > /dev/null; then
        echo "simulator died after attempt $attempt"
        break
    fi
    echo "attempt $attempt: simulator still alive"
done

echo "=== looking for core files ==="
ls -la /workspace/.debug-cores

mapfile -t CORES < <(find /workspace/.debug-cores -maxdepth 1 -type f -iname "*core*" 2>/dev/null)
echo "CORES=${CORES[*]}"

if [ "${#CORES[@]}" -eq 0 ]; then
    echo "NO CORE FILE FOUND"
    echo "--- sim.log ---"
    cat /tmp/sim.log
else
    for CORE in "${CORES[@]}"; do
        echo "=== file $CORE ==="
        file "$CORE"
        echo "=== gdb backtrace for $CORE ==="
        gdb -batch \
            -ex "bt full" \
            -ex "info threads" \
            -ex "thread apply all bt" \
            -ex "info registers" \
            -ex "x/20i \$pc" \
            "$SIMULATOR_BIN" "$CORE" 2>&1
        echo "=== end $CORE ==="
    done
fi
