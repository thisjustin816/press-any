#!/usr/bin/env python3
"""Export fixed wordmark artwork from a separately licensed Corporatus font.

Requires fonttools, reportlab and PyYAML. Keep the font outside the checkout;
only the outlined PDF artwork ships. Pass the purchased OTF file as the argument.
"""

import argparse
import json
from pathlib import Path

from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont
from reportlab.pdfgen import canvas
import yaml


ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App/Assets.xcassets"
POINT_SIZE = 34
TRACKING = 0.028


class OutlinePen(BasePen):
    def __init__(self, glyph_set, path):
        super().__init__(glyph_set)
        self.path = path

    def _moveTo(self, point):
        self.path.moveTo(*point)

    def _lineTo(self, point):
        self.path.lineTo(*point)

    def _curveToOne(self, first, second, end):
        self.path.curveTo(*first, *second, *end)

    def _closePath(self):
        self.path.close()

    def _endPath(self):
        pass


def asset_color(name, appearance):
    data = json.loads((ASSETS / f"{name}.colorset/Contents.json").read_text())
    entry = next(color for color in data["colors"] if
                 (color.get("appearances", [{}])[0].get("value", "light") == appearance))
    def component(channel):
        value = entry["color"]["components"][channel]
        return int(value, 16) / 255 if value.startswith("0x") else float(value)

    return tuple(component(channel) for channel in ("red", "green", "blue"))


def export(font, text, destination, ink, accent):
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()
    units = font["head"].unitsPerEm
    scale = POINT_SIZE / units
    # Match the wordmark's explicit tracking; Corporatus has no kerning pairs for this name.
    advances = [font["hmtx"][cmap[ord(letter)]][0] for letter in text]
    width = sum(advances) * scale + len(text) * POINT_SIZE * TRACKING
    height = (font["hhea"].ascent - font["hhea"].descent) * scale
    pdf = canvas.Canvas(str(destination), pagesize=(width, height), invariant=1, pageCompression=1)
    pdf.setTitle(text)
    pdf.setAuthor("Alex Rosario; Roc Mitchell")
    pdf.setSubject("Static wordmark artwork. Copyright (c) 2017 by Alex Rosario. All rights reserved.")
    accent_index = text.rfind(" ") + 1
    x = 0
    for index, letter in enumerate(text):
        pdf.saveState()
        pdf.translate(x, -font["hhea"].descent * scale)
        pdf.scale(scale, scale)
        pdf.setFillColorRGB(*(accent if index == accent_index else ink))
        path = pdf.beginPath()
        glyph_set[cmap[ord(letter)]].draw(OutlinePen(glyph_set, path))
        pdf.drawPath(path, stroke=0, fill=1)
        pdf.restoreState()
        x += advances[index] * scale + POINT_SIZE * TRACKING
    pdf.showPage()
    pdf.save()


def image_set(font, text, name, colors, template=False):
    directory = ASSETS / f"{name}.imageset"
    directory.mkdir(exist_ok=True)
    images = []
    for appearance, ink, accent in colors:
        filename = f"{name}{appearance.title()}.pdf" if appearance else f"{name}.pdf"
        export(font, text, directory / filename, ink, accent)
        image = {"filename": filename, "idiom": "universal"}
        if appearance == "dark":
            image["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        images.append(image)
    properties = {
        "preserves-vector-representation": True,
        "template-rendering-intent": "template" if template else "original",
    }
    contents = {"images": images, "info": {"author": "xcode", "version": 1}, "properties": properties}
    (directory / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("font", type=Path)
    arguments = parser.parse_args()
    font_path = arguments.font.resolve()
    if font_path.is_relative_to(ROOT):
        parser.error("Keep the licensed font outside the checkout.")
    font = TTFont(font_path)
    if font["name"].getDebugName(6) != "Corporatus-Regular":
        parser.error("Expected the licensed Corporatus-Regular font.")
    project = yaml.safe_load((ROOT / "project.yml").read_text())
    name = project["targets"]["PressAny"]["settings"]["base"]["INFOPLIST_KEY_CFBundleDisplayName"]
    image_set(font, name, "Wordmark", [
        (appearance, asset_color("BrandInk", appearance), asset_color("AccentColor", appearance))
        for appearance in ("light", "dark")
    ])
    image_set(font, name, "WordmarkRecess", [
        ("light", (20 / 255, 20 / 255, 22 / 255), (123 / 255, 23 / 255, 71 / 255)),
        ("dark", (64 / 255, 64 / 255, 68 / 255), (96 / 255, 30 / 255, 66 / 255)),
    ])
    image_set(font, name.upper(), "WordmarkPlaque", [("", (1, 1, 1), (1, 1, 1))], template=True)


if __name__ == "__main__":
    main()
