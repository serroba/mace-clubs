#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

staged_files=()
while IFS= read -r -d '' file; do
    staged_files+=("$file")
done < <(git diff --cached --name-only --diff-filter=ACMR -z)

if [[ ${#staged_files[@]} -eq 0 ]]; then
    exit 0
fi

echo "Checking staged files..."
git diff --cached --check

xml_files=()
monkey_files_changed=false
fit_contract_changed=false
workflow_changed=false

for file in "${staged_files[@]}"; do
    size="$(git cat-file -s ":$file")"
    if (( size > 1048576 )); then
        echo "Staged file exceeds 1 MiB: $file ($size bytes)" >&2
        exit 1
    fi

    if git show ":$file" | LC_ALL=C grep -Eq -- '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----'; then
        echo "Possible private key staged in $file" >&2
        exit 1
    fi

    case "$file" in
        *.xml) xml_files+=("$file") ;;
    esac
    case "$file" in
        source/*.mc) monkey_files_changed=true ;;
    esac
    case "$file" in
        resources/fitfields.xml|tools/schemas/fitfields.sch|tools/validate_fit_xml.sh)
            fit_contract_changed=true
            ;;
    esac
    case "$file" in
        .github/workflows/*.yml|.github/workflows/*.yaml) workflow_changed=true ;;
    esac
done

if [[ ${#xml_files[@]} -gt 0 ]]; then
    command -v xmllint >/dev/null || {
        echo "xmllint is required to validate staged XML files" >&2
        exit 1
    }
    for file in "${xml_files[@]}"; do
        xmllint --noout "$file"
    done
fi

if [[ "$fit_contract_changed" == true ]]; then
    make fit-schema
fi

if [[ "$monkey_files_changed" == true ]]; then
    make format-check lint
fi

if [[ "$workflow_changed" == true ]]; then
    command -v actionlint >/dev/null || {
        echo "actionlint is required when changing GitHub workflows" >&2
        echo "Install it with: brew install actionlint" >&2
        exit 1
    }
    actionlint
fi

echo "Staged-file checks passed"
