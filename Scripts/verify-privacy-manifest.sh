#!/usr/bin/env bash
set -euo pipefail

# Checks the app's privacy manifest, then that the app `make build` produced carries it unchanged.
# The manifest only counts once it is in the bundle, so a lint of the source file isn't enough.
# Needs macOS and Xcode; run after `make build`.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="${PROJECT_NAME:-PressAny}"
destination="${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
manifest="$repo_root/App/PrivacyInfo.xcprivacy"

plutil -lint "$manifest"

settings="$(xcodebuild -project "$repo_root/$project.xcodeproj" -scheme "$project" \
  -destination "$destination" -showBuildSettings 2>/dev/null)"
products="$(awk -F ' = ' '$1 ~ /^ *BUILT_PRODUCTS_DIR$/ { print $2; exit }' <<<"$settings")"
app="$(awk -F ' = ' '$1 ~ /^ *FULL_PRODUCT_NAME$/ { print $2; exit }' <<<"$settings")"
built="$products/$app/PrivacyInfo.xcprivacy"

if [[ ! -f "$built" ]]; then
  echo "The built app has no privacy manifest at $built" >&2
  exit 1
fi
if ! cmp -s <(plutil -convert xml1 -o - "$manifest") <(plutil -convert xml1 -o - "$built"); then
  echo "The built app's privacy manifest differs from App/PrivacyInfo.xcprivacy" >&2
  exit 1
fi
echo "Privacy manifest is valid and in $app. Required reason APIs it declares:"
plutil -extract NSPrivacyAccessedAPITypes json -o - "$built"
echo
