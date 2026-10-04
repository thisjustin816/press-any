#!/bin/sh
# Rebuilds every ROM and patch from source, then writes manifest.json and SHA256SUMS.
# Toolchains are not part of this package; point these at pinned installs (see README.md):
#   GBDK_450      GBDK-2020 4.5.0 root           (default /opt/gbdk)
#   GBDK_406      GBDK-2020 4.0.6 root           (default /opt/tc/gbdk406)
#   GBDK_411      GBDK-2020 4.1.1 root, for ZGB  (default /opt/tc/g411/gbdk)
#   RGBDS_HOME    directory with RGBDS 1.0.4 binaries (default /opt/tc/rgbds)
#   ZGB_PATH      ZGB v2023.0 checkout           (default /opt/tc/zgb)
#   GBSTUDIO_CLI  gb-studio-cli built from GB Studio v4.3.2 (default gb-studio-cli)
# Keep this directory on a short path: GBDK-2020 4.5.0 aborts on long paths.
set -eu
ROOT=$(cd "$(dirname "$0")" && pwd)
export PYTHONDONTWRITEBYTECODE=1
export GBDK_450=${GBDK_450:-/opt/gbdk}
export GBDK_406=${GBDK_406:-/opt/tc/gbdk406}
export RGBDS_HOME=${RGBDS_HOME:-/opt/tc/rgbds}
export GBSTUDIO_CLI=${GBSTUDIO_CLI:-gb-studio-cli}
GBDK_411=${GBDK_411:-/opt/tc/g411/gbdk}
ZGB_PATH=${ZGB_PATH:-/opt/tc/zgb}

rm -rf "$ROOT/roms" "$ROOT/patches" "$ROOT/manifest.json" "$ROOT/SHA256SUMS"
mkdir -p "$ROOT/roms" "$ROOT/patches"
export OUT_DIR="$ROOT/roms"

for rom in gbdk450-dmg gbdk406-dmg gbdk450-gbc gbdk450-dual mbc5-battery rev-pair bad-checksum \
           rgbds-dmg rgbds-gbc hugedriver-dmg gbstudio-dmg gbstudio-gbc; do
  echo "== $rom"
  sh "$ROOT/src/$rom/build.sh"
done

echo "== zgb-dmg"
zgb_tmp=$(mktemp -d)
BUILD_DIR="$zgb_tmp" GBDK_HOME="$GBDK_411/" ZGB_PATH="$ZGB_PATH" bash "$ROOT/src/zgb-dmg/build.sh"
rm -rf "$zgb_tmp"

echo "== patches"
ROM_DIR="$ROOT/roms" PATCH_DIR="$ROOT/patches" sh "$ROOT/src/patch-tools/build.sh"

echo "== manifest"
python3 "$ROOT/src/release-tools/make_manifest.py" "$ROOT"
