#!/bin/bash
# Exports one PNG per treatment from lab/shot-lab.html, plus a composite of the
# whole page for review. Each image is shot at 2x, so every file is 1600 wide.
# Usage: lab/export.sh [composite-dir]
set -euo pipefail

ROGER_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
OUT="$ROGER_ROOT/docs/screenshots/presentations"
COMPOSITE_DIR="${1:-}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PROFILE="$(mktemp -d)"
trap 'rm -rf "$PROFILE"' EXIT

mkdir -p "$OUT"

shoot() {
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
        --user-data-dir="$PROFILE" --force-device-scale-factor="$1" \
        --window-size="$2" --screenshot="$3" "$4" 2>/dev/null
}

for pair in v1:v1-studio v2:v2-over-the-work v3:v3-depth v4:v4-dark-stage v5:v5-type-led; do
    id="${pair%%:*}"; name="${pair##*:}"
    shoot 2 800,400 "$OUT/$name.png" "file://$ROGER_ROOT/lab/shot-lab.html?shot=$id"
    printf '%s\n' "$(magick identify -format "%f %wx%h" "$OUT/$name.png")"
done

if [ -n "$COMPOSITE_DIR" ]; then
    mkdir -p "$COMPOSITE_DIR"
    shoot 1 820,4200 "$COMPOSITE_DIR/composite.png" "file://$ROGER_ROOT/lab/shot-lab.html"
    magick "$COMPOSITE_DIR/composite.png" -fuzz 2% -trim +repage \
        -bordercolor '#FBFBFA' -border 40 "$COMPOSITE_DIR/composite.png"
    printf '%s\n' "$(magick identify -format "%f %wx%h" "$COMPOSITE_DIR/composite.png")"
fi
