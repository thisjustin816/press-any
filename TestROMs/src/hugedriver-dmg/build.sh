#!/bin/sh
# Builds hugedriver-dmg.gb with RGBDS 1.0.4. Set RGBDS_HOME to the directory holding rgbasm, rgblink and
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
cd "$here"
# hUGEDriver is not kept in this repository; fetch it at the pinned commit and check each hash.
commit=a3cbd0cea48e6784d7f625066d0300f7cb075926
fetch() { # <upstream path> <local path> <sha256>
  [ -f "$2" ] || { mkdir -p "$(dirname "$2")"; curl -sSf -o "$2" "https://raw.githubusercontent.com/untoxa/hUGEDriver/$commit/$1"; }
  echo "$3  $2" | sha256sum -c - >/dev/null || { echo "$2 does not match the pinned hUGEDriver" >&2; exit 1; }
}
fetch hUGEDriver.asm hUGEDriver.asm 16870fd80f764e9d64aa098d5a7ebdc5d5d48033ca080a121a7d11c3e2e01d56
fetch include/hUGE.inc include/hUGE.inc fc9c768337328ffaf518beaa7cee0e212db6fcd12bfe2fca7df254213a6e77cd
fetch include/hUGE_note_table.inc include/hUGE_note_table.inc 624d1364facea8e5deea26b15eff3f625ed19f22a3bae322790dc2bdac55099c
fetch include/hardware.inc include/hardware.inc e8d1a7361da65adb3281186ef44c85b30758de8ec3611bbdcf994025ec8b0f9f
fetch rgbds_example/sample_song.asm sample_song.asm 15469590783477aadbec15d75153ba7939f511a7e4bc3ae088a08bb32928c979
"$rgbds/rgbasm" -o "$tmp/main.o" main.asm
"$rgbds/rgbasm" -o "$tmp/driver.o" hUGEDriver.asm
"$rgbds/rgbasm" -o "$tmp/song.o" sample_song.asm
"$rgbds/rgblink" -p 0xFF -o "$out/hugedriver-dmg.gb" "$tmp/main.o" "$tmp/driver.o" "$tmp/song.o"
"$rgbds/rgbfix" -v -p 0xFF -t "HUGEDRIVER" "$out/hugedriver-dmg.gb"
