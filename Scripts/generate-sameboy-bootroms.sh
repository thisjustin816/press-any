#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/Scripts/lib/sameboy-source.sh"
SAMEBOY_ROOT="$(resolve_sameboy_root "$ROOT_DIR")" || {
  echo "SameBoy source not found. Run: git submodule update --init" >&2
  exit 1
}
RESOURCE_DIR="$ROOT_DIR/Packages/EmulatorKit/Sources/SameBoyAdapter/Resources/BootROMs"
VERSION="$(sed -n 's/^VERSION := //p' "$SAMEBOY_ROOT/version.mk")"

if [[ "$VERSION" != "1.0.3" ]]; then
  echo "Expected SameBoy 1.0.3, found '$VERSION'" >&2
  exit 1
fi

missing=()
for tool in rgbasm rgblink rgbgfx; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing+=("$tool")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "RGBDS is required to build SameBoy's open boot ROMs. Missing: ${missing[*]}" >&2
  echo "On macOS: brew install rgbds" >&2
  exit 2
fi

# cgb_boot_fast is not part of SameBoy's bootroms target; Quick Play uses it to skip the CGB animation.
make -C "$SAMEBOY_ROOT" bootroms build/bin/BootROMs/cgb_boot_fast.bin CONF=release
mkdir -p "$RESOURCE_DIR"
cp "$SAMEBOY_ROOT/build/bin/BootROMs/dmg_boot.bin" "$RESOURCE_DIR/dmg_boot.bin"
cp "$SAMEBOY_ROOT/build/bin/BootROMs/cgb_boot.bin" "$RESOURCE_DIR/cgb_boot.bin"
cp "$SAMEBOY_ROOT/build/bin/BootROMs/cgb_boot_fast.bin" "$RESOURCE_DIR/cgb_boot_fast.bin"

echo "Generated SameBoy boot ROM resources in $RESOURCE_DIR"
