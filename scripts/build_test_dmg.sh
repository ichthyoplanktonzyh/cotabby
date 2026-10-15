#!/usr/bin/env bash
# Build or package the local, ad-hoc-signed Lingrove 0.5 test installer.
# Use --app-path to package a Release app that has already been built.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$REPO_ROOT/scripts/package_test_dmg.py" "$@"
