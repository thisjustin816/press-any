#!/usr/bin/env python3
"""Generate the original PNG assets in ../res (font, background, ball sprite).

Run once; the PNGs are committed.  Needs Pillow.  Output is 4-shade
indexed PNG so png2asset maps colours 0..3 to DMG shades white..black.
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "res")
PAL = [255, 255, 255,  170, 170, 170,  85, 85, 85,  0, 0, 0]  # white..black

# 5x7 glyph rows (5 bits, MSB = left).
G = {
 'A': "0E 11 11 1F 11 11 11", 'B': "1E 11 11 1E 11 11 1E", 'C': "0E 11 10 10 10 11 0E",
 'D': "1E 11 11 11 11 11 1E", 'E': "1F 10 10 1E 10 10 1F", 'F': "1F 10 10 1E 10 10 10",
 'G': "0E 11 10 17 11 11 0F", 'H': "11 11 11 1F 11 11 11", 'I': "0E 04 04 04 04 04 0E",
 'J': "07 02 02 02 02 12 0C", 'K': "11 12 14 18 14 12 11", 'L': "10 10 10 10 10 10 1F",
 'M': "11 1B 15 15 11 11 11", 'N': "11 19 15 13 11 11 11", 'O': "0E 11 11 11 11 11 0E",
 'P': "1E 11 11 1E 10 10 10", 'Q': "0E 11 11 11 15 12 0D", 'R': "1E 11 11 1E 14 12 11",
 'S': "0F 10 10 0E 01 01 1E", 'T': "1F 04 04 04 04 04 04", 'U': "11 11 11 11 11 11 0E",
 'V': "11 11 11 0A 0A 04 04", 'W': "11 11 11 15 15 1B 11", 'X': "11 11 0A 04 0A 11 11",
 'Y': "11 11 0A 04 04 04 04", 'Z': "1F 01 02 04 08 10 1F",
 '0': "0E 11 13 15 19 11 0E", '1': "04 0C 04 04 04 04 0E", '2': "0E 11 01 02 04 08 1F",
 '3': "1F 02 04 02 01 11 0E", '4': "02 06 0A 12 1F 02 02", '5': "1F 10 1E 01 01 11 0E",
 '6': "06 08 10 1E 11 11 0E", '7': "1F 01 02 04 08 08 08", '8': "0E 11 11 0E 11 11 0E",
 '9': "0E 11 11 0F 01 02 0C",
 '!': "04 04 04 04 04 00 04", "'": "04 04 08 00 00 00 00", '(': "02 04 08 08 08 04 02",
 ')': "08 04 02 02 02 04 08", '-': "00 00 00 1F 00 00 00", '.': "00 00 00 00 00 0C 0C",
 ':': "00 0C 0C 00 0C 0C 00", '?': "0E 11 01 02 04 00 04",
}
# Order required by ZGB's Print(): space, A-Z, 0-9, ! ' ( ) - . : ?
ORDER = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!'()-.:?"


def save(img, name):
    p = Image.new("P", img.size)
    p.putpalette(PAL + [0] * (768 - len(PAL)))
    p.putdata(list(img.get_flattened_data() if hasattr(img, 'get_flattened_data') else img.getdata()))
    p.save(os.path.join(RES, name))


def glyph(ch):
    """8x8 cell: 5x7 glyph, bolded by 1px horizontally, 1px left/top margin."""
    cell = [[0] * 8 for _ in range(8)]
    if ch == ' ':
        return cell
    for y, row in enumerate(G[ch].split()):
        bits = int(row, 16)
        for x in range(5):
            if bits & (0x10 >> x):
                cell[y + 1][1 + x] = 3
                if ch not in ".:'!-":
                    cell[y + 1][2 + x] = 3
    return cell


def font():
    # One extra, unused swatch tile holds all four shades in palette order so
    # png2asset keeps colour indices 0..3 (it drops unused palette entries).
    img = Image.new("L", (8 * (len(ORDER) + 1), 8), 0)
    for x in range(8):
        for y in range(8):
            img.putpixel((len(ORDER) * 8 + x, y), x // 2)
    for i, ch in enumerate(ORDER):
        for y, row in enumerate(glyph(ch)):
            for x, v in enumerate(row):
                img.putpixel((i * 8 + x, y), v)
    # one-tile-high strip; png2asset -map keeps tile order with
    # -keep_duplicate_tiles (see font.png.meta)
    save(img, "font.png")


def background():
    img = Image.new("L", (160, 144), 0)
    # play-field frame around the bounce area: tile rows 8..12 (y 64..103)
    for x in range(160):
        for t in (64, 65, 102, 103):
            img.putpixel((x, t), 3)
    for y in range(64, 104):
        for xx in (0, 1, 158, 159):
            img.putpixel((xx, y), 3)
    # dark inner rule + light checker inside (all four shades used)
    for x in range(8, 152):
        img.putpixel((x, 66), 2)
        img.putpixel((x, 101), 2)
    # light checker inside to prove tile map rendering
    for y in range(72, 100):
        for x in range(8, 152):
            if ((x // 8) + (y // 8)) % 2 == 0 and (x % 8 in (3, 4)) and (y % 8 in (3, 4)):
                img.putpixel((x, y), 1)
    save(img, "bkg.png")


def ball():
    # 16x16 ball: ring with highlight, 8x16 sprites => two columns
    img = Image.new("L", (16, 16), 0)
    cx = cy = 7.5
    for y in range(16):
        for x in range(16):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d <= 7.6:
                v = 3 if d > 5.8 else 2
                if (x - 5) ** 2 + (y - 5) ** 2 <= 5:
                    v = 0 if v == 2 else v  # shine (colour 0 is transparent)
                    v = 1 if v == 0 else v
                img.putpixel((x, y), v)
    # colour 0 is transparent for sprites: keep outside as 0
    save(img, os.path.join("sprites", "ball.png"))


if __name__ == "__main__":
    os.makedirs(os.path.join(RES, "sprites"), exist_ok=True)
    font(); background(); ball()
