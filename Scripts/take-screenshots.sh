#!/usr/bin/env bash
set -euo pipefail

# Captures the library, game, Build info, gameplay, import review, and Quick Play screens on an
# iOS simulator, seeded from TestROMs/. Needs macOS with Xcode, after `make bootstrap`.
#
#   Scripts/take-screenshots.sh [ROMS] [OUTPUT_DIR]
#
# ROMS is `hero` (the default), `all`, or a comma-separated list of manifest tags and filenames.
# Optional environment: SHOTS (`listing`, the default: the nine App Store screenshots, numbered in
# listing order; `summary`: one of each screen and every menu, for review; `every-rom`: summary
# plus each ROM's game, Technical Info and gameplay), DEVICE (simulator name), APPEARANCE (light or dark),
# TEXT_SIZE (`default`, or a `simctl ui content_size` value such as
# accessibility-extra-extra-extra-large), IMPORT_ROM (the file the import review opens, which is
# never seeded), and GAME_URL with GAME_SHA256 (and optionally GAME_NAME): a real game for the
# listing's gameplay shots, a .gb, .gbc or .zip holding one, downloaded at run time so neither the
# game nor its name is kept in the repository. Use only a game whose author allows it.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

roms="${1:-hero}"
output="${2:-screenshots}"
device="${DEVICE:-iPhone 17 Pro}"
appearance="${APPEARANCE:-light}"
text_size="${TEXT_SIZE:-default}"
import_rom="${IMPORT_ROM:-zgb-dmg.gb}"
shots="${SHOTS:-listing}"
derived_data="build/screenshots/DerivedData"
app="$derived_data/Build/Products/Debug-iphonesimulator/PressAny.app"

# The listing's gameplay shots use a real game when one is given, described as a manifest entry.
game_dir="build/screenshots/game"
game_entry=""
if [[ -n ${GAME_URL:-} ]]; then
  if [[ -z ${GAME_SHA256:-} ]]; then
    echo "GAME_SHA256 is required with GAME_URL, so a changed download is refused." >&2
    exit 1
  fi
  rm -rf "$game_dir"
  mkdir -p "$game_dir"
  curl -fsSL --retry 3 "$GAME_URL" -o "$game_dir/download"
  # Heredocs stay out of $(...): macOS's bash 3.2 misreads one holding an odd number of quotes.
  python3 - "$game_dir" "$GAME_URL" "$GAME_SHA256" "${GAME_NAME:-}" >"$game_dir/entry.json" <<'PY'
import hashlib, json, sys, zipfile
from pathlib import Path
folder, url, expected, name = Path(sys.argv[1]), *sys.argv[2:]
download = folder / "download"
filename = Path(url.split("?")[0]).name
if zipfile.is_zipfile(download):
    with zipfile.ZipFile(download) as archive:
        roms = [i for i in archive.infolist()
                if i.filename.lower().endswith((".gb", ".gbc")) and not Path(i.filename).name.startswith(".")]
        if len(roms) != 1:
            sys.exit(f"The zip at GAME_URL must hold exactly one .gb or .gbc, not {len(roms)}.")
        data, filename = archive.read(roms[0]), Path(roms[0].filename).name
else:
    data = download.read_bytes()
download.unlink()
if hashlib.sha256(data).hexdigest() != expected.strip().lower():
    sys.exit("The game's SHA-256 doesn't match GAME_SHA256.")
if len(data) < 0x150:
    sys.exit("The game is too small to be a Game Boy ROM.")
color = data[0x143] in (0x80, 0xC0)
if not filename.lower().endswith((".gb", ".gbc")):
    filename = "game.gbc" if color else "game.gb"
if not name:
    name = data[0x134:0x143 if color else 0x144].split(b"\0")[0].decode("ascii", "replace").strip().title()
(folder / filename).write_bytes(data)
print(json.dumps({"filename": filename, "name": name or "Game", "system": "GBC" if color else "GB",
                  "sha256": hashlib.sha256(data).hexdigest(), "hero": True, "tags": ["listing-game"]}))
PY
  game_entry="$(cat "$game_dir/entry.json")"
  echo "Gameplay shots use $(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["filename"])' "$game_entry")."
fi

# The plan, tab-separated: `file <name>` for each ROM or patch to copy (the chosen ROMs, then any
# patch whose source was chosen), `menus <game ROM> <gameplay ROM>` for the menu UI tests,
# `only <test>` for each UI test to run (all of them when there is none), `order <names>` for the
# final numbering, then `shot <scene> <seconds to wait> <name> <ready> <flags>` for each
# screenshot. The waits let gameplay get past the boot logo with the game's picture moving. Ready
# is `ready` when the app reports the scene ready, and the wait counts from then, or `-`. Flags
# are the Debug-only launch arguments in App/Screenshots/ScreenshotScene.swift, or `-` for none.
plan_file="build/screenshots/plan.tsv"
mkdir -p "$(dirname "$plan_file")"
python3 - "$roms" "$shots" "$import_rom" "$game_entry" >"$plan_file" <<'PY'
import json, sys
wanted_arg, shots, import_rom, game_entry = sys.argv[1:]
game = json.loads(game_entry) if game_entry else None
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

