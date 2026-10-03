#!/usr/bin/env bash
set -euo pipefail

# Fail when a test target exists that no CI layer filter in ci.yml names.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/ci.yml"

missing=()
for dir in "$repo_root"/Packages/EmulatorKit/Tests/*/; do
  target="$(basename "$dir")"
  # Match the whole name: CoreTests must not pass because EmulationCoreTests is listed.
  if ! grep -Eq "(^|[^A-Za-z0-9_])${target}([^A-Za-z0-9_]|\$)" "$workflow"; then
    missing+=("$target")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "Test targets that no job in .github/workflows/ci.yml runs: ${missing[*]}" >&2
  exit 1
fi
echo "Every test target is named in ci.yml."
