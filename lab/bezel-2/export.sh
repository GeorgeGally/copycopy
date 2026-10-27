#!/bin/bash
# Shoots lab/bezel-2/frames.html at 2x.
# Hero: 800x400 CSS -> 1600x800.
# Social: the same frame scaled into 640x320 CSS -> 1280x640.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/shots"
CHROME="${CHROME:-google-chrome}"
mkdir -p "$OUT"

shoot() {
  local w="$1" h="$2" dest="$3" url="$4"
  local profile
  profile="$(mktemp -d)"
  # Chrome writes the PNG and then often fails to exit in this environment.
  timeout --signal=KILL 20 \
    "$CHROME" --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage \
      --hide-scrollbars --no-first-run --disable-extensions \
      --force-device-scale-factor=2 \
      --force-color-profile=srgb \
      --use-gl=angle --use-angle=swiftshader \
      --window-size="${w},${h}" \
      --user-data-dir="$profile" \
      --screenshot="$dest" \
      "$url" >/tmp/roger-shot.log 2>&1 || true
  rm -rf "$profile"
  if [[ ! -s "$dest" ]]; then
    echo "failed: $dest" >&2
    cat /tmp/roger-shot.log >&2 || true
    return 1
  fi
}

export -f shoot
export CHROME ROOT OUT

names=(v1:v1-still v2:v2-line v3:v3-face v4:v4-page v5:v5-name)
pids=()
for pair in "${names[@]}"; do
  id="${pair%%:*}"
  name="${pair##*:}"
  (
    shoot 800 400 "$OUT/$name-hero.png" "file://$ROOT/frames.html?shot=$id&frame=hero"
    shoot 640 320 "$OUT/$name-social.png" "file://$ROOT/frames.html?shot=$id&frame=social"
    echo "done $name"
  ) &
  pids+=($!)
done

fail=0
for pid in "${pids[@]}"; do
  wait "$pid" || fail=1
done
if [[ "$fail" -ne 0 ]]; then
  echo "one or more shots failed" >&2
  exit 1
fi

python3 - "$OUT" << 'PY'
import struct, sys
from pathlib import Path

expected = {"hero": (1600, 800), "social": (1280, 640)}

def size(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path.name} is not a png")
    return struct.unpack(">II", data[16:24])

out = Path(sys.argv[1])
bad = False
paths = sorted(out.glob("v*-*.png"))
if len(paths) != 10:
    print(f"expected 10 pngs, found {len(paths)}")
    bad = True
for path in paths:
    w, h = size(path)
    kind = "hero" if path.name.endswith("-hero.png") else "social"
    mark = "ok" if (w, h) == expected[kind] else "WRONG"
    if mark != "ok":
        bad = True
    print(f"{path.name}: {w}x{h} {mark}")
if bad:
    raise SystemExit("shot size mismatch")
PY
