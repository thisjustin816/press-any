#!/bin/sh
# Builds the Automatic model fixtures with RGBDS 1.0.4: one program, assembled with each fixture's
# text, and rgbfix setting each one's Game Boy Color flag (-c), Super Game Boy flag (-s), old
# licensee (-l) and new licensee (-k). Set RGBDS_HOME to the directory holding rgbasm, rgblink and
# rgbfix (default /opt/tc/rgbds). Output goes to $OUT_DIR (default ./out).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
rgbds=${RGBDS_HOME:-/opt/tc/rgbds}
out=${OUT_DIR:-$here/out}
mkdir -p "$out"
case $("$rgbds/rgbasm" --version) in
  "rgbasm v1.0.4") ;;
  *) echo "expected rgbasm v1.0.4, got $("$rgbds/rgbasm" --version)" >&2; exit 1 ;;
esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# build FILE TITLE LINE1 LINE2 LINE3 [rgbfix flags...]
build() {
  file=$1 title=$2 line1=$3 line2=$4 line3=$5
  shift 5
  # The font is the RGBDS DMG fixture's.
  "$rgbds/rgbasm" -I "$here/../rgbds-dmg" -D "LINE1=\"$line1\"" -D "LINE2=\"$line2\"" -D "LINE3=\"$line3\"" \
    -o "$tmp/main.o" "$here/main.asm"
  "$rgbds/rgblink" -p 0xFF -o "$out/$file" "$tmp/main.o"
  "$rgbds/rgbfix" -v -p 0xFF -t "$title" "$@" "$out/$file"
}

build sgb-packets.gb "SGB PACKETS" "SGB PACKETS" "SGB 03  LICENSEE 33" "PALETTE AND BORDER" -s -l 0x33
build header-sgb-cgb.gbc "SGB AND CGB" "SGB AND CGB" "CGB 80 SGB 03 LIC 33" "COLOR AND SGB FLAGS" -c -s -l 0x33
build header-sgb-licensee-00.gb "SGB LICENSEE 00" "SGB LICENSEE 00" "SGB 03  LICENSEE 00" "SGB FLAG IGNORED" -s -l 0x00
build header-licensee-01.gb "LICENSEE 01" "LICENSEE 01" "OLD LICENSEE 01" "NINTENDO" -l 0x01
build header-licensee-33-01.gb "LICENSEE 33 01" "LICENSEE 33 01" "OLD 33  NEW 01" "NINTENDO" -l 0x33 -k 01
build header-sgb-licensee-33-01.gb "SGB NINTENDO" "SGB NINTENDO" "SGB 03 OLD 33 NEW 01" "SGB AND NINTENDO" -s -l 0x33 -k 01
