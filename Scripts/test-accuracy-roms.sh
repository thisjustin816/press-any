#!/usr/bin/env bash
# Runs community accuracy test ROMs through SameBoyBridge, the way the app runs a game, and
# compares each result with Scripts/tests/accuracy-expected.txt. SameBoy already passes these
# suites upstream; this catches Press Any's own setup (models, boot ROMs, the bridge) changing a
# result, and shows what a SameBoy update changes. The suites are fetched at pinned commits and
# built here, never committed.
#
# usage: Scripts/test-accuracy-roms.sh [--update]
#   --update  rewrite the expected results instead of comparing with them
#
# Needs git, a C compiler, cmake and make for wla-dx, and RGBDS for the boot ROMs when
# Packages/EmulatorKit/Sources/SameBoyAdapter/Resources/BootROMs has none. TEST_ROMS_DIR keeps the
# fetched suites between runs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/Scripts/lib/sameboy-source.sh"
SAMEBOY="$(resolve_sameboy_root "$ROOT_DIR")" || {
  echo "SameBoy source not found. Run: git submodule update --init" >&2
  exit 1
}
BRIDGE="$ROOT_DIR/Packages/EmulatorKit/Sources/SameBoyBridge"
BOOT_ROMS="$ROOT_DIR/Packages/EmulatorKit/Sources/SameBoyAdapter/Resources/BootROMs"
EXPECTED="$ROOT_DIR/Scripts/tests/accuracy-expected.txt"
CACHE="${TEST_ROMS_DIR:-${TMPDIR:-/tmp}/press-any-test-roms}"
BUILD="${TMPDIR:-/tmp}/press-any-accuracy-build"
CC="${CC:-cc}"

# The commits game-boy-test-roms v7.0 builds (github.com/c-sp/game-boy-test-roms, src/assemble.sh).
BLARGG_COMMIT=c240dd7d700e5c0b00a7bbba52b53e4ee67b5f15
WLA_DX_COMMIT=89a90a56be5c2b8cf19a9afa3e1b32384ddb1a97
MOONEYE_COMMIT=443f6e1f2a8d83ad9da051cbb960311c5aaaea66

fetch() {
  local dir="$CACHE/$1" url="$2" commit="$3"
  if [[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" == "$commit" ]]; then return; fi
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" fetch -q --depth 1 "$url" "$commit"
  git -C "$dir" checkout -q FETCH_HEAD
}

fetch blargg https://github.com/retrio/gb-test-roms "$BLARGG_COMMIT"
fetch wla-dx https://github.com/vhelin/wla-dx "$WLA_DX_COMMIT"
fetch mooneye https://github.com/Gekkio/mooneye-test-suite "$MOONEYE_COMMIT"

if [[ ! -x "$CACHE/wla-dx/binaries/wla-gb" ]]; then
  (cd "$CACHE/wla-dx" && cmake . >/dev/null && make wla-gb wlalink >/dev/null)
fi
if [[ ! -f "$CACHE/mooneye/build/acceptance/add_sp_e_timing.gb" ]]; then
  PATH="$CACHE/wla-dx/binaries:$PATH" make -C "$CACHE/mooneye" all >/dev/null
fi
if [[ ! -f "$BOOT_ROMS/dmg_boot.bin" || ! -f "$BOOT_ROMS/cgb_boot.bin" ]]; then
  "$ROOT_DIR/Scripts/generate-sameboy-bootroms.sh"
fi

rm -rf "$BUILD"
mkdir -p "$BUILD/obj"
objects=()
while IFS= read -r source; do
  object="$BUILD/obj/$(basename "${source%.c}").o"
  "$CC" -std=gnu11 -D_GNU_SOURCE -DGB_INTERNAL -DGB_VERSION='"1.0.3"' -DGB_COPYRIGHT_YEAR='"2026"' \
    -O2 -I"$SAMEBOY" -I"$SAMEBOY/Core" -c "$source" -o "$object"
  objects+=("$object")
done < <(find "$SAMEBOY/Core" -maxdepth 1 -name '*.c' -print | sort)
"$CC" -std=gnu11 -D_GNU_SOURCE -DGB_INTERNAL -DGB_VERSION='"1.0.3"' -DGB_COPYRIGHT_YEAR='"2026"' -O2 \
  -I"$SAMEBOY" -I"$SAMEBOY/Core" -I"$BRIDGE/include" \
  "$BRIDGE/SameBoyBridge.c" "$ROOT_DIR/Scripts/tests/sameboy_test_roms.c" "${objects[@]}" -lm -o "$BUILD/run"

# One line per run: model, mode, emulated seconds (with the boot ROM's few), ROM relative to $CACHE.
{
  # Blargg's run times come from game-boy-test-roms' blargg.md. halt_bug, interrupt_time and the
  # sound tests report only on screen, so they wait for a screenshot check.
  for model in dmg cgb; do
    [[ $model == dmg ]] && cpu=58 || cpu=34
    echo "$model blargg $cpu blargg/cpu_instrs/cpu_instrs.gb"
    echo "$model blargg 4 blargg/instr_timing/instr_timing.gb"
    echo "$model blargg 6 blargg/mem_timing/mem_timing.gb"
    echo "$model blargg 7 blargg/mem_timing-2/mem_timing.gb"
  done
  echo "dmg blargg 24 blargg/oam_bug/oam_bug.gb"
  # The Mooneye tests that report a result, on both models. A test written for other hardware
  # (the -dmg0, -mgb, -sgb and -cgb suffixes) is expected to fail, and the expected results
  # record that.
  (cd "$CACHE" && find mooneye/build/acceptance mooneye/build/emulator-only mooneye/build/misc -name '*.gb' | sort) |
    while read -r rom; do
      echo "dmg mooneye 123 $rom"
      echo "cgb mooneye 123 $rom"
    done
} > "$BUILD/runs.txt"

run_one() {
  local model="$1" mode="$2" seconds="$3" rom="$4" boot
  [[ $model == dmg ]] && boot="$BOOT_ROMS/dmg_boot.bin" || boot="$BOOT_ROMS/cgb_boot.bin"
  # SameBoy logs some test ROMs' odd hardware use to stdout; the harness's verdict is the last line.
  echo "$model $rom: $("$BUILD/run" "$model" "$boot" "$mode" "$seconds" "$CACHE/$rom" | tail -n 1)"
}
export -f run_one
export BUILD BOOT_ROMS CACHE
xargs -P "$(getconf _NPROCESSORS_ONLN)" -L 1 bash -c 'run_one "$@"' _ < "$BUILD/runs.txt" | sort > "$BUILD/results.txt"

passed=$(grep -c ': pass$' "$BUILD/results.txt" || true)
total=$(wc -l < "$BUILD/results.txt")
echo "$passed of $total test ROM runs pass."

if [[ "${1:-}" == "--update" ]]; then
  cp "$BUILD/results.txt" "$EXPECTED"
  echo "Updated $EXPECTED"
elif ! diff -u "$EXPECTED" "$BUILD/results.txt"; then
  echo "Test ROM results changed. If the change is intended, as with a SameBoy update, run" >&2
  echo "Scripts/test-accuracy-roms.sh --update and commit the expected results with it." >&2
  exit 1
fi
