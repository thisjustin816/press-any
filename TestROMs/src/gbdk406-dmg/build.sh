#!/bin/sh
# Builds gbdk406-dmg.gb with GBDK-2020 4.0.6. Set GBDK_406 to the toolchain root (keep the path short:
# GBDK-2020 4.5.0 aborts on long paths). Output goes to $OUT_DIR (default ./out).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
gbdk=${GBDK_406:-/opt/tc/gbdk406}
gbdk=${gbdk%/}
out=${OUT_DIR:-$here/out}
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$here/main.c" "$here/config.h" "$tmp/"
cd "$tmp"
"${gbdk}/bin/lcc"  -Wm-yn"GBDK406 DMG" -o "$out/gbdk406-dmg.gb" main.c
