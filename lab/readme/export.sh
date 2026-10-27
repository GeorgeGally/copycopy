#!/bin/bash
# README pictures, shot the same way as the Still hero: one CSS pixel
# per point, Chrome at 2x, sRGB.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
OUT="$REPO/docs/screenshots"
CHROME="${CHROME:-google-chrome}"
mkdir -p "$OUT"

shoot() {
  local w="$1" h="$2" dest="$3" url="$4"
  local profile
  profile="$(mktemp -d)"
  timeout --signal=KILL 20 \
    "$CHROME" --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage \
      --hide-scrollbars --no-first-run --disable-extensions \
      --force-device-scale-factor=2 \
      --force-color-profile=srgb \
      --use-gl=angle --use-angle=swiftshader \
      --window-size="${w},${h}" \
      --user-data-dir="$profile" \
      --screenshot="$dest" \
      "$url" >/tmp/roger-readme-shot.log 2>&1 || true
  rm -rf "$profile"
  if [[ ! -s "$dest" ]]; then
    echo "failed: $dest" >&2
    cat /tmp/roger-readme-shot.log >&2 || true
    return 1
  fi
}

# docs/screenshots/bezel.png is the capture already on main. This only
# refreshes the menu, which is the picture the README adds under Use.
shoot 800 460 "$OUT/menu.png" "file://$ROOT/shots.html?shot=menu"

python3 - "$OUT" << 'PY'
import struct, sys
from pathlib import Path

expected = {"menu.png": (1600, 920)}
out = Path(sys.argv[1])
bad = False
for name, size in expected.items():
    path = out / name
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        print(f"{name} is not a png")
        bad = True
        continue
    got = struct.unpack(">II", data[16:24])
    mark = "ok" if got == size else "WRONG"
    if mark != "ok":
        bad = True
    print(f"{name}: {got[0]}x{got[1]} {mark}")

# The paper is flat. A shadow on the stage itself darkens the corners.
from PIL import Image
paper = (228, 223, 214)
for name in expected:
    im = Image.open(out / name).convert("RGB")
    w, h = im.size
    for pt in ((0, 0), (10, 10), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (10, h - 11)):
        px = im.getpixel(pt)
        if max(abs(a - b) for a, b in zip(px, paper)) > 2:
            print(f"{name} corner {pt} is {px}, expected paper")
            bad = True
if bad:
    raise SystemExit("shot size mismatch")
PY
