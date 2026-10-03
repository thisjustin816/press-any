#!/usr/bin/env bash
set -euo pipefail

# Check the Swift gbtoolsid port against the C tool at the pinned revision:
# 1. regenerate GBToolsIDData.swift from that revision and require it to match the committed file;
# 2. build gbtoolsid, run it over its own test ROMs and synthetic ROMs, and require the port to
#    produce the same results.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
data="$repo_root/Packages/EmulatorKit/Sources/ToolchainDetection/GB/GBToolsIDData.swift"
commit="$(sed -n 's/^    static let upstreamCommit = "\([0-9a-f]*\)"$/\1/p' "$data")"
if [[ -z "$commit" ]]; then
  echo "Could not read upstreamCommit from $data" >&2
  exit 1
fi

work="${TMPDIR:-/tmp}/gbtoolsid-differential"
rm -rf "$work"
mkdir -p "$work"
git clone --quiet https://github.com/bbbbbr/gbtoolsid.git "$work/gbtoolsid"
git -C "$work/gbtoolsid" checkout --quiet "$commit"
make -C "$work/gbtoolsid" --quiet linux CC="${CC:-cc}"

python3 "$repo_root/Scripts/generate-gbtoolsid-data.py" "$work/gbtoolsid" "$work/GBToolsIDData.swift"
if ! diff -u "$data" "$work/GBToolsIDData.swift"; then
  echo "GBToolsIDData.swift does not match its generator output for $commit." >&2
  exit 1
fi

python3 "$repo_root/Scripts/gbtoolsid-differential-corpus.py" "$work/gbtoolsid" "$work/corpus"
GBTOOLSID_DIFFERENTIAL_CORPUS="$work/corpus" \
  swift test --package-path "$repo_root/Packages/EmulatorKit" --filter GBToolsIDDifferentialTests
