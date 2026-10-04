#!/bin/sh
# Builds gbdk450-dmg.gb with GBDK-2020 4.5.0. Set GBDK_450 to the toolchain root (keep the path short:
# GBDK-2020 4.5.0 aborts on long paths). Output goes to $OUT_DIR (default ./out).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
gbdk=${GBDK_450:-/opt/gbdk}
gbdk=${gbdk%/}
out=${OUT_DIR:-$here/out}
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$here/main.c" "$here/config.h" "$tmp/"
cd "$tmp"
"${gbdk}/bin/lcc"  -Wm-yn"GBDK450 DMG" -o "$out/gbdk450-dmg.gb" main.c
