#!/usr/bin/env python3
"""Generate every original asset and resource file for this GB Studio test ROM.

Writes background/sprite PNGs, their .gbsres files, the scene and actors.
Text is rasterised from Pillow's built-in bitmap font and scaled up with
nearest-neighbour. Deterministic (uuid5 ids), safe to re-run.
Copyright (c) 2026 Press Any test ROM authors. MIT.
"""
import hashlib
import json
import os
import uuid

from PIL import Image, ImageDraw, ImageFont

MODE = "dmg"  # "dmg" or "gbc"
TILE_COLORS = "" if MODE == "dmg" else "003c+013c+023c+033c+0478+"
ROOT = os.path.dirname(os.path.abspath(__file__))
NS = uuid.UUID("6f1d2a52-0c1e-4c7b-9a43-5a9e7d0b1c11")
SHADES = [(0xE0, 0xF8, 0xCF), (0x86, 0xC0, 0x6C), (0x30, 0x68, 0x50), (0x07, 0x18, 0x21)]
TRANSPARENT = (0x65, 0xFF, 0x00)
FONT = ImageFont.load_default_imagefont()


def uid(name):
    return str(uuid.uuid5(NS, MODE + ":" + name))


def text_img(s, scale, bold=True):
    """Render text with the built-in bitmap font, bold by double strike."""
    w = int(FONT.getlength(s)) + 2
    im = Image.new("1", (w, 11), 0)
    d = ImageDraw.Draw(im)
    d.text((0, 0), s, font=FONT, fill=1)
    if bold:
        d.text((1, 0), s, font=FONT, fill=1)
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)


def paste_text(img, s, x, y, scale, shade):
    t = text_img(s, scale, False)
    px = img.load()
    tp = t.load()
    for yy in range(t.height):
        for xx in range(t.width):
            if tp[xx, yy] and 0 <= x + xx < img.width and 0 <= y + yy < img.height:
                px[x + xx, y + yy] = shade


def indexed(size, fill):
    im = Image.new("RGB", size, fill)
    return im


def save_p(im, path, palette_colors):
    pal = Image.new("P", (1, 1))
    flat = []
    for c in palette_colors:
        flat += list(c)
    flat += [0] * (768 - len(flat))
    pal.putpalette(flat)
    out = im.quantize(palette=pal, dither=Image.NONE)
    out.save(path)


def make_background():
    bg = Image.new("RGB", (160, 144), SHADES[0])
    d = ImageDraw.Draw(bg)
    # shade-2 divider lines on band edges
    for y in (23, 47, 71, 95):
        d.line([(0, y), (159, y)], fill=SHADES[1])
    dark = SHADES[3]
    label = "DMG" if MODE == "dmg" else "GBC"
    paste_text(bg, "GBSTUDIO", 2, 1, 2, dark)
    paste_text(bg, label + " TEST", 2, 25, 2, dark)
    paste_text(bg, "GB Studio", 2, 49, 2, dark)
    paste_text(bg, "4.3.2", 2, 73, 2, dark)
    paste_text(bg, "GB" if MODE == "dmg" else "GBC", 2, 98, 4, dark)
    paste_text(bg, "HELD:", 114, 35, 1, dark)
    os.makedirs(os.path.join(ROOT, "assets/backgrounds"), exist_ok=True)
    path = os.path.join(ROOT, "assets/backgrounds/main.png")
    save_p(bg, path, SHADES)
    tiles = set()
    for ty in range(18):
        for tx in range(20):
            tiles.add(bg.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8)).tobytes())
    print("unique bg tiles:", len(tiles))
    assert len(tiles) <= 192, len(tiles)
    write(
        "assets/backgrounds/main.png.gbsres",
        {
            "_resourceType": "background",
            "id": uid("bg-main"),
            "name": "main",
            "symbol": "bg_main",
            "tileColors": TILE_COLORS,
            "filename": "main.png",
            "width": 20,
            "height": 18,
            "imageWidth": 160,
            "imageHeight": 144,
            "autoColor": False,
        },
    )


def tile_entries(n, frame, x0=0):
    return [
        {
            "id": uid("tile-%d-%d" % (frame, i)),
            "x": x0 + 8 * i,
            "y": 0,
            "sliceX": 8 * i,
            "sliceY": 16 * frame,
            "flipX": False,
            "flipY": False,
            "palette": 0,
            "paletteIndex": 0,
            "objPalette": "OBP0",
            "priority": False,
        }
        for i in range(n)
    ]


