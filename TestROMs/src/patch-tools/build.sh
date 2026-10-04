#!/bin/sh
# Builds patches/gbdk450-rev-v1.0-to-v1.1.{ips,bps} from the two revision ROMs.
# ROM_DIR holds gbdk450-rev-v1.0.gb and gbdk450-rev-v1.1.gb (default ../../roms); output goes to
# $PATCH_DIR (default ./out).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
roms=${ROM_DIR:-$here/../../roms}
out=${PATCH_DIR:-$here/out}
mkdir -p "$out"
python3 "$here/make_patches.py" "$roms/gbdk450-rev-v1.0.gb" "$roms/gbdk450-rev-v1.1.gb" "$out/gbdk450-rev-v1.0-to-v1.1"
