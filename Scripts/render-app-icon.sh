#!/usr/bin/env bash
set -euo pipefail

# Renders the app icon (a Game Boy A button) from Scripts/app-icon/icon.html into the asset
# catalog: the default icon, plus the Dark and Tinted variants iOS 18 uses. Needs a Chromium
# build (set CHROME to its path) and ImageMagick.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
page="$repo_root/Scripts/app-icon/icon.html"
out="$repo_root/App/Assets.xcassets/AppIcon.appiconset"
chrome="${CHROME:-$(command -v chromium || command -v google-chrome || echo /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome)}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

render() {
  "$chrome" --headless --no-sandbox --disable-gpu --virtual-time-budget=1000 --dump-dom "file://$page#$1" 2>/dev/null \
    | grep -o 'data-png="data:image/png;base64,[^"]*' | sed 's/.*base64,//' | base64 --decode > "$work/$1.png" || true
  if [[ ! -s "$work/$1.png" ]]; then
    echo "The $1 icon didn't render; open $page#$1 in a browser to see the script error." >&2
    exit 1
  fi
}

render light
render dark
render tinted
# The App Store rejects an icon with an alpha channel. The Tinted variant keeps its transparent
# background and is brightened, since iOS tints it by brightness.
magick "$work/light.png" -alpha off "$out/AppIcon.png" 2>/dev/null || convert "$work/light.png" -alpha off "$out/AppIcon.png"
magick "$work/dark.png" -alpha off "$out/AppIcon-Dark.png" 2>/dev/null || convert "$work/dark.png" -alpha off "$out/AppIcon-Dark.png"
magick "$work/tinted.png" -colorspace Gray -level 0%,70% "$out/AppIcon-Tinted.png" 2>/dev/null \
  || convert "$work/tinted.png" -colorspace Gray -level 0%,70% "$out/AppIcon-Tinted.png"
echo "Rendered the app icon into $out."
