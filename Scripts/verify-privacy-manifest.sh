#!/usr/bin/env bash
set -euo pipefail

# Checks the app's privacy manifest, then that a built app carries it unchanged. The manifest only
# counts once it is in the bundle, so a lint of the source file isn't enough. Pass the path of an
# .app, such as the one in an archive; with none, it checks the app `make build` produced.
# Needs macOS and Xcode.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="${PROJECT_NAME:-PressAny}"
destination="${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
manifest="$repo_root/App/PrivacyInfo.xcprivacy"

plutil -lint "$manifest"

if [[ $# -gt 0 ]]; then
  app_path="$1"
else
  settings="$(xcodebuild -project "$repo_root/$project.xcodeproj" -scheme "$project" \
    -destination "$destination" -showBuildSettings 2>/dev/null)"
  products="$(awk -F ' = ' '$1 ~ /^ *BUILT_PRODUCTS_DIR$/ { print $2; exit }' <<<"$settings")"
  app_path="$products/$(awk -F ' = ' '$1 ~ /^ *FULL_PRODUCT_NAME$/ { print $2; exit }' <<<"$settings")"
fi
app="$(basename "$app_path")"
built="$app_path/PrivacyInfo.xcprivacy"

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
