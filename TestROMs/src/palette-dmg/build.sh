#!/bin/sh
# Builds the palette fixture with the test ROM collection's pinned RGBDS 1.0.4.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
rgbds=${RGBDS_HOME:-/opt/tc/rgbds}
out=${OUT_DIR:-$here/out}
mkdir -p "$out"
case $("$rgbds/rgbasm" --version) in
  "rgbasm v1.0.4") ;;
  *) echo "expected rgbasm v1.0.4" >&2; exit 1 ;;
esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"$rgbds/rgbasm" -o "$tmp/main.o" "$here/main.asm"
"$rgbds/rgblink" -p 0xFF -o "$out/palette-dmg.gb" "$tmp/main.o"
"$rgbds/rgbfix" -v -p 0xFF -t "PALETTE DMG" "$out/palette-dmg.gb"