lines = [f"file\t{f}" for f in names + [p["filename"] for p in patches] + ([game["filename"]] if game else [])]
# A Game with a patched Build shows Builds best.
game_rom = patches[0]["source"] if patches else names[0]
lines.append(f"menus\t{game_rom}\t{game['filename'] if game and shots == 'listing' else names[0]}")
shot = lambda scene, wait, name, flags="-", ready="-": lines.append(f"shot\t{scene}\t{wait:g}\t{name}\t{ready}\t{flags}")
gb = first(lambda r: r["system"] == "GB") or names[0]
gbc = first(lambda r: r["system"] == "GBC") or names[0]
if shots == "listing" and game:
    # A real game plays in every gameplay shot; the test ROMs still fill the library.
    gb = gbc = game["filename"]
if shots == "listing":
    # Captured in a practical order (the first launch seeds the library, so it goes first and
    # waits longest), then renumbered in App Store order: the first three show in search
    # results, so they carry gameplay, the library and a Game's Builds and saves.
    shot("library", 8, "library")
    shot(f"game:{game_rom}", 4, "game")
    shot(f"build-info:{first(lambda r: 'gbstudio' in r['tags']) or names[0]}", 4, "build-info", ready="ready")
    shot(f"play:{gbc}", 10, "play")
    shot(f"play:{gb}", 10, "play-lcd", "-ScreenshotLCDFilter lcd3x")
    shot(f"import:unimported/{import_rom}", 4, "import-review")
    shot(f"quick-play:{gb}", 10, "quick-play")
    # Landscape gameplay needs the device turned, which only a UI test can do.
    for test in ("test9LandscapeGameplayAndClosingReturnsToPortrait", "testLandscapeQuickPlayWithController"):
        lines.append(f"only\tPressAnyScreenshotTests/MenuScreenshots/{test}")
    lines.append("order\t" + " ".join(["play", "library", "game", "play-landscape", "import-review",
        "play-lcd", "build-info", "quick-play", "play-landscape-gamepad"]))
    print("\n".join(lines))
    sys.exit()
# The first launch seeds the library, so it waits longest.
shot("library", 8, "library")
shot("settings", 4, "settings")
if shots == "every-rom":
    for f in names:
        shot(f"game:{f}", 4, f"game-{stem(f)}")
        shot(f"build-info:{f}", 4, f"build-info-{stem(f)}", ready="ready")
        shot(f"play:{f}", 10, f"play-{stem(f)}")
elif shots == "summary":
    shot(f"game:{game_rom}", 4, "game")
    # GB Studio shows the most in Made With.
    shot(f"build-info:{first(lambda r: 'gbstudio' in r['tags']) or names[0]}", 4, "build-info", ready="ready")
    for system in ("GB", "GBC"):
        if f := first(lambda r: r["system"] == system):
            shot(f"play:{f}", 10, f"play-{system.lower()}")
else:
    sys.exit(f"SHOTS must be listing, summary or every-rom, not {shots!r}")
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
files=()
scenes=()
only=()
order=""
while IFS=$'\t' read -r kind rest; do
  case "$kind" in
    file) files+=("$rest") ;;
    menus) IFS=$'\t' read -r game_rom play_rom <<<"$rest" ;;
    only) only+=("-only-testing:$rest") ;;
    order) order="$rest" ;;
    shot) scenes+=("$rest") ;;
  esac
done <"$plan_file"
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
  elif [[ -f "TestROMs/patches/$file" ]]; then
    cp "TestROMs/patches/$file" "$staging/"
  else
    cp "$game_dir/$file" "$staging/"
  fi
done
if [[ -n $game_entry ]]; then
  # The app seeds each manifest ROM as a Game, so the real game joins the staged manifest.
  python3 - "$staging/manifest.json" "$game_entry" <<'PY'
import json, sys
path, entry = sys.argv[1], json.loads(sys.argv[2])
manifest = json.load(open(path))
manifest["roms"].append(entry)
json.dump(manifest, open(path, "w"), indent=2)
PY
fi
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

# The app logs this, as ScreenshotScene spells it, once a scene that takes time to settle is ready.
ready_message="Screenshot scene ready"

# wait_ready <seconds>: waits for the app to log that the scene is ready. A scene that doesn't
# report in time is taken anyway, with a warning.
wait_ready() {
  local deadline=$((SECONDS + $1))
  while ((SECONDS < deadline)); do
    grep -qF "$ready_message" "$log.tmp" 2>/dev/null && return 0
    sleep 0.5
  done
  echo "The app didn't report the scene ready within $1 seconds; taking it anyway." >&2
}

