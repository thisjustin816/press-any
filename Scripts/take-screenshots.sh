#!/usr/bin/env bash
set -euo pipefail

# Captures the library, game, Build info, gameplay, import review, and Quick Play screens on an
# iOS simulator, seeded from TestROMs/. Needs macOS with Xcode, after `make bootstrap`.
#
#   Scripts/take-screenshots.sh [ROMS] [OUTPUT_DIR]
#
# ROMS is `hero` (the default), `all`, or a comma-separated list of manifest tags and filenames.
# Optional environment: SHOTS (`summary`, the default: one of each screen; `every-rom`: each
# ROM's game, Technical Info and gameplay), DEVICE (simulator name), APPEARANCE (light or dark),
# IMPORT_ROM (the file the import review opens, which is never seeded).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

roms="${1:-hero}"
output="${2:-screenshots}"
device="${DEVICE:-iPhone 17 Pro}"
appearance="${APPEARANCE:-light}"
import_rom="${IMPORT_ROM:-gbdk450-badsum.gb}"
shots="${SHOTS:-summary}"
derived_data="build/screenshots/DerivedData"
app="$derived_data/Build/Products/Debug-iphonesimulator/PressAny.app"

# The plan, tab-separated: `file <name>` for each ROM or patch to copy (the chosen ROMs, then any
# patch whose source was chosen), then `shot <scene> <seconds to wait> <name> <gamepad>` for each
# screenshot. The waits let gameplay get past the boot logo with the game's picture moving.
plan="$(python3 - "$roms" "$shots" "$import_rom" <<'PY'
import json, sys
wanted_arg, shots, import_rom = sys.argv[1:]
manifest = json.load(open("TestROMs/manifest.json"))
wanted = {w.strip() for w in wanted_arg.split(",") if w.strip()}
def chosen(entry):
    if "all" in wanted:
        return True
    if "hero" in wanted and entry["hero"]:
        return True
    return entry["filename"] in wanted or bool(wanted & set(entry["tags"]))
roms = [r for r in manifest["roms"] if chosen(r)]
if not roms:
    sys.exit(f"No ROMs in TestROMs/manifest.json match {wanted_arg!r}")
names = [r["filename"] for r in roms]
patches = [p for p in manifest["patches"] if p["source"] in names]
def first(test):
    return next((r["filename"] for r in roms if test(r)), None)
def stem(filename):
    return filename.rsplit(".", 1)[0]

lines = [f"file\t{f}" for f in names + [p["filename"] for p in patches]]
shot = lambda scene, wait, name, gamepad=0: lines.append(f"shot\t{scene}\t{wait}\t{name}\t{gamepad}")
# The first launch seeds the library, so it waits longest.
shot("library", 8, "library")
if shots == "every-rom":
    for f in names:
        shot(f"game:{f}", 4, f"game-{stem(f)}")
        shot(f"build-info:{f}", 4, f"build-info-{stem(f)}")
        shot(f"play:{f}", 8, f"play-{stem(f)}")
elif shots == "summary":
    # A Game with a patched Build shows Builds best, and GB Studio shows the most in Made With.
    shot(f"game:{(patches[0]['source'] if patches else names[0])}", 4, "game")
    shot(f"build-info:{first(lambda r: 'gbstudio' in r['tags']) or names[0]}", 4, "build-info")
    for system in ("GB", "GBC"):
        if f := first(lambda r: r["system"] == system):
            shot(f"play:{f}", 8, f"play-{system.lower()}")
else:
    sys.exit(f"SHOTS must be summary or every-rom, not {shots!r}")
shot(f"play:{names[0]}", 8, "play-gamepad", 1)
shot(f"import:unimported/{import_rom}", 4, "import-review")
shot(f"quick-play:{names[0]}", 8, "quick-play")
shot(f"quick-play-info:{names[0]}", 4, "quick-play-info")
print("\n".join(lines))
PY
)"
files=()
scenes=()
while IFS=$'\t' read -r kind rest; do
  case "$kind" in
    file) files+=("$rest") ;;
    shot) scenes+=("$rest") ;;
  esac
