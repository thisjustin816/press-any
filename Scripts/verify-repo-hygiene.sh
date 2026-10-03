#!/usr/bin/env bash
set -euo pipefail

# AGENTS.md: no commercial ROMs, saves or generated Xcode projects in the repository.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

images="$(git ls-files | grep -iE '\.(gb|gbc|gba|sgb|sav|state|srm|rom|nes|smc|sfc|nds|3ds|z64|n64)$' || true)"
if [[ -n "$images" ]]; then
  echo "Tracked game images or saves (use synthetic fixtures generated at test time):" >&2
  echo "$images" >&2
  status=1
fi

generated="$(git ls-files | grep -E '(^|/)[^/]+\.xcodeproj/' || true)"
if [[ -n "$generated" ]]; then
  echo "Generated Xcode project files are tracked; project.yml is the source of truth:" >&2
  echo "$generated" >&2
  status=1
fi

(( status == 0 )) && echo "Repository hygiene checks passed."
exit "$status"