# A fresh simulator can show a system notification banner, such as one about Apple Intelligence,
# at any time, and nothing simctl offers turns those off. A banner stays about five seconds, so
# each shot is compared with a second one taken after that: a difference along the screen's left
# edge, below the status bar, where the banner's end sits and every scene holds still, means one
# of them was covered, and the scene is taken again. This exits 1 for a difference.
banner_check="build/screenshots/banner-check.py"
cat >"$banner_check" <<'PY'
import struct, sys, zlib

# Pixels near the screen's left edge, below the status bar: where a notification banner's left end
# sits, and where every scene shows something that holds still.
LEFT, WIDTH, TOP, BOTTOM = 8, 48, 120, 440

def strip(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    pos, idat, header = 8, [], None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", data[pos + 8:pos + 8 + length])
        elif kind == b"IDAT":
            idat.append(data[pos + 8:pos + 8 + length])
        pos += 12 + length
    width, height, depth, color, _, _, interlace = header
    if depth != 8 or interlace or color not in (2, 6) or height < BOTTOM:
        return None
    bpp = 4 if color == 6 else 3
    stride = width * bpp + 1
    raw = zlib.decompressobj().decompress(b"".join(idat), stride * BOTTOM)
    count = (LEFT + WIDTH) * bpp
    previous, rows = bytearray(count), []
    for y in range(BOTTOM):
        kind, line = raw[y * stride], bytearray(raw[y * stride + 1:y * stride + 1 + count])
        for i in range(count):
            a = line[i - bpp] if i >= bpp else 0
            b = previous[i]
            c = previous[i - bpp] if i >= bpp else 0
            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        previous = line
        if y >= TOP:
            rows.append(line[LEFT * bpp:])
    return bpp, rows

shot, later = strip(sys.argv[1]), strip(sys.argv[2])
if not shot or not later or shot[0] != later[0]:
    sys.exit(0)
bpp = shot[0]
changed = sum(1 for one, two in zip(shot[1], later[1]) for x in range(0, len(one), bpp)
              if max(abs(one[x + i] - two[x + i]) for i in range(3)) > 8)
sys.exit(1 if changed > WIDTH * (BOTTOM - TOP) // 50 else 0)
PY

shot=0
# shoot <file> <scene> <seconds to wait> <ready> [launch arguments...]: launches the scene and
# saves the screen to <file> once it's ready and has waited, leaving the app running.
shoot() {
  local file="$1" scene="$2" wait="$3" ready="$4"
  shift 4
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
  [[ $ready == - ]] || wait_ready 30
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
}

# capture <scene> <seconds to wait> <name> <ready> [launch arguments...]
capture() {
  local scene="$1" wait="$2" name="$3" ready="$4"
  shift 4
  shot=$((shot + 1))
  local file check arguments attempt
  file="$(printf '%s/%02d-%s.png' "$output" "$shot" "$name")"
  check="$output/banner-check.png"
  arguments=("$@")
  echo "== $scene $*" >>"$log"
  for attempt in 1 2 3; do
    shoot "$file" "$scene" "$wait" "$ready" ${arguments[@]+"${arguments[@]}"} || return 1
    sleep 7
    xcrun simctl io "$udid" screenshot "$check" >/dev/null
    xcrun simctl terminate "$udid" "$bundle_id" || true
    cat "$log.tmp" >>"$log" 2>/dev/null || true
    python3 "$banner_check" "$file" "$check" && break
    if ((attempt == 3)); then
      echo "$file may still show a notification banner." >&2
    else
      echo "$file may show a notification banner; taking it again ($attempt)." >&2
    fi
  done
  rm -f "$check"
  echo "$file"
}

for scene in "${scenes[@]}"; do
  IFS=$'\t' read -r name_scene wait name ready flags <<<"$scene"
  arguments=()
  [[ $flags == - ]] || read -r -a arguments <<<"$flags"
  # Written so bash 3.2, macOS's, accepts an empty array under `set -u`.
  capture "$name_scene" "$wait" "$name" "$ready" ${arguments[@]+"${arguments[@]}"}
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
  -destination "id=$udid" -derivedDataPath "$derived_data" ${only[@]+"${only[@]}"} 2>&1 |
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

# The listing set is renumbered in App Store order, and anything outside it, such as the menu the
# landscape test opens, is removed so the folder holds exactly what to upload.
if [[ -n $order ]]; then
  python3 - "$output" $order <<'PY'
import re, sys
from pathlib import Path
output, names = Path(sys.argv[1]), sys.argv[2:]
taken = {re.sub(r"^\d+-", "", p.stem): p for p in output.glob("*.png")}
missing = [n for n in names if n not in taken]
for stem, path in taken.items():
    if stem not in names:
        path.unlink()
for number, name in enumerate(names, 1):
    if name in taken:
        taken[name].rename(output / f"{number:02d}-{name}.png")
if missing:
    sys.exit("Missing from the listing set: " + ", ".join(missing))
PY
fi

if grep -q "Couldn't seed\|seeding failed" "$log"; then
  echo "Seeding reported problems; see $log." >&2
fi
echo "Screenshots in $output"
exit "$menu_status"
