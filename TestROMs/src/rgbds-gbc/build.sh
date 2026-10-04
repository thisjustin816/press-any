#!/bin/sh
# Builds rgbds-gbc.gbc with RGBDS 1.0.4. Set RGBDS_HOME to the directory holding rgbasm, rgblink and
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
"$rgbds/rgbasm" -D GBC=1 -o "$tmp/main.o" main.asm
"$rgbds/rgblink" -p 0xFF -o "$out/rgbds-gbc.gbc" "$tmp/main.o"
"$rgbds/rgbfix" -v -p 0xFF -C -t "RGBDS GBC" "$out/rgbds-gbc.gbc"
