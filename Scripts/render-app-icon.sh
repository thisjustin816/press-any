#!/usr/bin/env bash
set -euo pipefail

# Renders every icon colorway and its settings previews. Requires Chromium and ImageMagick.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
page="$repo_root/Scripts/app-icon/icon.html"
assets="$repo_root/App/Assets.xcassets"
chrome="${CHROME:-$(command -v chromium || command -v google-chrome || echo /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome)}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if command -v magick >/dev/null; then
  image_tool=magick
else
  image_tool=convert
fi

render() {
  local colorway="$1" variant="$2" dom="$work/render.html"
  if ! "$chrome" --headless --no-sandbox --disable-gpu --user-data-dir="$work/chromium" --allow-file-access-from-files \
    --virtual-time-budget=1000 --dump-dom "file://$page?colorway=$colorway#$variant" > "$dom" 2>/dev/null; then
    echo "Chromium could not render the $colorway $variant icon." >&2
    exit 1
  fi
  local data
  data="$(sed -n 's/.*data-png="data:image\/png;base64,\([^"]*\)".*/\1/p' "$dom")"
  if [[ -z "$data" ]]; then
    echo "The $colorway $variant icon did not render; inspect $page in a browser." >&2
    exit 1
  fi
  printf '%s' "$data" | base64 --decode > "$work/$variant.png"
}

for colorway in Default Berry Grape Teal Kiwi Dandelion; do
  icon_name="AppIcon"
  if [[ "$colorway" != Default ]]; then icon_name="AppIcon-$colorway"; fi
  out="$assets/$icon_name.appiconset"
  preview_name="AppIconPreview-$colorway"
  preview="$assets/$preview_name.imageset"
  for variant in light dark tinted; do
    render "$colorway" "$variant"
    suffix=""
    if [[ "$variant" == dark ]]; then suffix="-Dark"; fi
    if [[ "$variant" == tinted ]]; then suffix="-Tinted"; fi
    # App Store icons are opaque. The Tinted artwork keeps a transparent background for iOS.
    if [[ "$variant" == tinted ]]; then
      "$image_tool" "$work/$variant.png" -colorspace Gray "$out/$icon_name$suffix.png"
    else
      "$image_tool" "$work/$variant.png" -alpha off "$out/$icon_name$suffix.png"
      "$image_tool" "$out/$icon_name$suffix.png" -resize 180x180 "$preview/$preview_name$suffix.png"
    fi
  done
  echo "Rendered $colorway icons and previews."
done
