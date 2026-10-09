#!/usr/bin/env bash
set -euo pipefail

# AGENTS.md: no commercial ROMs, saves or generated Xcode projects in the repository. The one
# exception is the original test ROMs in TestROMs/roms/, each of which must match TestROMs/manifest.json.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

test_rom_dir="TestROMs/roms/"
images="$(git ls-files | grep -iE '\.(gb|gbc|gba|sgb|sav|state|srm|rom|nes|smc|sfc|nds|3ds|z64|n64)$' | grep -vE "^${test_rom_dir}[^/]+\.gbc?$" || true)"
if [[ -n "$images" ]]; then
  echo "Tracked game images or saves (use synthetic fixtures generated at test time, or add original ROMs under ${test_rom_dir}):" >&2
  echo "$images" >&2
  status=1
fi

# Every tracked test ROM is listed in the manifest with the recorded hash, and nothing else is in roms/.
if ! python3 - <<'PY'
import hashlib, json, subprocess, sys
manifest = {r["filename"]: r["sha256"] for r in json.load(open("TestROMs/manifest.json"))["roms"]}
tracked = subprocess.check_output(["git", "ls-files", "TestROMs/roms/"], text=True).split()
problems = []
for path in tracked:
    name = path.removeprefix("TestROMs/roms/")
    if name not in manifest:
        problems.append(f"{path} is not listed in TestROMs/manifest.json")
    elif hashlib.sha256(open(path, "rb").read()).hexdigest() != manifest[name]:
        problems.append(f"{path} does not match its SHA-256 in TestROMs/manifest.json")
problems += [f"TestROMs/roms/{n} is in the manifest but not tracked" for n in manifest if f"TestROMs/roms/{n}" not in tracked]
print("\n".join(problems), file=sys.stderr)
sys.exit(1 if problems else 0)
PY
then
  status=1
fi

generated="$(git ls-files | grep -E '(^|/)[^/]+\.xcodeproj/' || true)"
if [[ -n "$generated" ]]; then
  echo "Generated Xcode project files are tracked; project.yml is the source of truth:" >&2
  echo "$generated" >&2
  status=1
fi

# The app shows SameBoy's license verbatim (Settings > Acknowledgements).
sameboy_license="Packages/EmulatorKit/Dependencies/SameBoy/LICENSE"
if [[ -f "$sameboy_license" ]] && ! cmp -s "$sameboy_license" App/Acknowledgements/SameBoy-LICENSE.txt; then
  echo "App/Acknowledgements/SameBoy-LICENSE.txt differs from the SameBoy submodule's LICENSE; copy it again." >&2
  status=1
fi

# Every required-reason API the code uses is declared in the privacy manifest.
if ! python3 -I Scripts/verify-required-reason-apis.py; then
  status=1
fi

(( status == 0 )) && echo "Repository hygiene checks passed."
exit "$status"
