#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

git config core.hooksPath .githooks
echo "Git hooks enabled from .githooks"
echo "pre-commit: staged XML, FIT schema, Monkey C, workflow, secret, and size checks"
echo "pre-push: complete make check"
