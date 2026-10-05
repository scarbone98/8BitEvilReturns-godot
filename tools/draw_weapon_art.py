#!/usr/bin/env python3
"""Draws the weapon art that had no art of its own (or borrowed a pickup's):
projectiles, plus 64x64 skill cards in the style of the original skill icons
(dark rounded card, dithered glow, outlined item). Pure pixel placement: no
antialiasing anywhere, so the output is on-grid by construction.

Usage: tools/draw_weapon_art.py [OUT_DIR]   (default assets/sprites)
Needs Pillow (e.g. ~/tools/pixel-snap/pyenv/bin/python3)."""
import math, sys, os
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
os.makedirs(OUT, exist_ok=True)

def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

CLEAR = (0, 0, 0, 0)

# ------------------------------------------------------------------ helpers

def new(w, h):
    return Image.new("RGBA", (w, h), CLEAR)

def put(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((int(x), int(y)), c)

def rows(im, x0, y0, art, pal):
    """Paints a text grid: each char is a palette key, '.' is nothing."""
    for j, line in enumerate(art):
        for i, ch in enumerate(line):
            if ch != "." and ch != " ":
                put(im, x0 + i, y0 + j, pal[ch])

def outline(im, col, diagonal=False):
    """1px outline around everything opaque."""
    src = im.copy()
    w, h = im.size
    nb = [(1, 0), (-1, 0), (0, 1), (0, -1)] + ([(1, 1), (-1, 1), (1, -1), (-1, -1)] if diagonal else [])
    for y in range(h):
        for x in range(w):
            if src.getpixel((x, y))[3] == 0:
                for dx, dy in nb:
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < w and 0 <= yy < h and src.getpixel((xx, yy))[3] > 0:
                        im.putpixel((x, y), col)
                        break
    return im

def disc(im, cx, cy, r, c):
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                put(im, x, y, c)

def poly(im, pts, c):
    d = ImageDraw.Draw(im)
    d.polygon(pts, fill=c)

def line(im, x0, y0, x1, y1, c):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for k in range(n + 1):
        t = k / max(n, 1)
        put(im, round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), c)

def thick(im, x0, y0, x1, y1, r, c):
    n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
    for k in range(n + 1):
        t = k / n
        disc(im, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r, c)

def paste(dst, src, x, y):
    dst.alpha_composite(src, (int(x), int(y)))

def sheet(frames):
    w, h = frames[0].size
    s = new(w * len(frames), h)
    for i, f in enumerate(frames):
        s.alpha_composite(f, (i * w, 0))
    return s

def save(im, name):
    im.save(os.path.join(OUT, name + ".png"))
    print("wrote", name, im.size)

# ------------------------------------------------------------------ skill card

def card(base, mid, glow):
    """64x64 card like the originals: rounded corners, a dithered outer halo of
    `mid`, a solid inner disc of `mid`, dithered `glow` in the middle."""
    im = Image.new("RGBA", (64, 64), base)
    for (x, y) in [(0, 0), (1, 0), (2, 0), (3, 0), (0, 1), (1, 1), (0, 2), (0, 3)]:
        for (fx, fy) in [(x, y), (63 - x, y), (x, 63 - y), (63 - x, 63 - y)]:
            im.putpixel((fx, fy), CLEAR)
    for y in range(64):
        for x in range(64):
            d = math.hypot(x + 0.5 - 32, y + 0.5 - 32)
            chk = (x + y) % 2 == 0
            if d < 15:
                im.putpixel((x, y), glow if chk else mid)
            elif d < 20:
                im.putpixel((x, y), mid)
            elif d < 28 and chk:
                im.putpixel((x, y), mid)
    return im

