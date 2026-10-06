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
# TEXT_SIZE (`default`, or a `simctl ui content_size` value such as
# accessibility-extra-extra-extra-large), IMPORT_ROM (the file the import review opens, which is
# never seeded).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

roms="${1:-hero}"
output="${2:-screenshots}"
device="${DEVICE:-iPhone 17 Pro}"
appearance="${APPEARANCE:-light}"
text_size="${TEXT_SIZE:-default}"
import_rom="${IMPORT_ROM:-gbdk450-badsum.gb}"
shots="${SHOTS:-summary}"
derived_data="build/screenshots/DerivedData"
app="$derived_data/Build/Products/Debug-iphonesimulator/PressAny.app"

# The plan, tab-separated: `file <name>` for each ROM or patch to copy (the chosen ROMs, then any
# patch whose source was chosen), `menus <game ROM> <gameplay ROM>` for the menu UI tests, then
# `shot <scene> <seconds to wait> <name> <flags>` for each
# screenshot. The waits let gameplay get past the boot logo with the game's picture moving. Flags
# are the Debug-only launch arguments in App/Screenshots/ScreenshotScene.swift, or `-` for none.
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
# A Game with a patched Build shows Builds best.
game_rom = patches[0]["source"] if patches else names[0]
lines.append(f"menus\t{game_rom}\t{names[0]}")
shot = lambda scene, wait, name, flags="-": lines.append(f"shot\t{scene}\t{wait}\t{name}\t{flags}")
# The first launch seeds the library, so it waits longest.
shot("library", 8, "library")
shot("settings", 4, "settings")
if shots == "every-rom":
    for f in names:
        shot(f"game:{f}", 4, f"game-{stem(f)}")
        shot(f"build-info:{f}", 4, f"build-info-{stem(f)}")
        shot(f"play:{f}", 10, f"play-{stem(f)}")
elif shots == "summary":
    shot(f"game:{game_rom}", 4, "game")
    # GB Studio shows the most in Made With.
    shot(f"build-info:{first(lambda r: 'gbstudio' in r['tags']) or names[0]}", 4, "build-info")
    for system in ("GB", "GBC"):
        if f := first(lambda r: r["system"] == system):
            shot(f"play:{f}", 10, f"play-{system.lower()}")
else:
    sys.exit(f"SHOTS must be summary or every-rom, not {shots!r}")
for system in ("GB", "GBC"):
    if f := first(lambda r: r["system"] == system):
        for preset in ("lcd1x", "lcd3x"):
            shot(f"play:{f}", 10, f"play-{system.lower()}-{preset}", f"-ScreenshotLCDFilter {preset}")
shot(f"play:{names[0]}", 10, "play-gamepad", "-ScreenshotGamepad YES")
# The Playtiles layout is drawn after a GBC skin, so it shows a GBC game when one was chosen.
playtiles_rom = first(lambda r: r["system"] == "GBC") or names[0]
shot(f"play:{playtiles_rom}", 10, "playtiles", "-ScreenshotLayout playtiles")
shot(f"play:{playtiles_rom}", 10, "playtiles-gamepad", "-ScreenshotLayout playtiles -ScreenshotGamepad YES")
shot(f"import:unimported/{import_rom}", 4, "import-review")
shot(f"quick-play:{names[0]}", 10, "quick-play")
shot(f"quick-play-info:{names[0]}", 4, "quick-play-info")
print("\n".join(lines))
PY
)"
files=()
scenes=()
while IFS=$'\t' read -r kind rest; do
  case "$kind" in
    file) files+=("$rest") ;;
    menus) IFS=$'\t' read -r game_rom play_rom <<<"$rest" ;;
    shot) scenes+=("$rest") ;;
  esac
done <<<"$plan"
echo "Seeding: ${files[*]}"

mkdir -p "$output"
output="$(cd "$output" && pwd)"
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
if [ "$text_size" != default ]; then
  xcrun simctl ui "$udid" content_size "$text_size"
fi
xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$udid" "$app"

# Staged on the Mac, then copied into the app. The menu UI tests have the app seed from the
# staged folder itself, whatever xcodebuild does to the installed app's data.
staging="$PWD/build/screenshots/fixtures"
rm -rf "$staging"
mkdir -p "$staging/unimported"
cp TestROMs/manifest.json "$staging/"
for file in "${files[@]}"; do
  if [[ -f "TestROMs/roms/$file" ]]; then
    cp "TestROMs/roms/$file" "$staging/"
  else
    cp "TestROMs/patches/$file" "$staging/"
  fi
