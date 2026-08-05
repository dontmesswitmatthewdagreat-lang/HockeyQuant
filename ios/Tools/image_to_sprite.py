#!/usr/bin/env python3
"""Turn an image into a TeamSprite grid.

    python3 ios/Tools/image_to_sprite.py art/bear.png BOS [--size 24] [--invert]

Prints the Swift rows for TeamSprite.swift and writes a preview PNG so you can
check the downsample before pasting. Feed it original artwork — a bear, a
flame, a shark — not a club's logo: pixelating a mark doesn't make it a new
work, and the crest system exists precisely so the app ships nothing traced
from NHL artwork.

The image should be a single subject on a flat background, ideally already
square-ish. Background is detected from the border, so leave a clear margin.
Output symbols follow TeamSprite: '.' transparent, 'X' body, 'L' highlight,
'D' shadow. 'E' (cut through to the disc color) is left for you to place by
hand — it's usually one or two pixels for an eye.
"""
import os
import sys
from collections import Counter

from PIL import Image

SYMS = ".XLD"


def load(path, size):
    img = Image.open(path).convert("RGBA")
    # Flatten onto the detected background so alpha and flat-color backgrounds
    # behave identically downstream.
    bg = border_color(img)
    flat = Image.new("RGBA", img.size, bg)
    flat.alpha_composite(img)
    img = flat.convert("RGB")

    box = content_box(img, bg[:3])
    if box:
        img = img.crop(box)
    # Pad to square so the subject isn't stretched by the resize.
    w, h = img.size
    side = max(w, h)
    square = Image.new("RGB", (side, side), bg[:3])
    square.paste(img, ((side - w) // 2, (side - h) // 2))
    return square.resize((size, size), Image.BOX), bg[:3]


def border_color(img):
    w, h = img.size
    px = img.load()
    edge = Counter()
    for x in range(w):
        edge[px[x, 0]] += 1
        edge[px[x, h - 1]] += 1
    for y in range(h):
        edge[px[0, y]] += 1
        edge[px[w - 1, y]] += 1
    return edge.most_common(1)[0][0]


def near(a, b, tol=40):
    return sum(abs(a[i] - b[i]) for i in range(3)) <= tol


def content_box(img, bg):
    w, h = img.size
    px = img.load()
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            if not near(px[x, y], bg):
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    pad = 1
    return (max(0, min(xs) - pad), max(0, min(ys) - pad),
            min(w, max(xs) + 1 + pad), min(h, max(ys) + 1 + pad))


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def to_grid(img, bg, invert):
    size = img.size[0]
    px = img.load()
    subject = [px[x, y] for y in range(size) for x in range(size)
               if not near(px[x, y], bg, 60)]
    if not subject:
        sys.exit("no subject found — is the background flat and the margin clear?")

    # Anchor the mid-tone on the subject's dominant color rather than on a
    # luminance percentile: the body is most of the art, so a percentile span
    # puts the whole body at one end and everything reads as shadow.
    body = Counter(subject).most_common(1)[0][0]
    base = lum(body)
    spread = max(24.0, max(abs(lum(c) - base) for c in subject) * 0.55)

    rows = []
    for y in range(size):
        row = ""
        for x in range(size):
            c = px[x, y]
            if near(c, bg, 60):
                row += "."
                continue
            d = (lum(c) - base) / spread
            if invert:
                d = -d
            row += "L" if d > 0.5 else ("D" if d < -0.5 else "X")
        rows.append(row)
    return rows


def preview(rows, path, cell=10):
    size = len(rows) * cell
    img = Image.new("RGB", (size, size), (245, 245, 248))
    px = img.load()
    tone = {"X": (40, 40, 48), "L": (150, 150, 160), "D": (10, 10, 14)}
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch == ".":
                continue
            for dy in range(cell):
                for dx in range(cell):
                    px[c * cell + dx, r * cell + dy] = tone[ch]
    img.save(path)
    return path


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 2:
        sys.exit(__doc__)
    path, team = args[0], args[1].upper()
    size = 24
    if "--size" in sys.argv:
        size = int(sys.argv[sys.argv.index("--size") + 1])
    invert = "--invert" in sys.argv

    img, bg = load(path, size)
    rows = to_grid(img, bg, invert)
    out = preview(rows, os.path.splitext(path)[0] + f".sprite{size}.png")

    print(f'        "{team}": TeamSprite(rows: [')
    for row in rows:
        print(f'            "{row}",')
    print("        ]),")
    print(f"\n// preview: {out}", file=sys.stderr)
    filled = sum(ch != "." for row in rows for ch in row)
    print(f"// {filled}/{size*size} pixels filled", file=sys.stderr)


main()
