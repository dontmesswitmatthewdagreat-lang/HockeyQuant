#!/usr/bin/env python3
"""Preview TeamSprite pixel art outside the simulator.

Simulator screenshots are downscaled far too much to judge 16x16 art, which
makes authoring a sprite by rebuild-and-look painfully slow. This renders the
sprites straight from the Swift source — grids from TeamSprite.swift, colors
resolved from TeamInfo.swift with the same rule CrestView uses — so what you
see here is what ships.

    python3 ios/Tools/render_sprites.py [TEAM ...]

Writes sprites.png: each team at three scales, because a sprite that reads at
crest size is the actual bar, not one that reads blown up.
"""
import os
import re
import sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SPRITES_SWIFT = os.path.join(HERE, "..", "HockeyQuant", "DesignSystem", "TeamSprite.swift")
TEAMINFO_SWIFT = os.path.join(HERE, "..", "HockeyQuant", "Core", "TeamInfo.swift")


def parse_sprites(path):
    src = open(path).read()
    out = {}
    for m in re.finditer(r'"([A-Z]{3})": TeamSprite\(rows: \[(.*?)\]\)', src, re.S):
        out[m.group(1)] = re.findall(r'"([.XLDE]*)"', m.group(2))
    return out


def parse_teams(path):
    src = open(path).read()
    out = {}
    for m in re.finditer(
        r'TeamInfo\(abbrev: "([A-Z]{3})".*?primaryHex: 0x([0-9A-Fa-f]{6}), '
        r'secondaryHex: 0x([0-9A-Fa-f]{6})\)', src):
        out[m.group(1)] = (int(m.group(2), 16), int(m.group(3), 16))
    return out


def rgb(hex_):
    return ((hex_ >> 16) & 0xFF) / 255, ((hex_ >> 8) & 0xFF) / 255, (hex_ & 0xFF) / 255


def lum(hex_):
    r, g, b = rgb(hex_)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def to255(hex_):
    return ((hex_ >> 16) & 0xFF, (hex_ >> 8) & 0xFF, hex_ & 0xFF)


def crest_ink(primary, secondary):
    """Mirror of TeamInfo.crestMonogram."""
    if abs(lum(primary) - lum(secondary)) >= 0.28:
        return to255(secondary)
    return (255, 255, 255) if lum(primary) < 0.5 else to255(0x10141B)


def blend(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(rows, disc, ink, cell):
    n = len(rows)
    img = Image.new("RGB", (n * cell, n * cell), disc)
    d = ImageDraw.Draw(img)
    light, dark = blend(ink, (255, 255, 255), 0.45), blend(ink, (0, 0, 0), 0.40)
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch == ".":
                continue
            color = {"X": ink, "L": light, "D": dark, "E": disc}[ch]
            d.rectangle([c * cell, r * cell, (c + 1) * cell - 1, (r + 1) * cell - 1],
                        fill=color)
    return img


def main():
    sprites, teams = parse_sprites(SPRITES_SWIFT), parse_teams(TEAMINFO_SWIFT)
    if not sprites:
        sys.exit("no sprites found — did TeamSprite.swift's format change?")
    wanted = [t.upper() for t in sys.argv[1:]] or sorted(sprites)
    missing = [t for t in wanted if t not in sprites]
    if missing:
        sys.exit(f"no sprite for {', '.join(missing)}")

    scales, pad = (14, 4, 2), 16
    box = len(sprites[wanted[0]]) * scales[0]
    widths = [len(sprites[wanted[0]]) * s for s in scales]
    sheet = Image.new("RGB", (pad + sum(w + pad for w in widths),
                              pad + len(wanted) * (box + pad)), (245, 245, 248))
    for i, team in enumerate(wanted):
        primary, secondary = teams.get(team, (0x333333, 0xFFFFFF))
        disc, ink = to255(primary), crest_ink(primary, secondary)
        x, y = pad, pad + i * (box + pad)
        for scale, w in zip(scales, widths):
            sheet.paste(render(sprites[team], disc, ink, scale), (x, y + (box - w) // 2))
            x += w + pad
    out = os.path.join(os.getcwd(), "sprites.png")
    sheet.save(out)
    print(f"wrote {out} — {', '.join(wanted)}")


main()