done <<<"$plan"
echo "Seeding: ${files[*]}"

mkdir -p "$output"
log="$output/app.log"
: >"$log"

xcodebuild -quiet -project PressAny.xcodeproj -scheme PressAny -configuration Debug \
  -destination "platform=iOS Simulator,name=$device" -derivedDataPath "$derived_data" build

udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS" in runtime:
        for d in devices:
            if d["name"] == name:
                print(d["udid"]); sys.exit()
sys.exit(f"No available simulator named {name!r}")
' "$device")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"

# Erasing would start the library empty too, but costs minutes of first-boot data migration;
# uninstalling the app is enough.
xcrun simctl bootstatus "$udid" -b
xcrun simctl uninstall "$udid" "$bundle_id" 2>/dev/null || true
# SpringBoard can refuse launches for a while after boot. Opening Settings first waits it out.
for attempt in 1 2 3 4 5 6; do
  xcrun simctl launch "$udid" com.apple.Preferences >/dev/null 2>&1 && break
  echo "Simulator not ready to launch apps (attempt $attempt); waiting." >&2
  sleep 10
done
xcrun simctl terminate "$udid" com.apple.Preferences 2>/dev/null || true
xcrun simctl ui "$udid" appearance "$appearance"
xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$udid" "$app"

fixtures="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)/Documents/ScreenshotROMs"
mkdir -p "$fixtures/unimported"
cp TestROMs/manifest.json "$fixtures/"
for file in "${files[@]}"; do
  if [[ -f "TestROMs/roms/$file" ]]; then
    cp "TestROMs/roms/$file" "$fixtures/"
  else
    cp "TestROMs/patches/$file" "$fixtures/"
  fi
done
# Kept out of the seeded folder so the review shows a new ROM rather than a duplicate.
cp "TestROMs/roms/$import_rom" "$fixtures/unimported/"

# SpringBoard's and the app's recent log, and any crash report, for a launch that failed.
collect_diagnostics() {
  xcrun simctl spawn "$udid" log show --last 5m --style compact \
    --predicate 'process == "SpringBoard" OR process == "PressAny"' >"$output/simulator.log" 2>&1 || true
  cp ~/Library/Logs/DiagnosticReports/PressAny* "$output/" 2>/dev/null || true
  echo "Launch failed; see $output/simulator.log." >&2
}

shot=0
# capture <scene> <seconds to wait> <name> <gamepad: 1 to act as if one were connected>
capture() {
  shot=$((shot + 1))
  local file
  file="$(printf '%s/%02d-%s.png' "$output" "$shot" "$3")"
  echo "== $1" >>"$log"
  # simctl doesn't truncate the output file, so a launch that prints nothing would repeat the last.
  rm -f "$log.tmp"
  local attempt
  for attempt in 1 2 3; do
    xcrun simctl launch --terminate-running-process --stdout="$PWD/$log.tmp" --stderr="$PWD/$log.tmp" \
      "$udid" "$bundle_id" -ScreenshotScene "$1" -ScreenshotGamepad "$([[ $4 == 1 ]] && echo YES || echo NO)" \
      >/dev/null && break
    if ((attempt == 3)); then
      collect_diagnostics
      return 1
    fi
    sleep 5
  done
  sleep "$2"
  xcrun simctl io "$udid" screenshot "$file" >/dev/null
  xcrun simctl terminate "$udid" "$bundle_id" || true
  cat "$log.tmp" >>"$log" 2>/dev/null || true
  echo "$file"
}

for scene in "${scenes[@]}"; do
  IFS=$'\t' read -r name_scene wait name gamepad <<<"$scene"
  capture "$name_scene" "$wait" "$name" "$gamepad"
done
rm -f "$log.tmp"

if grep -q "Couldn't seed\|seeding failed" "$log"; then
  echo "Seeding reported problems; see $log." >&2
fi
echo "Screenshots in $output"
