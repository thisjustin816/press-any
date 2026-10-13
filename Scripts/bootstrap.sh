#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The iOS bootstrap requires macOS/Xcode. Pure Swift/core tests can run with: make test-core" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen 2.46.0+ is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

source "$(dirname "$0")/lib/sameboy-source.sh"
if ! resolve_sameboy_root "$(pwd)" >/dev/null; then
  echo "SameBoy source not found. Run: git submodule update --init" >&2
  exit 1
fi

for name in dmg_boot mgb_boot sgb_boot sgb2_boot cgb_boot cgb_boot_fast agb_boot; do
  if [[ ! -f Packages/EmulatorKit/Sources/SameBoyAdapter/Resources/BootROMs/$name.bin ]]; then
    ./Scripts/generate-sameboy-bootroms.sh
    break
  fi
done

xcodegen generate
