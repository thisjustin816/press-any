#!/usr/bin/env bash
# Build zgb-dmg.gb with the ZGB engine and GBDK-2020 found via env vars.
#   ZGB_PATH   ZGB checkout (default /opt/tc/zgb) or its common/ dir
#   GBDK_HOME  GBDK-2020 4.1.x install (default /opt/tc/g411/gbdk/; 4.5.0 fails, see NOTICE)
#   BUILD_DIR  scratch tree (default /opt/w/build/zgb-dmg)
#   OUT_DIR    where zgb-dmg.gb is copied (default /opt/w/out)
# The project is copied to BUILD_DIR so no build output lands in the source tree.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZGB_PATH="${ZGB_PATH:-/opt/tc/zgb}"
[ -d "$ZGB_PATH/common/src" ] && ZGB_PATH="$ZGB_PATH/common"   # ZGB_PATH must point at <zgb>/common
export GBDK_HOME="${GBDK_HOME:-/opt/tc/g411/gbdk/}"
BUILD_DIR="${BUILD_DIR:-/opt/w/build/zgb-dmg}"
OUT_DIR="${OUT_DIR:-/opt/w/out}"
[ -f "$ZGB_PATH/src/MakefileCommon" ] || { echo "bad ZGB_PATH: $ZGB_PATH" >&2; exit 1; }
[ -x "$GBDK_HOME/bin/sdcc" ] || { echo "bad GBDK_HOME: $GBDK_HOME" >&2; exit 1; }

rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR" "$OUT_DIR"
cp -r "$SRC/src" "$SRC/include" "$SRC/res" "$BUILD_DIR/"

# MakefileCommon hard-codes GBDK_HOME/PATH for ZGB's Windows env\ layout and
# uses sh-specific "echo -e", and calls the Windows-only romview; command-line values override those.
make -C "$BUILD_DIR/src" build_gb \
  ZGB_PATH="$ZGB_PATH" GBDK_HOME="$GBDK_HOME" \
  PATH="$GBDK_HOME/bin:$PATH" SHELL=/bin/bash ROMVIEW=true
cp "$BUILD_DIR/bin/zgb-dmg.gb" "$OUT_DIR/zgb-dmg.gb"
ls -l "$OUT_DIR/zgb-dmg.gb"