def item_on_card(c, item, dark):
    """Outlines the item (dark) and centres it on the card."""
    outline(item, dark)
    bb = item.getbbox()
    it = item.crop(bb)
    paste(c, it, 32 - it.width // 2, 32 - it.height // 2)
    return c

# ------------------------------------------------------------------ art

def wood_stake():
    # Points up (the game rotates it by +90deg). 6x16.
    pal = {"o": hexc("2b1a10"), "l": hexc("c98a4b"), "m": hexc("9a6233"), "d": hexc("6b3f1f"),
           "s": hexc("d8dde6"), "S": hexc("8d96a8"), "t": hexc("f1d2a0")}
    im = new(6, 16)
    rows(im, 0, 0, [
        "..o...",
        "..to..",
        ".otdo.",
        ".olmo.",
        ".olmdo",
        "olmmdo",
        "olmmdo",
        "osssSo",
        "olmmdo",
        "olmmdo",
        "oldmdo",
        "olmmdo",
        "olmddo",
        "osssSo",
        "oddddo",
        ".oooo.",
    ], pal)
    return im

def candy_shot():
    # A small candy corn pellet pointing right, with a sugar streak. 12x8, 2 frames.
    pal = {"w": hexc("fff3d6"), "y": hexc("ffcf3a"), "o": hexc("f07a1e"), "k": hexc("3a1c08"),
           "s": hexc("ffe9b0", 150), "S": hexc("ffe9b0", 70)}
    frames = []
    for f in range(2):
        im = new(12, 8)
        streak = ["SSs", "Ss.", "sS."][f::1][0] if False else None
        rows(im, 0, 0, [
            "......kk....",
            "....kkyyk...",
            ("SSs." if f == 0 else ".Ss.") + "koooyywk",
            ("Ss.." if f == 0 else "SSs.") + "koooyywk",
            "....kkyyk...",
            "......kk....",
        ], pal)
        frames.append(im)
    return [im.crop((0, 0, 12, 6)) for im in frames]

def coin_spin():
    # A tarnished cursed coin with a skull, spinning: 12x12, 6 frames.
    hi, mid, lo, dk, ol = hexc("f2f4f8"), hexc("b9c0cc"), hexc("7d8596"), hexc("4a4f5c"), hexc("1d1f26")
    eye = hexc("b3243a")
    widths = [6, 5, 3, 1, 3, 5]
    frames = []
    for wdt in widths:
        im = new(12, 12)
        for y in range(12):
            for x in range(12):
                dx = (x + 0.5 - 6) / max(wdt, 0.6)
                dy = (y + 0.5 - 6) / 6
                if dx * dx + dy * dy <= 1.0:
                    shade = mid
                    if dy < -0.4 or dx < -0.5:
                        shade = hi
                    if dy > 0.45 or dx > 0.55:
                        shade = lo
                    put(im, x, y, shade)
        if wdt >= 5:
            # skull emblem
            rows(im, 4, 3, ["dddd", "deed", "dddd", ".dd."], {"d": dk, "e": eye})
        elif wdt == 3:
            rows(im, 5, 3, ["dd", "ed", "dd", "d."], {"d": dk, "e": eye})
        else:
            for y in range(1, 11):
                put(im, 6, y, lo)
        outline(im, ol)
        frames.append(im)
    return frames

def flame_skull():
    # A skull riding green ghost-fire, facing right. 16x16, 4 frames.
    bone, bone2, bone3 = hexc("f4efe2"), hexc("cbc3ad"), hexc("8d8572")
    ol, eye, glow = hexc("17110c"), hexc("1a0d10"), hexc("8bff6a")
    f1, f2, f3 = hexc("2fd36b"), hexc("8bff6a"), hexc("d9ffb8")
    frames = []
    for k in range(4):
        im = new(16, 16)
        # flame trail to the left, flickering
        for i in range(9):
            x = 7 - i
            amp = 3.6 - i * 0.35
            wob = math.sin(k * 1.6 + i * 0.9) * 1.2
            for y in range(16):
                d = abs(y + 0.5 - (8 + wob * 0.6))
                if d < amp:
                    c = f1 if d > amp * 0.55 else (f2 if d > amp * 0.2 else f3)
                    if (x + y + k) % 5 == 0 and d > amp * 0.7:
                        continue
                    put(im, x, y, c)
        rows(im, 6, 3, [
            "..bbbbb..",
            ".bbbbbbb.",
            "bbbbbbbbb",
            "bbEEbbEEc",
            "bbEgbbEgc",
            "bbbbccbbc",
            ".bbbbbbc.",
            "..mbmbm..",
            "..b.b.b..",
        ], {"b": bone, "c": bone2, "m": bone3, "E": eye, "g": glow})
        outline(im, ol)
        frames.append(im)
    return frames

def sacred_heart():
    # A glowing heart with a gold cross, pulsing. 32x32, 4 frames.
    r1, r2, r3, r4 = hexc("ff8a9a"), hexc("e8324f"), hexc("a3122f"), hexc("5a0718")
    g1, g2, g3 = hexc("fff4b0"), hexc("f5c542"), hexc("a8761a")
    ray = hexc("fff2a8", 140)
    frames = []
    for k in range(4):
        im = new(32, 32)
        pulse = [0.0, 0.6, 1.0, 0.4][k]
        # holy glow: a dithered halo that swells with the beat
        for y in range(32):
            for x in range(32):
                d = math.hypot(x + 0.5 - 16, y + 0.5 - 16)
                if d < 11.5 + pulse * 2.5 and (x + y) % 2 == 0:
                    put(im, x, y, ray)
        s = 8.3 + pulse * 0.6
        for y in range(32):
            for x in range(32):
                u = (x + 0.5 - 16) / s
                v = -(y + 0.5 - 17) / s
                # classic heart curve
                if (u * u + v * v - 1) ** 3 - u * u * v ** 3 <= 0:
                    light = -u * 0.5 + v * 0.7
                    c = r1 if light > 0.75 else r2 if light > -0.1 else r3 if light > -0.7 else r4
                    put(im, x, y, c)
        # gold cross on top
        rows(im, 13, 3, [
            "..ggk.",
            "..gGk.",
            "gggGkk",
            "GGGGGk",
            "..gGk.",
            "..gGk.",
        ], {"g": g1, "G": g2, "k": g3})
        # outline the heart and cross only (not the glow)
        solid = Image.new("RGBA", im.size, CLEAR)
        for y in range(32):
            for x in range(32):
                if im.getpixel((x, y))[3] == 255:
                    solid.putpixel((x, y), im.getpixel((x, y)))
        outline(solid, hexc("3a0410"))
        glow = Image.new("RGBA", im.size, CLEAR)
        for y in range(32):
            for x in range(32):
                if 0 < im.getpixel((x, y))[3] < 255 and solid.getpixel((x, y))[3] == 0:
                    glow.putpixel((x, y), im.getpixel((x, y)))
        glow.alpha_composite(solid)
        im = glow
        frames.append(im)
    return frames

# ---- card items (drawn on 64x64, then outlined and centred) ----

def card_wood_stake():
    it = new(64, 64)
    wood_l, wood, wood_d, tip = hexc("d39a5a"), hexc("9a6233"), hexc("5e3519"), hexc("f1d2a0")
    sil, sil_d = hexc("e3e8f0"), hexc("8d96a8")
    # a big stake on the diagonal, point at the top right
    thick(it, 14, 50, 44, 20, 4.2, wood)
    thick(it, 13, 49, 42, 20, 2.0, wood_l)
    thick(it, 17, 52, 46, 23, 1.2, wood_d)
    poly(it, [(41, 15), (54, 10), (49, 23)], wood)
    poly(it, [(44, 15), (54, 10), (47, 19)], tip)
    for t in (0.28, 0.62):
        cx, cy = 14 + 30 * t, 50 - 30 * t
        thick(it, cx - 3.5, cy - 3.5, cx + 3.5, cy + 3.5, 1.5, sil)
        line(it, cx - 2, cy + 3, cx + 3, cy - 2, sil_d)
    # wood chips
    for (x, y) in [(52, 26), (55, 30), (50, 33), (8, 22)]:
        rows(it, x, y, ["ll", "dd"], {"l": wood_l, "d": wood_d})
    return item_on_card(card(hexc("2a1206"), hexc("4b2410"), hexc("6e3a17")), it, hexc("140803"))

def card_airstrike():
    it = new(64, 64)
    body, body_l, body_d, fin = hexc("4a4f5c"), hexc("8a93a6"), hexc("23262e"), hexc("b8352f")
    fire1, fire2 = hexc("ffd23f"), hexc("ff7a1a")
    # bomb falling diagonally, fins up-left
    disc(it, 36, 36, 11, body)
    disc(it, 33, 33, 7, body_l)
    disc(it, 36, 36, 11, body) if False else None
    for y in range(64):
        for x in range(64):
            if it.getpixel((x, y))[3] and (x - 36) + (y - 36) > 6:
                put(it, x, y, body_d)
    thick(it, 22, 22, 28, 28, 4, body)
    poly(it, [(10, 24), (20, 18), (24, 24), (16, 30)], body_l)
    poly(it, [(24, 10), (18, 20), (24, 24), (30, 16)], body_l)
    line(it, 11, 25, 17, 29, body_d)
    line(it, 25, 11, 29, 17, body_d)
    thick(it, 24, 24, 27, 27, 2.6, fin)  # red band where tail meets body
    rows(it, 40, 30, ["ww", "w."], {"w": hexc("e9eef7")})
    # sparks / speed lines
    for i, (x, y) in enumerate([(50, 48), (54, 44), (47, 53)]):
        disc(it, x, y, 2.2 - i * 0.4, fire2)
        put(it, x, y, fire1)
    return item_on_card(card(hexc("2b1405"), hexc("5a2c0b"), hexc("8a4510")), it, hexc("120803"))

def card_plasma_storm():
    it = new(64, 64)
    f1, f2, f3, f4 = hexc("fff2c4"), hexc("ffb347"), hexc("ff5a2b"), hexc("b0186a")
    zap, zap2 = hexc("f3e9ff"), hexc("c38bff")
    # fireball core
    for y in range(64):
        for x in range(64):
            d = math.hypot(x + 0.5 - 30, y + 0.5 - 34)
            if d < 13:
                put(it, x, y, f1 if d < 5 else f2 if d < 8.5 else f3 if d < 11 else f4)
    # tail flames to the lower left
    for i in range(8):
        disc(it, 22 - i * 2.2, 42 + i * 2.0, 6 - i * 0.6, f3 if i % 2 else f4)
    # lightning forks out of it
    for path in [[(36, 26), (42, 20), (40, 16), (50, 9)], [(40, 36), (47, 38), (46, 44), (55, 47)], [(26, 24), (24, 16), (29, 12)]]:
        for a, b in zip(path, path[1:]):
            thick(it, *a, *b, 1.0, zap2)
            line(it, *a, *b, zap)
    return item_on_card(card(hexc("1c0624"), hexc("3d0f4a"), hexc("6a1a72")), it, hexc("0d0212"))

def card_candy_shotgun():
    it = new(64, 64)
    steel, steel_l, steel_d = hexc("6d7486"), hexc("b4bccb"), hexc("353946")
    wood, wood_l, wood_d = hexc("9a5a2a"), hexc("cc8a4a"), hexc("5c3012")
    # a blunderbuss pointing up-right: wooden stock, brass-banded barrel, flared bell
    poly(it, [(4, 54), (10, 60), (24, 46), (20, 40), (14, 42)], wood)
    poly(it, [(5, 54), (9, 57), (20, 45), (17, 42)], wood_l)
    line(it, 10, 60, 24, 46, wood_d)
    thick(it, 21, 43, 26, 38, 2.2, wood_d)  # grip
    rows(it, 22, 44, ["sss", "s.s", "sss"], {"s": steel_d})  # trigger guard
    thick(it, 22, 40, 40, 22, 3.0, steel)
    thick(it, 21, 38, 39, 20, 1.0, steel_l)
    thick(it, 24, 42, 42, 24, 0.8, steel_d)
    poly(it, [(37, 19), (44, 12), (52, 20), (45, 27)], steel)
    poly(it, [(40, 14), (44, 10), (54, 20), (50, 24)], steel_l)
    poly(it, [(42, 17), (45, 14), (49, 18), (46, 21)], steel_d)
    brass = hexc("e0a83a")
    for t in (0.3, 0.65):
        cx, cy = 22 + 18 * t, 40 - 18 * t
        thick(it, cx - 3, cy - 3, cx + 3, cy + 3, 0.9, brass)
    # candy corn blasting out of the bell
    def corn(x, y):
        rows(it, x, y, ["...w...", "..www..", "..yyy..", ".yyyyy.", ".ooooo.", "ooooooo"],
             {"w": hexc("fff3d6"), "y": hexc("ffcf3a"), "o": hexc("f07a1e")})
    corn(50, 1); corn(56, 12); corn(41, 0)
    return item_on_card(card(hexc("2b1405"), hexc("5c2a08"), hexc("8f4a0d")), it, hexc("140803"))

def card_silver_coin():
    it = new(64, 64)
    hi, mid, lo, dk, eye = hexc("f6f7fb"), hexc("c3c9d4"), hexc("8a92a3"), hexc("454b59"), hexc("c22a43")
    for y in range(64):
        for x in range(64):
            dx, dy = (x + 0.5 - 30) / 19, (y + 0.5 - 32) / 19
            d = dx * dx + dy * dy
            if d <= 1:
                c = mid
                if d > 0.8:
                    c = hi if (dx + dy) < 0 else lo
                elif d > 0.68:
                    c = lo if (dx + dy) < 0 else hi
                elif dx + dy < -0.8:
                    c = hi
                put(it, x, y, c)
    # skull emblem
    rows(it, 22, 21, [
        "...dddddd...",
        ".dddddddddd.",
        "dddddddddddd",
        "dddddddddddd",
        "ddEEEddEEEdd",
        "ddEEEddEEEdd",
        "ddEEEddEEEdd",
        "dddddmmddddd",
        ".dddddddddd.",
        "..dd.dd.dd..",
        "..dddddddd..",
        "...d.dd.d...",
    ], {"d": dk, "E": eye, "m": lo})
    for (x, y) in [(12, 14), (54, 46), (10, 48)]:
        rows(it, x, y, [".w.", "www", ".w."], {"w": hexc("ffffff")})
    return item_on_card(card(hexc("0d1a22"), hexc("1d3442"), hexc("2f5266")), it, hexc("05090c"))

def card_skull_toss():
    it = new(64, 64)
    fs = flame_skull()[1]
    big = fs.resize((48, 48), Image.NEAREST)
    paste(it, big, 10, 8)
    return item_on_card(card(hexc("06190c"), hexc("0f3a1a"), hexc("1d6230")), it, hexc("020803"))

def card_sacred_heart():
    it = new(64, 64)
    h = sacred_heart()[2].resize((64, 64), Image.NEAREST)
    paste(it, h, 0, 0)
    c = card(hexc("2a1a05"), hexc("5a3d0c"), hexc("8d6516"))
    bb = it.getbbox()
    item = it.crop(bb)
    paste(c, item, 32 - item.width // 2, 32 - item.height // 2)
    return c

if __name__ == "__main__":
    save(wood_stake(), "wood_stake_shot")
    save(sheet(candy_shot()), "candy_shot")
    save(sheet(coin_spin()), "coin_spin")
    save(sheet(flame_skull()), "flame_skull")
    save(sheet(sacred_heart()), "sacred_heart")
    save(card_wood_stake(), "wood_stake_skill")
    save(card_airstrike(), "airstrike_skill")
    save(card_plasma_storm(), "plasma_storm_skill")
    save(card_candy_shotgun(), "candy_shotgun_skill")
    save(card_silver_coin(), "silver_coin_skill")
    save(card_skull_toss(), "skull_toss_skill")
    save(card_sacred_heart(), "sacred_heart_skill")
