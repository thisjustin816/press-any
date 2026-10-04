#!/bin/sh
# Builds the revision pair ROMs with GBDK-2020 4.5.0. Set GBDK_450 to the toolchain root (keep the path short:
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
"${gbdk}/bin/lcc" -DREV=0  -Wm-yn"REV TEST V1.0" -o "$out/gbdk450-rev-v1.0.gb" main.c
"${gbdk}/bin/lcc" -DREV=1  -Wm-yn"REV TEST V1.1" -o "$out/gbdk450-rev-v1.1.gb" main.c
