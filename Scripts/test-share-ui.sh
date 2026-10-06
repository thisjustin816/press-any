#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
device="${DEVICE:-iPhone 17 Pro}"
results="${SHARE_UI_RESULTS:-build/share-ui}"
mkdir -p "$results"
results="$(cd "$results" && pwd)"
derived_data="$results/DerivedData"
rm -rf "$results/share-ui.xcresult" "$results/refresh-control.xcresult" "$results/menu-control.xcresult"
rm -f "$results/refresh-control.log" "$results/menu-control.log"
udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS" in runtime:
        for device in devices:
            if device["name"] == name:
                print(device["udid"])
                sys.exit(0)
sys.exit(f"No available iOS simulator named {name!r}")
' "$device")"
destination="platform=iOS Simulator,id=$udid"

xcodebuild -project PressAny.xcodeproj -scheme ShareTestSender -configuration Debug \
  -destination "$destination" -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO build \
  > "$results/sender-build.log" 2>&1
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$derived_data/Build/Products/Debug-iphonesimulator/ShareTestSender.app"

xcodebuild -project PressAny.xcodeproj -scheme PressAnyShareTests -configuration Debug \
  -destination "$destination" -derivedDataPath "$derived_data" -parallel-testing-enabled NO \
  -resultBundlePath "$results/share-ui.xcresult" CODE_SIGNING_ALLOWED=NO test \
  2>&1 | tee "$results/share-ui.log"

# Prove the refresh assertion detects the reported regression, rather than merely passing the flow.
source_file="App/Library/GameDetailView.swift"
backup="$(mktemp)"
gameplay_source="App/Gameplay/GameplayViewController.swift"
gameplay_backup="$(mktemp)"
cp "$source_file" "$backup"
cp "$gameplay_source" "$gameplay_backup"
trap 'cp "$backup" "$source_file"; cp "$gameplay_backup" "$gameplay_source"; rm -f "$backup" "$gameplay_backup"' EXIT
python3 - "$source_file" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
receiver = '            .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in model.reload() }\n'
if source.count(receiver) != 1:
    sys.exit("Expected exactly one Game Details library-change receiver")
path.write_text(source.replace(receiver, ""))
PY

if xcodebuild -project PressAny.xcodeproj -scheme PressAnyShareTests -configuration Debug \
  -destination "$destination" -derivedDataPath "$derived_data" -parallel-testing-enabled NO \
  -only-testing:PressAnyShareUITests/SharedFileUITests/testSharedIPSRefreshesOpenGameDetails \
  -resultBundlePath "$results/refresh-control.xcresult" CODE_SIGNING_ALLOWED=NO test \
  > "$results/refresh-control.log" 2>&1; then
  echo "Refresh regression control unexpectedly passed without the listener." >&2
  exit 1
fi
if ! grep -Eq "Test Case .*testSharedIPSRefreshesOpenGameDetails.*failed" "$results/refresh-control.log" \
  || ! grep -Fq 'the new Build appears without leaving Game Details' "$results/refresh-control.log"; then
  tail -n 80 "$results/refresh-control.log" >&2
  echo "The regression control did not fail at the expected new-Build assertion." >&2
  exit 1
fi
echo "Shared-file UI scenarios passed; removing the refresh listener fails the new-Build assertion."
cp "$backup" "$source_file"

# The first Quick Play menu opens before any backgrounding; without its pause it must show Pause.
python3 - "$gameplay_source" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
hook = '    func prepareGameMenu() -> [UIMenuElement] {\n        pauseGameplay()\n'
if source.count(hook) != 1:
    sys.exit("Expected exactly one game-menu pause hook")
path.write_text(source.replace(hook, '    func prepareGameMenu() -> [UIMenuElement] {\n'))
PY

if xcodebuild -project PressAny.xcodeproj -scheme PressAnyShareTests -configuration Debug \
  -destination "$destination" -derivedDataPath "$derived_data" -parallel-testing-enabled NO \
  -only-testing:PressAnyShareUITests/SharedFileUITests/testSharedGBCQuickPlayQueuesROMUntilSessionCloses \
  -resultBundlePath "$results/menu-control.xcresult" CODE_SIGNING_ALLOWED=NO test \
  > "$results/menu-control.log" 2>&1; then
  echo "Menu regression control unexpectedly passed without pausing." >&2
  exit 1
fi
if ! grep -Eq "Test Case .*testSharedGBCQuickPlayQueuesROMUntilSessionCloses.*failed" "$results/menu-control.log" \
  || ! grep -Fq 'opening the game menu pauses the game' "$results/menu-control.log"; then
  tail -n 80 "$results/menu-control.log" >&2
  echo "The menu regression control did not fail at the expected pause assertion." >&2
  exit 1
fi
echo "Removing the game-menu pause hook fails the menu's Resume assertion."
