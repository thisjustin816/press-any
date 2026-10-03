#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/Scripts/lib/sameboy-source.sh"
SAMEBOY="$(resolve_sameboy_root "$ROOT_DIR")" || {
  echo "SameBoy source not found. Run: git submodule update --init" >&2
  exit 1
}
BRIDGE="$ROOT_DIR/Packages/EmulatorKit/Sources/SameBoyBridge"
BUILD="${TMPDIR:-/tmp}/sameboy-bridge-linux"

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "This smoke test is intended for Linux; use the XCFramework/Xcode tests on macOS." >&2
  exit 2
fi

rm -rf "$BUILD"
mkdir -p "$BUILD/obj"
objects=()
while IFS= read -r source; do
  object="$BUILD/obj/$(basename "${source%.c}").o"
  clang -std=gnu11 -D_GNU_SOURCE -DGB_INTERNAL \
    -DGB_VERSION='"1.0.3"' -DGB_COPYRIGHT_YEAR='"2026"' \
    -O2 -fPIC -I"$SAMEBOY" -I"$SAMEBOY/Core" \
    -c "$source" -o "$object"
  objects+=("$object")
done < <(find "$SAMEBOY/Core" -maxdepth 1 -name '*.c' -print | sort)

ar rcs "$BUILD/libsameboy.a" "${objects[@]}"
clang -std=gnu11 -D_GNU_SOURCE -DGB_INTERNAL \
  -DGB_VERSION='"1.0.3"' -DGB_COPYRIGHT_YEAR='"2026"' \
  -I"$SAMEBOY" -I"$SAMEBOY/Core" -I"$BRIDGE/include" \
  "$BRIDGE/SameBoyBridge.c" "$ROOT_DIR/Scripts/tests/sameboy_bridge_smoke.c" \
  "$BUILD/libsameboy.a" -lm -o "$BUILD/smoke"
"$BUILD/smoke"
