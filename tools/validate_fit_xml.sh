#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
monkeyc="$(node --experimental-strip-types "$repo_root/tools/resolve-tool.ts" monkeyc)"
resources_xsd="$(dirname "$monkeyc")/resources.xsd"
fitfields="$repo_root/resources/fitfields.xml"
schematron="$repo_root/tools/schemas/fitfields.sch"

if [[ ! -f "$resources_xsd" ]]; then
    echo "Garmin resources.xsd not found beside monkeyc: $resources_xsd" >&2
    exit 1
fi

xmllint --noout --schema "$resources_xsd" "$fitfields"
xmllint --noout --schematron "$schematron" "$fitfields"
echo "FIT XML satisfies Garmin's XSD and the app Schematron contract"
