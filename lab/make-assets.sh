#!/bin/bash
# Cuts the pieces lab/shot-lab.html composes, from the captures the app already
# makes. Nothing here redraws or retouches: each piece is a straight crop of a
# real asset, with alpha taken from what the asset already shows.
#
#   popup.png  the bezel, cropped to the card's own edge (1696x732 shot -> card)
#   menu.png   the menu card, same idea
#   mark.png   the bowtie, cut from the app icon with the cream knocked out
#   work.png   a real page of text to sit behind the popup in V2: the project's
#              own README, rendered by Chrome from
#              https://raw.githubusercontent.com/GeorgeGally/roger/main/README.md
#              at 2x, cropped to 1600x1000. Retake with:
#              chrome --headless --screenshot=raw.png --window-size=1000,720 \
#                     --force-device-scale-factor=2 <that url>
#              then pass raw.png as the argument.
#
# Usage: lab/make-assets.sh [path-to-work-capture]
set -euo pipefail

ROGER_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SHOTS="$ROGER_ROOT/docs/screenshots"
OUT="$ROGER_ROOT/lab/assets"
WORK_CAPTURE="${1:-}"

mkdir -p "$OUT"
pack() { magick "$1" -strip -define png:compression-level=9 "$1"; }

# The card sits at 128,112 in the 1696x732 capture and measures 1440x477.
magick "$SHOTS/bezel.png" -crop 1440x477+128+112 +repage "$OUT/popup.png"
pack "$OUT/popup.png"

# The menu card sits at 546,48 and measures 604x612.
magick "$SHOTS/menu.png" -crop 604x612+546+48 +repage "$OUT/menu.png"
pack "$OUT/menu.png"

# The bowtie is the only dark thing on the icon's cream plate: its bbox is
# 245,352 to 1008,898. Invert the grey to get alpha, then paint it one ink.
magick "$ROGER_ROOT/Resources/AppIcon-source.png" -crop 767x551+243+350 +repage \
    -alpha off \( +clone -colorspace gray -negate -level 4%,88% \) \
    -compose CopyOpacity -composite -fill '#121212' -colorize 100 "$OUT/mark.png"
pack "$OUT/mark.png"

if [ -n "$WORK_CAPTURE" ]; then
    magick "$WORK_CAPTURE" -crop 1600x1000+0+300 +repage "$OUT/work.png"
    pack "$OUT/work.png"
fi

for f in popup menu mark work; do
    [ -f "$OUT/$f.png" ] && printf '%s: %s\n' "$f" "$(magick "$OUT/$f.png" -format '%wx%h %b' info:)"
done
