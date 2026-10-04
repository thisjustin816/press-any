#!/bin/sh
# Builds gbdk450-badsum.gb with GBDK-2020 4.5.0. Set GBDK_450 to the toolchain root (keep the path short:
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
"${gbdk}/bin/lcc"  -Wm-yn"BAD CHECKSUM" -o "$out/gbdk450-badsum.gb" main.c
# Corrupt the header checksum at 0x14D on purpose: flip every bit of the correct value.
python3 - "$out/gbdk450-badsum.gb" <<'PY'
import sys
path = sys.argv[1]
rom = bytearray(open(path, "rb").read())
good = 0
for b in rom[0x134:0x14D]:
    good = (good - b - 1) & 0xFF
assert rom[0x14D] == good, "unexpected checksum before corruption"
rom[0x14D] = good ^ 0xFF
open(path, "wb").write(rom)
PY