def sprite_res(name, png, w, h, frame_tiles, x0=0):
    """frame_tiles: list of tile-count per frame (0 = blank frame)."""
    sid = uid("sprite-" + name)
    frames = []
    for f, n in enumerate(frame_tiles):
        tl = tile_entries(n, f, x0)
        for t in tl:
            t["id"] = uid("t-%s-%d-%d" % (name, f, t["x"]))
        frames.append({"id": uid("f-%s-%d" % (name, f)), "frames_": None, "tiles": tl})
    for fr in frames:
        del fr["frames_"]
    anims = [{"id": uid("a-%s-0" % name), "frames": frames}]
    for k in range(1, 8):
        anims.append({"id": uid("a-%s-%d" % (name, k)), "frames": [{"id": uid("f-%s-e%d" % (name, k)), "tiles": []}]})
    with open(os.path.join(ROOT, "assets/sprites", png), "rb") as fh:
        chk = hashlib.sha1(fh.read()).hexdigest()
    write(
        "assets/sprites/%s.gbsres" % png,
        {
            "_resourceType": "sprite",
            "id": sid,
            "name": name,
            "symbol": "sprite_" + name,
            "states": [
                {
                    "id": uid("state-" + name),
                    "name": "",
                    "animationType": "fixed",
                    "flipLeft": False,
                    "animations": anims,
                }
            ],
            "numTiles": sum(frame_tiles),
            "canvasOriginX": 0,
            "canvasOriginY": 0,
            "canvasWidth": w,
            "canvasHeight": 16,
            "boundsX": 0,
            "boundsY": 0,
            "boundsWidth": 16,
            "boundsHeight": 16,
            "animSpeed": 15,
            "filename": png,
            "width": w,
            "height": h,
            "checksum": chk,
        },
    )
    return sid


def make_sprites():
    os.makedirs(os.path.join(ROOT, "assets/sprites"), exist_ok=True)
    # Ball 16x16: dark outline, mid fill, light highlight, transparent corners.
    ball = Image.new("RGB", (16, 16), TRANSPARENT)
    px = ball.load()
    cx = cy = 7.5
    for y in range(16):
        for x in range(16):
            r = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if r <= 7.6:
                px[x, y] = SHADES[3] if r > 6.4 else SHADES[1]
    for (x, y) in [(4, 4), (5, 4), (4, 5), (6, 3), (3, 6), (5, 5)]:
        px[x, y] = SHADES[0]
    save_p(ball, os.path.join(ROOT, "assets/sprites/ball.png"), [TRANSPARENT] + SHADES)
    ball_id = sprite_res("ball", "ball.png", 16, 16, [2])

    labels = ["A", "B", "START", "SELECT", "UP", "DOWN", "LEFT", "RIGHT"]
    sheet = Image.new("RGB", (48, 144), TRANSPARENT)
    counts = [0]
    for i, lab in enumerate(labels):
        frame = i + 1
        for ci, ch in enumerate(lab):
            t = text_img(ch, 1, False)  # glyph cell 6x11 (+2 spare), 1 px per source pixel
            ox, oy = ci * 8 + 1, frame * 16 + 2
            tp = t.load()
            sp = sheet.load()
            for yy in range(min(t.height, 12)):
                for xx in range(min(t.width, 7)):
                    if tp[xx, yy]:
                        sp[ox + xx, oy + yy] = SHADES[3]
        counts.append(len(lab))
    save_p(sheet, os.path.join(ROOT, "assets/sprites/buttons.png"), [TRANSPARENT] + SHADES)
    # tile x is relative to a canvas-centered 16px base: -16 .. +24 for a 48px canvas
    btn_id = sprite_res("buttons", "buttons.png", 48, 144, counts, x0=-16)
    return ball_id, btn_id


def write(rel, obj):
    p = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as fh:
        json.dump(obj, fh, indent=2)
        fh.write("\n")


def ev(command, args, name):
    return {"id": uid("ev-" + name), "command": command, "args": args}


def num(v):
    return {"type": "number", "value": v}


def move_to(actor, x, y, name):
    return ev(
        "EVENT_ACTOR_MOVE_TO",
        {
            "actorId": actor,
            "x": num(x),
            "y": num(y),
            "units": "pixels",
            "collideWith": [],
            "lockDirection": [],
            "moveType": "diagonal",
        },
        name,
    )


def set_frame(actor, f, name):
    return ev("EVENT_ACTOR_SET_FRAME", {"actorId": actor, "frame": num(f)}, name)


