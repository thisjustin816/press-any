#!/bin/sh
# Regenerate assets, then build the ROM with gb-studio-cli (GB Studio 4.3.2).
# Env: GBSTUDIO_CLI (default gb-studio-cli), OUT_DIR (default ./out).
# Build from a short path: GBDK aborts on long paths.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
CLI=${GBSTUDIO_CLI:-gb-studio-cli}
OUT=${OUT_DIR:-$HERE/out}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
python3 "$HERE/make_assets.py"
cd "$HERE"
"$CLI" make:rom project.gbsproj "$OUT/gbstudio-dmg.gb"
