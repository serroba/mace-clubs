#!/usr/bin/env bash
# Verifies the release paperwork for a version exists and is current.
#
#   bash tools/check_release_docs.sh 0.15.2
#
# Run by the pre-push hook whenever a v* tag is pushed, and available as
# `make release-check VERSION=x.y.z` to check before tagging rather than
# discovering a gap at push time.
#
# This gate is the whole point of the generators: docs/product-updates/ had
# no entry for 19 of the first 26 tags, docs/store-listing.md still advertised
# the previous version, and docs/store-assets/ held screenshots from eleven
# releases earlier. Generating them is easy; remembering to is what failed.
set -euo pipefail

version="${1:-}"
if [[ -z "$version" ]]; then
    echo "usage: check_release_docs.sh <version>   (e.g. 0.15.2)" >&2
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

notes="docs/product-updates/v${version}.md"
listing="docs/store-listing.md"
assets="docs/store-assets/v${version}"
problems=()

[[ -f "$notes" ]] || problems+=("$notes is missing")

if [[ -f "$listing" ]]; then
    grep -q "v${version}" "$listing" || problems+=("$listing does not mention v${version}")
else
    problems+=("$listing is missing")
fi

if [[ -d "$assets" ]]; then
    [[ -f "$assets/manifest.json" ]] || problems+=("$assets/manifest.json is missing")
    shots=$(find "$assets" -name '*.png' | wc -l | tr -d ' ')
    [[ "$shots" -gt 0 ]] || problems+=("$assets contains no screenshots")
else
    problems+=("$assets is missing")
fi

# Uncommitted generated docs would ship a release whose paperwork is only on
# this machine, which is the same failure as not having it.
if [[ -n "$(git status --porcelain -- docs/product-updates "$listing" docs/store-assets 2>/dev/null)" ]]; then
    problems+=("generated release docs have uncommitted changes - commit them before tagging")
fi

if [[ ${#problems[@]} -gt 0 ]]; then
    echo "Release paperwork for v${version} is not ready:" >&2
    printf '  - %s\n' "${problems[@]}" >&2
    cat >&2 <<EOF

Generate it, review it, and commit it:

    make release-assets VERSION=${version}
    git add docs/ && git commit -m "Release paperwork for v${version}"

release-shots drives the simulator, so it needs an awake, unlocked screen.
To generate only the written docs: make release-docs VERSION=${version}
EOF
    exit 1
fi

echo "Release paperwork for v${version} is present and committed."
