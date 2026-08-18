#!/usr/bin/env bash
# Report SDK devices that support watch apps on Connect IQ 3.1+ but are
# missing from manifest.xml. Warning-only: new Garmin hardware should be a
# conscious decision, not a silent gap, so this never fails the build.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$repo_root/manifest.xml"

devices_dir="${1:-}"
if [[ -z "$devices_dir" ]]; then
    for candidate in \
        "$HOME/Library/Application Support/Garmin/ConnectIQ/Devices" \
        "$HOME/.Garmin/ConnectIQ/Devices" \
        "/root/.Garmin/ConnectIQ/Devices"; do
        if [[ -d "$candidate" ]]; then
            devices_dir="$candidate"
            break
        fi
    done
fi
if [[ -z "$devices_dir" || ! -d "$devices_dir" ]]; then
    echo "No Connect IQ device directory found; skipping the manifest drift check."
    exit 0
fi

missing=0
checked=0
for dir in "$devices_dir"/*/; do
    id="$(basename "$dir")"
    json="$dir/compiler.json"
    [[ -f "$json" ]] || continue
    # Bike computers and handhelds also report watchApp support but a wrist
    # workout app makes no sense there; the app targets wearables only.
    case "$id" in
        edge*|gpsmap*|montana*|etrex*|oregon*|rino*|foretrex*) continue ;;
    esac
    checked=$((checked + 1))
    # Watch-app support, on a part whose Connect IQ version is 3.1 or later.
    grep -q '"watchApp"' "$json" || continue
    grep -oE '"connectIQVersion" *: *"[0-9.]+"' "$json" \
        | grep -qE '"(3\.[1-9]|[4-9]\.|[1-9][0-9]\.)' || continue
    if ! grep -q "product id=\"$id\"" "$manifest"; then
        echo "::warning::$id supports watch apps on CIQ 3.1+ but is not in manifest.xml"
        missing=$((missing + 1))
    fi
done

echo "Checked $checked devices in $devices_dir: $missing compatible device(s) missing from the manifest."
