#!/usr/bin/env python3
"""Build Roger's icons from Resources/AppIcon-source.png.

The source is the bow tie on its off-white rounded square, with a white
margin. The app icon crops to that square, scales it onto Apple's 1024
grid (the long side at 824, the rest transparent) and packs every size
into AppIcon.icns. The menu-bar images are the same bow tie, black on
clear, at 18 pt and 18 pt @2x, so AppKit can tint them as a template.

Usage: python3 scripts/make-icon.py [output-dir]
"""

import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Resources" / "AppIcon-source.png"
CANVAS = 1024
ICON_EXTENT = 824  # Apple's macOS icon grid: 100 pt of margin on a square tile

# Pixel sizes iconutil would emit. ic11/ic12/ic13/ic14 repeat a size as the
# @2x representation of a smaller point size; macOS looks them up by type.
ICON_TYPES = (
    (b"icp4", 16),
    (b"icp5", 32),
    (b"icp6", 64),
    (b"ic07", 128),
    (b"ic08", 256),
    (b"ic09", 512),
    (b"ic10", 1024),
    (b"ic11", 32),
    (b"ic12", 64),
    (b"ic13", 256),
    (b"ic14", 512),
)


def main_component(inside: np.ndarray) -> np.ndarray:
    """The connected region of `inside` that holds the middle of that mask."""
    h, w = inside.shape
    ys, xs = np.where(inside)
    if len(xs) == 0:
        raise SystemExit("make-icon: the source has no icon to trace")
    y, x = int(ys[len(ys) // 2]), int(xs[len(xs) // 2])
    seen = np.zeros((h, w), dtype=bool)
    stack = [(y, x)]
    seen[y, x] = True
    while stack:
        y, x = stack.pop()
        x0 = x
        while x0 > 0 and inside[y, x0 - 1] and not seen[y, x0 - 1]:
            x0 -= 1
        x1 = x
        while x1 < w - 1 and inside[y, x1 + 1] and not seen[y, x1 + 1]:
            x1 += 1
        seen[y, x0 : x1 + 1] = True
        for xx in range(x0, x1 + 1):
            if y > 0 and inside[y - 1, xx] and not seen[y - 1, xx]:
                seen[y - 1, xx] = True
                stack.append((y - 1, xx))
            if y < h - 1 and inside[y + 1, xx] and not seen[y + 1, xx]:
                seen[y + 1, xx] = True
                stack.append((y + 1, xx))
    return seen


def app_icon(src: np.ndarray) -> Image.Image:
    """The rounded square, centred on a transparent 1024 canvas."""
    # The plate sits a few levels under white; the margin is white. A hard
    # mask keeps that white out, and the downsample supplies the edge.
    inside = main_component(src.min(axis=2) <= 250)
    ys, xs = np.where(inside)
    y0, y1 = int(ys.min()), int(ys.max())
    x0, x1 = int(xs.min()), int(xs.max())
    crop = src[y0 : y1 + 1, x0 : x1 + 1]
    mask = inside[y0 : y1 + 1, x0 : x1 + 1]
    rgba = np.zeros(crop.shape[:2] + (4,), np.float32)
    rgba[..., :3] = crop
    rgba[..., 3] = mask.astype(np.float32) * 255
    rgba[..., :3] *= rgba[..., 3:] / 255

    h, w = mask.shape
    scale = ICON_EXTENT / max(w, h)
    size = (max(1, round(w * scale)), max(1, round(h * scale)))
    resized = Image.fromarray(rgba.astype(np.uint8), "RGBA").resize(size, Image.Resampling.BOX)
    straight = unpremultiply(np.asarray(resized).astype(np.float32))

    master = np.zeros((CANVAS, CANVAS, 4), np.uint8)
    x = (CANVAS - size[0]) // 2
    y = (CANVAS - size[1]) // 2
    master[y : y + size[1], x : x + size[0]] = straight
    if master[0, 0, 3] != 0 or master[-1, -1, 3] != 0:
        raise SystemExit("make-icon: app icon corners should be transparent")
    if master[CANVAS // 2, CANVAS // 2, 3] != 255:
        raise SystemExit("make-icon: app icon centre should be opaque")
    return Image.fromarray(master, "RGBA")


def unpremultiply(arr: np.ndarray) -> np.ndarray:
    out = arr.copy()
    alpha = out[..., 3:4]
    painted = alpha > 0
    out[..., :3] = np.where(painted, np.clip(out[..., :3] / np.maximum(alpha, 1) * 255, 0, 255), 0)
    return out.astype(np.uint8)


def downsample(master: Image.Image, pixels: int) -> Image.Image:
    if pixels == CANVAS:
        return master
    arr = np.asarray(master).astype(np.float32)
    arr[..., :3] *= arr[..., 3:] / 255
    small = Image.fromarray(arr.astype(np.uint8), "RGBA").resize((pixels, pixels), Image.Resampling.BOX)
    return Image.fromarray(unpremultiply(np.asarray(small).astype(np.float32)), "RGBA")


def png_bytes(image: Image.Image) -> bytes:
    import io
    buf = io.BytesIO()
    image.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def pack_icns(images: list[tuple[bytes, Image.Image]]) -> bytes:
    chunks = []
    for kind, image in images:
        data = png_bytes(image)
        chunks.append(kind + struct.pack(">I", 8 + len(data)) + data)
    body = b"".join(chunks)
    return b"icns" + struct.pack(">I", 8 + len(body)) + body


def bowtie_mask(src: np.ndarray) -> np.ndarray:
    """Both wings. The plate is light, so the mark is whatever is dark."""
    dark = src.sum(axis=2) < 400
    if dark.sum() < 1000:
        raise SystemExit("make-icon: no bow tie in the source")
    return dark


def menu_bar_icon(mask: np.ndarray, pixels: int) -> Image.Image:
    """Black bow tie at `pixels` (18 pt, or that many device pixels).

    The wings are scaled together. At 18 px the true gap would close, so
    the gap is held open just enough to stay a clear slot.
    """
    ys, xs = np.where(mask)
    split = int(round(xs.mean()))
    wings = []
    for side in (mask[:, :split], mask[:, split:]):
        yy, xx = np.where(side)
        if len(xx) == 0:
            raise SystemExit("make-icon: bow tie is missing a wing")
        wings.append(side[yy.min() : yy.max() + 1, xx.min() : xx.max() + 1])
    left, right = wings
    total_h = max(left.shape[0], right.shape[0])
    total_w = int(xs.max() - xs.min() + 1)

    scale = pixels / total_w
    wing_w = max(1, round(left.shape[1] * scale))
    height = max(1, round(total_h * scale))
    gap = pixels - 2 * wing_w
    # A sub-pixel gap fills in. Keep two clear pixels, and give the wings
    # the rest so the silhouette stays as wide as the point size allows.
    if gap < 2:
        gap = 2
        scale = (pixels - gap) / (left.shape[1] + right.shape[1])
        wing_w = max(1, round(left.shape[1] * scale))
        height = max(1, round(total_h * scale))
        while 2 * wing_w + gap > pixels and wing_w > 1:
            wing_w -= 1
    gap = pixels - 2 * wing_w

    def wing_image(wing: np.ndarray) -> Image.Image:
        gray = Image.fromarray(wing.astype(np.uint8) * 255, "L")
        return gray.resize((wing_w, height), Image.Resampling.BOX)

    icon = Image.new("RGBA", (pixels, pixels), (0, 0, 0, 0))
    top = (pixels - height) // 2
    for image, x in ((wing_image(left), 0), (wing_image(right), pixels - wing_w)):
        alpha = image
        black = Image.merge(
            "RGBA",
            (
                Image.new("L", image.size, 0),
                Image.new("L", image.size, 0),
                Image.new("L", image.size, 0),
                alpha,
            ),
        )
        icon.paste(black, (x, top))
    # The slot between the wings must read as a gap, not a grey bridge.
    alpha = np.asarray(icon)[:, pixels // 2 - 1 : pixels // 2 + 1, 3]
    if alpha.max() > 40:
        raise SystemExit("make-icon: menu-bar bow tie wings ran together")
    return icon


def main() -> None:
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Resources"
    output.mkdir(parents=True, exist_ok=True)
    src = np.asarray(Image.open(SOURCE).convert("RGB"))
    master = app_icon(src)
    by_size = {}
    packed = []
    for kind, pixels in ICON_TYPES:
        image = by_size.get(pixels)
        if image is None:
            image = downsample(master, pixels)
            by_size[pixels] = image
        packed.append((kind, image))
    icns = pack_icns(packed)
    (output / "AppIcon.icns").write_bytes(icns)

    mask = bowtie_mask(src)
    menu_bar_icon(mask, 18).save(output / "MenuBarIcon.png")
    menu_bar_icon(mask, 36).save(output / "MenuBarIcon@2x.png")
    print(f"Wrote AppIcon.icns ({len(icns)} bytes), MenuBarIcon.png and MenuBarIcon@2x.png to {output}")


if __name__ == "__main__":
    main()