done
# Kept out of the seeded folder so the review shows a new ROM rather than a duplicate.
cp "TestROMs/roms/$import_rom" "$staging/unimported/"
fixtures="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)/Documents/ScreenshotROMs"
mkdir -p "$fixtures"
cp -R "$staging/." "$fixtures/"

# SpringBoard's and the app's recent log, and any crash report, for a launch that failed.
collect_diagnostics() {
  xcrun simctl spawn "$udid" log show --last 5m --style compact \
    --predicate 'process == "SpringBoard" OR process == "PressAny"' >"$output/simulator.log" 2>&1 || true
  cp ~/Library/Logs/DiagnosticReports/PressAny* "$output/" 2>/dev/null || true
  echo "Launch failed; see $output/simulator.log." >&2
}

shot=0
# capture <scene> <seconds to wait> <name> [launch arguments...]
capture() {
  local scene="$1" wait="$2" name="$3"
  shift 3
  shot=$((shot + 1))
  local file
  file="$(printf '%s/%02d-%s.png' "$output" "$shot" "$name")"
  echo "== $scene $*" >>"$log"
  # simctl doesn't truncate the output file, so a launch that prints nothing would repeat the last.
  rm -f "$log.tmp"
  local attempt
  for attempt in 1 2 3; do
    xcrun simctl launch --terminate-running-process --stdout="$log.tmp" --stderr="$log.tmp" \
      "$udid" "$bundle_id" -ScreenshotScene "$scene" "$@" >/dev/null && break
    if ((attempt == 3)); then
      collect_diagnostics
      return 1
    fi
    sleep 5
  done
  sleep "$wait"
  xcrun simctl io "$udid" screenshot "$file" >/dev/null
  # Before its first frame the app shows the blank launch screen, a PNG under 100 KB where every
  # real screen is over 150 KB. A slow simulator gets two more chances.
  for attempt in 1 2; do
    (($(wc -c <"$file") < 120000)) || break
    echo "$file looks blank; waiting and taking it again ($attempt)." >&2
    sleep 6
    xcrun simctl io "$udid" screenshot "$file" >/dev/null
  done
  xcrun simctl terminate "$udid" "$bundle_id" || true
  cat "$log.tmp" >>"$log" 2>/dev/null || true
  echo "$file"
}

for scene in "${scenes[@]}"; do
  IFS=$'\t' read -r name_scene wait name flags <<<"$scene"
  arguments=()
  [[ $flags == - ]] || read -r -a arguments <<<"$flags"
  # Written so bash 3.2, macOS's, accepts an empty array under `set -u`.
  capture "$name_scene" "$wait" "$name" ${arguments[@]+"${arguments[@]}"}
done
rm -f "$log.tmp"

# Pop-up menus open only on a tap, so the UI tests in ScreenshotTests/ open them and save a
# screenshot of each. A menu that doesn't open fails the run once everything else is saved.
menus="$output/menus"
# Without -quiet, which hides why a test failed; the filter keeps the results and failures.
set +e
TEST_RUNNER_SCREENSHOT_ROMS="$staging" TEST_RUNNER_SCREENSHOT_OUTPUT="$menus" \
  TEST_RUNNER_SCREENSHOT_GAME_ROM="$game_rom" TEST_RUNNER_SCREENSHOT_PLAY_ROM="$play_rom" \
  xcodebuild test -project PressAny.xcodeproj -scheme PressAnyScreenshots \
  -destination "id=$udid" -derivedDataPath "$derived_data" 2>&1 |
  grep -E 'error:|Test Case .*(passed|failed)|Failing tests|\*\* TEST'
menu_status=${PIPESTATUS[0]}
set -e
for file in "$menus"/*.png; do
  [[ -e $file ]] || continue
  shot=$((shot + 1))
  mv "$file" "$(printf '%s/%02d-%s' "$output" "$shot" "$(basename "$file")")"
  echo "$output/$(printf '%02d' "$shot")-$(basename "$file")"
done
rmdir "$menus" 2>/dev/null || true
((menu_status == 0)) || echo "The menu UI tests failed (exit $menu_status); see the log above." >&2

if grep -q "Couldn't seed\|seeding failed" "$log"; then
  echo "Seeding reported problems; see $log." >&2
fi
echo "Screenshots in $output"
exit "$menu_status"
