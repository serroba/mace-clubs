#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# Prefer monkeyc already on PATH (the CI container has it but no Node);
# fall back to the resolver for local SDK-manager installs. The full path
# matters: resources.xsd is located relative to the monkeyc binary.
if ! monkeyc="$(command -v monkeyc 2>/dev/null)"; then
    monkeyc="$(node --experimental-strip-types "$repo_root/tools/resolve-tool.ts" monkeyc)"
fi
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
