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
  -retry-tests-on-failure -test-iterations 3 \
  -resultBundlePath "$results/share-ui.xcresult" CODE_SIGNING_ALLOWED=NO test \
  2>&1 | tee "$results/share-ui.log"

# A control must fail at its own assertion. The simulator share sheet sometimes stalls before that
# point, so a failure elsewhere is retried; a pass, or three misses, is a real error.
run_control() {
  local test_name="$1" name="$2" assertion="$3"
  local log="$results/$name.log" attempt
  for attempt in 1 2 3; do
    rm -rf "$results/$name.xcresult"
    if xcodebuild -project PressAny.xcodeproj -scheme PressAnyShareTests -configuration Debug \
      -destination "$destination" -derivedDataPath "$derived_data" -parallel-testing-enabled NO \
      -only-testing:"PressAnyShareUITests/SharedFileUITests/$test_name" \
      -resultBundlePath "$results/$name.xcresult" CODE_SIGNING_ALLOWED=NO test \
      > "$log" 2>&1; then
      echo "The $name regression control unexpectedly passed." >&2
      return 1
    fi
    if grep -Eq "Test Case .*$test_name.*failed" "$log" && grep -Fq "$assertion" "$log"; then
      return 0
    fi
    echo "The $name control failed before its assertion (attempt $attempt of 3)." >&2
    tail -n 40 "$log" >&2
  done
  echo "The $name control never failed at the expected assertion: $assertion" >&2
  return 1
}

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

run_control testSharedIPSRefreshesOpenGameDetails refresh-control \
  'the new Build appears without leaving Game Details'
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

run_control testSharedGBCQuickPlayQueuesROMUntilSessionCloses menu-control \
  'opening the game menu pauses the game'
echo "Removing the game-menu pause hook fails the menu's Resume assertion."