def make_scene(bg_id, ball_id, btn_id):
    inputs = ["a", "b", "start", "select", "up", "down", "left", "right"]
    ind_actor = uid("actor-indicator")

    def chain(i):
        if i == len(inputs):
            return [set_frame(ind_actor, 0, "frame-blank")]
        return [
            ev(
                "EVENT_IF_INPUT",
                {
                    "input": [inputs[i]],
                    "true": [set_frame(ind_actor, i + 1, "frame-%d" % i)],
                    "false": chain(i + 1),
                    "__collapseElse": False,
                    "__disableElse": False,
                },
                "if-%d" % i,
            )
        ]

    loop_body = chain(0) + [
        ev("EVENT_WAIT", {"units": "frames", "frames": num(1), "time": num(0.1)}, "wait")
    ]
    # Input polling lives in the indicator's update script (the init script must end).
    # The engine always has a player actor; hide it (the ball sprite is reused for it).
    script = [ev("EVENT_ACTOR_HIDE", {"actorId": "player"}, "hide-player")]
    pal = []
    tile_colors = ""
    spr_pal = []
    if MODE == "gbc":
        pal_defs = [
            ["FFE0E0", "F0A0A0", "D04040", "700000"],
            ["FFF0C0", "F0C040", "C08000", "5A3800"],
            ["D8F8D0", "90D880", "30A030", "105010"],
            ["D0E8FF", "80B8F0", "3070D0", "102870"],
            ["F0D8FF", "C090F0", "8040C0", "381060"],
        ]
        pal = []
        for i, c in enumerate(pal_defs):
            write(
                "project/palettes/gbc_test_%d.gbsres" % (i + 1),
                {"_resourceType": "palette", "id": "gbc-test-%d" % (i + 1), "name": "GBC Test %d" % (i + 1), "colors": c},
            )
            pal.append("gbc-test-%d" % (i + 1))
        pal.append("")
        tile_colors = "003c+013c+023c+033c+0478+"
    write(
        "project/scenes/main/scene.gbsres",
        {
            "_resourceType": "scene",
            "id": uid("scene-main"),
            "_index": 0,
            "type": "TOPDOWN",
            "name": "Main",
            "symbol": "scene_main",
            "x": 100,
            "y": 100,
            "width": 20,
            "height": 18,
            "backgroundId": bg_id,
            "tilesetId": "",
            "colorModeOverride": "none",
            "paletteIds": pal,
            "spritePaletteIds": [],
            "autoFadeSpeed": 1,
            "script": script,
            "playerHit1Script": [],
            "playerHit2Script": [],
            "playerHit3Script": [],
            "collisions": "",
        },
    )

    def actor(name, aid, sprite, x, y, upd):
        write(
            "project/scenes/main/actors/%s.gbsres" % name,
            {
                "_resourceType": "actor",
                "id": aid,
                "_index": 0 if name == "ball" else 1,
                "symbol": "actor_" + name,
                "prefabId": "",
                "name": name,
                "x": x,
                "y": y,
                "frame": 0,
                "animate": False,
                "spriteSheetId": sprite,
                "paletteId": "",
                "direction": "down",
                "moveSpeed": 1,
                "animSpeed": 255,  # ANIM_PAUSED: stops the engine stepping frames on its own
                "isPinned": False,
                "persistent": False,
                "collisionGroup": "",
                "collisionExtraFlags": [],
                "prefabScriptOverrides": {},
                "script": [],
                "startScript": [],
                "updateScript": upd,
            },
        )

    ball_actor = uid("actor-ball")
    # Pixel targets are the ball's top-left corner; region x 88..136, y 100..124.
    pts = [(136, 124), (88, 124), (136, 100), (88, 100), (112, 112)]
    upd = [move_to("$self$", x, y, "ball-%d" % i) for i, (x, y) in enumerate(pts)]
    actor("ball", ball_actor, ball_id, 11, 13, upd)
    actor("indicator", ind_actor, btn_id, 16, 8, loop_body)


def make_project():
    write(
        "project/variables.gbsres", {"_resourceType": "variables", "variables": [], "constants": []}
    )
    with open(os.path.join(ROOT, "project/settings.gbsres")) as fh:
        s = json.load(fh)
    return s


def update_settings(ball_id, bg_scene):
    p = os.path.join(ROOT, "project/settings.gbsres")
    with open(p) as fh:
        s = json.load(fh)
    s["startSceneId"] = bg_scene
    s["colorMode"] = "mono" if MODE == "dmg" else "color"
    s["defaultPlayerSprites"] = {k: ball_id for k in s["defaultPlayerSprites"]}
    s["romFilename"] = "gbstudio-%s" % MODE
    s["openBuildFolderOnExport"] = False
    s["spriteMode"] = "8x16"
    with open(p, "w") as fh:
        json.dump(s, fh, indent=2)
        fh.write("\n")
    write(
        "project.gbsproj",
        {
            "_resourceType": "project",
            "name": "gbstudio-" + MODE,
            "author": "Press Any test ROM authors",
            "notes": "Original test ROM. MIT.",
            "_version": "4.2.0",
            "_release": "10",
        },
    )


if __name__ == "__main__":
    make_background()
    ball_id, btn_id = make_sprites()
    bg_id = uid("bg-main")
    make_scene(bg_id, ball_id, btn_id)
    update_settings(ball_id, uid("scene-main"))
    print("done")
