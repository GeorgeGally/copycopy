#!/bin/bash
# Retakes docs/screenshots/bezel.png and menu.png with the roger-shot dev tool.
# Usage: scripts/screenshots.sh <photo.png>
# The photo is recorded into a throwaway history as the image item. Both
# pictures are read from the window server at the display's scale, so run
# this on a Retina display for 2x output. roger-shot needs Screen Recording
# for the terminal it runs from; Roger.app itself never does.
set -euo pipefail

ROGER_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
ROGER_PHOTO="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
ROGER_OUT="$ROGER_ROOT/docs/screenshots"

"$ROGER_ROOT/scripts/swift-package.sh" build -c release --product roger-shot
ROGER_SHOT="$("$ROGER_ROOT/scripts/swift-package.sh" build -c release --product roger-shot --show-bin-path)/roger-shot"
for shot in bezel menu; do
    "$ROGER_SHOT" "$shot" --out "$ROGER_OUT/$shot.png" --photo "$ROGER_PHOTO" --icon "$ROGER_ROOT/Resources/MenuBarIcon.png"
    # The window server's PNG encoder is quick, not small; repack losslessly.
    if command -v magick >/dev/null; then
        magick "$ROGER_OUT/$shot.png" -strip -define png:compression-level=9 -define png:compression-filter=5 "$ROGER_OUT/$shot.png"
    fi
    printf '%s: %s\n' "$shot" "$(sips -g pixelWidth -g pixelHeight "$ROGER_OUT/$shot.png" | awk '/pixel/{printf "%s ", $2}')"
done
