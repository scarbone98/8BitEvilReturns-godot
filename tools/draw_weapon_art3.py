#!/usr/bin/env python3
"""Third batch: the evolutions whose attack *is* an animated effect, which
were the base effect with a tint. Same rules as draw_weapon_art.py: every
pixel placed by hand, no antialiasing.

Usage: tools/draw_weapon_art3.py [OUT_DIR]   (default assets/sprites)"""
import math, os, random, sys
sys.path.insert(0, os.path.dirname(__file__))
import draw_weapon_art as A
from draw_weapon_art import hexc, new, put, rows, outline, disc, poly, line, thick, paste, sheet, CLEAR, Image

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
A.OUT = OUT

def dither_fade(im, keep, seed=0):
    """Drops pixels on an ordered pattern so `keep` (0..1) of them remain."""
    bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    for y in range(im.height):
        for x in range(im.width):
            if im.getpixel((x, y))[3] and (bayer[(y + seed) % 4][(x + seed) % 4] + 0.5) / 16 > keep:
                im.putpixel((x, y), CLEAR)
    return im

# ---------------------------------------------------------------- Bear Maul
def maul_slash():
    """Three deep crimson gashes torn top to bottom, then dripping and fading.
    32x32, 10 frames (played once across the lash; drawn twice side by side)."""
    hot, red, dark, deep = hexc("fff0e8"), hexc("ff3b3b"), hexc("b0102a"), hexc("5a0614")
    frames = []
    cols = [(7, 0), (15, 1), (23, 0)]
    for k in range(10):
        im = new(32, 32)
        grow = min(1.0, (k + 1) / 4.0)
        for j, (x0, lag) in enumerate(cols):
            g = max(0.0, min(1.0, grow - lag * 0.15))
            if g <= 0:
                continue
            top, bot = 3 + lag * 2, 3 + lag * 2 + int(24 * g)
            for y in range(top, bot + 1):
                t = (y - top) / 24.0
                x = x0 + int(round(math.sin(t * 2.2) * 2.5)) - int(t * 3)
                w = 1.6 * math.sin(min(1.0, t * 1.15) * math.pi) + 0.6
                for dx in range(-2, 3):
                    if abs(dx) <= w:
                        put(im, x + dx, y, dark if abs(dx) >= w - 0.6 else red)
                if y >= bot - 1 and k < 4:
                    put(im, x, y, hot)
                    put(im, x + 1, y, hot)
            # drips once the tear is open
            if k >= 4:
                for d in range(min(k - 3, 4)):
                    put(im, x0 - 2 + j % 2, 27 + d + lag, deep)
        outline(im, hexc("1a0206"))
        if k >= 7:
            dither_fade(im, 1.0 - (k - 6) * 0.25, seed=k)
        frames.append(im)
    return frames

# ---------------------------------------------------------------- Thunderstorm
def storm_strike():
    """A storm cloud gathers, a thick bolt splits the sky, sparks scatter.
    32x128, 9 frames, bottom-anchored like the original lightning."""
    cl, cl2, cl3 = hexc("9aa8c8"), hexc("5f6c90"), hexc("343c58")
    core, glow, glow2 = hexc("ffffff"), hexc("bfe6ff"), hexc("6fb8ff")
    rng = random.Random(7)
    # one bolt path, reused so the bolt stays put while it flashes
    pts, x = [], 16.0
    for y in range(14, 124, 8):
        pts.append((x, y))
        x = max(6.0, min(26.0, x + rng.choice([-5, -3, 3, 5])))
    pts.append((16, 124))
    branches = [[pts[3], (pts[3][0] - 8, pts[3][1] + 10), (pts[3][0] - 11, pts[3][1] + 20)],
                [pts[7], (pts[7][0] + 7, pts[7][1] + 9)]]
    frames = []
    for k in range(9):
        im = new(32, 128)
        size = min(1.0, (k + 1) / 3.0) if k < 7 else 1.0 - (k - 6) * 0.35
        for (cx, cy, r) in [(9, 8, 6), (16, 5, 7), (23, 8, 6), (16, 10, 6)]:
            disc(im, cx, cy, r * size, cl2)
        for (cx, cy, r) in [(9, 6, 3.5), (16, 3, 4.5), (23, 6, 3.5)]:
            disc(im, cx, cy, r * size, cl)
        for xx in range(32):
            for yy in range(11, 16):
                if im.getpixel((xx, yy))[3]:
                    put(im, xx, yy, cl3)
        if 3 <= k <= 6:
            for path in [pts] + (branches if k in (3, 4) else []):
                for a, b in zip(path, path[1:]):
                    thick(im, *a, *b, 1.8 if k == 4 else 1.2, glow2)
                    thick(im, *a, *b, 0.8, glow)
                    line(im, *a, *b, core)
            # ground flash
            for xx in range(4, 29):
                h = 4 - abs(xx - 16) * 0.25
                for yy in range(int(124 - h), 128):
                    if (xx + yy + k) % 2 == 0:
                        put(im, xx, yy, glow if abs(xx - 16) < 5 else glow2)
        if k >= 7:
            for s in range(6):
                put(im, 16 + rng.randint(-10, 10), 112 + rng.randint(0, 14), glow)
        outline(im, hexc("10142a"))
        frames.append(im)
    return frames

# ---------------------------------------------------------------- Necromancer's Grip
def bone_hand():
    """A skeletal hand bursts from a green-lit grave, grabs, and sinks.
    48x48, 6 frames, bottom-anchored."""
    bone, bone2, bone3 = hexc("f2ecda"), hexc("c4b99c"), hexc("7d735c")
    dirt, dirt2, magic, magic2 = hexc("4a3424"), hexc("2a1c12"), hexc("8bff9a"), hexc("2fd36b")
    rise = [0.0, 0.45, 0.85, 1.0, 1.0, 0.5]
    curl = [0.0, 0.0, 0.1, 0.2, 1.0, 1.0]
    frames = []
    for k in range(6):
        im = new(48, 48)
        # magic glow ring on the ground
        for xx in range(48):
            for yy in range(36, 48):
                d = ((xx + 0.5 - 24) / 20) ** 2 + ((yy + 0.5 - 42) / 5) ** 2
                if 0.7 < d < 1.0 and (xx + k) % 2 == 0:
                    put(im, xx, yy, magic if k in (2, 3, 4) else magic2)
        r = rise[k]
        base = 41
        top = base - 30 * r
        if r > 0:
            # forearm: two bones
            thick(im, 22, base, 22, top + 12, 1.6, bone2)
            thick(im, 26, base, 26, top + 12, 1.4, bone3)
            # palm
            disc(im, 24, top + 10, 5.5, bone)
            disc(im, 25, top + 11, 3, bone2)
            # four fingers + thumb, curling in when it grabs
            c = curl[k]
            for i, fx in enumerate([17, 21, 26, 31]):
                tip_x = fx + (24 - fx) * c * 0.6
                tip_y = top - 2 + abs(i - 1.5) * 1.5 + c * 8
                thick(im, (fx + 24) / 2, top + 6, tip_x, tip_y, 1.0, bone)
                put(im, tip_x, tip_y, bone3)
                put(im, (fx + 24) / 2 + (tip_x - (fx + 24) / 2) * 0.5, top + 2 + c * 3, bone3)
            thick(im, 19, top + 12, 13 + c * 7, top + 7 + c * 3, 1.0, bone)
        # dirt mound torn open
        for xx in range(12, 37):
            h = 4 - abs(xx - 24) * 0.3 + (1 if (xx * 7) % 3 == 0 else 0)
            for yy in range(int(base - h + 2), base + 3):
                put(im, xx, yy, dirt if yy < base else dirt2)
        for (dx, dy) in [(-15, -4), (14, -6), (-11, -9), (17, -2)]:
            if 1 <= k <= 3:
                put(im, 24 + dx, base + dy - k, dirt)
        outline(im, hexc("0a0806"))
        if k == 5:
            dither_fade(im, 0.6, seed=1)
        frames.append(im)
    return frames

# ---------------------------------------------------------------- Eldritch Horror
def eldritch_rift():
    """A rift tears open; a violet tentacle covered in eyes lashes up out of
    it and pulls back. 64x64, 10 frames, bottom-anchored."""
    skin, skin2, skin3 = hexc("9a5ad8"), hexc("6a2fa8"), hexc("3a1466")
    eye_w, eye_r, rift, rift2 = hexc("f8f4e8"), hexc("ff2a4a"), hexc("12041e"), hexc("c38bff")
    ext = [0.0, 0.25, 0.55, 0.85, 1.0, 1.0, 0.9, 0.6, 0.3, 0.0]
    whip = [0, 0, 0.1, 0.3, 0.7, 1.0, 0.6, 0.3, 0.1, 0]
    frames = []
    for k in range(10):
        im = new(64, 64)
        open_w = [6, 14, 20, 22, 22, 22, 22, 20, 14, 6][k]
        for xx in range(64):
            for yy in range(52, 64):
                d = ((xx + 0.5 - 32) / max(open_w, 1)) ** 2 + ((yy + 0.5 - 58) / 4) ** 2
                if d < 1:
                    put(im, xx, yy, rift2 if d > 0.6 else rift)
        e = ext[k]
        n = int(46 * e)
        pts = []
        for i in range(n):
            t = i / 46.0
            x = 32 + math.sin(t * 3.3 + whip[k] * 1.8) * (6 + 12 * t) * (0.4 + whip[k])
            y = 56 - i
            pts.append((x, y, 5.2 - t * 4.0))
        for (x, y, w) in pts:
            disc(im, x, y, w, skin2)
        for (x, y, w) in pts:
            disc(im, x - w * 0.35, y, max(0.6, w * 0.45), skin)
        for (x, y, w) in pts[::7]:
            put(im, x + w * 0.6, y, skin3)
        for i in range(6, n, 11):
            x, y, w = pts[i]
            if w > 2.5:
                disc(im, x, y, 2.2, eye_w)
                put(im, x, y, eye_r)
                put(im, x + 1, y, eye_r)
        outline(im, hexc("0a0212"))
        frames.append(im)
    return frames

# ---------------------------------------------------------------- Haunted Boulevard
def haunted_lamp():
    """The street lamp, haunted: cyan ghost-fire in the glass and a little
    ghost circling the top. 16x64, 4 frames (same frame as street_lamp)."""
    iron, iron2, iron3 = hexc("2a2e3c"), hexc("4a5068"), hexc("15171f")
    f0, f1, f2 = hexc("e8ffff"), hexc("7ff3ff"), hexc("21b5d1")
    gb, gs, ge = hexc("e8f0ff"), hexc("9fb0d8"), hexc("1a1430")
    frames = []
    for k in range(4):
        im = new(16, 64)
        # post
        for yy in range(16, 60):
            put(im, 7, yy, iron2); put(im, 8, yy, iron)
        rows(im, 5, 58, ["iiiiii", "IIIIII"], {"i": iron, "I": iron3})
        rows(im, 6, 30, ["iiii"], {"i": iron})
        # lantern head
        rows(im, 3, 5, ["..iiiiii..", ".iiiiiiii.", "iiiiiiiiii"], {"i": iron})
        for yy in range(8, 15):
            for xx in range(4, 12):
                put(im, xx, yy, iron if xx in (4, 11) else hexc("0f3a44"))
        flick = [0, 1, 0, -1][k]
        for yy in range(9, 15):
            w = (yy - 8) * 0.55
            for xx in range(5, 11):
                if abs(xx + 0.5 - 8 - flick * 0.3 * (14 - yy) / 6) < w:
                    put(im, xx, yy, f0 if yy > 12 and abs(xx - 8) < 1 else f1 if w - abs(xx + 0.5 - 8) > 0.8 else f2)
        rows(im, 4, 15, ["iiiiiiii"], {"i": iron})
        # glow specks
        for (dx, dy) in [(-6, 10), (7, 9), (-5, 14), (6, 15)]:
            if (dx + dy + k) % 2 == 0:
                put(im, 8 + dx, dy, f1)
        # tiny ghost circling the head
        ang = k * math.pi / 2
        gx, gy = 8 + math.cos(ang) * 6 - 2, 2 + math.sin(ang) * 2
        rows(im, gx, gy, [".bb.", "beeb", "bbbs", "b.b."], {"b": gb, "s": gs, "e": ge})
        frames.append(im)
    return frames

# ---------------------------------------------------------------- Top Hat Tornado
def tornado_hat():
    """The merchant's hat spinning on a little twister. 32x32, 4 frames (the
    game draws it at half size)."""
    hat, hat2, hat3, band, coin = hexc("4a4ea8"), hexc("6a70d0"), hexc("2a2c66"), hexc("c4c9e8"), hexc("e8c84a")
    w1, w2, w3 = hexc("f2f6ff"), hexc("b8c4d8"), hexc("7d8aa8")
    frames = []
    for k in range(4):
        im = new(32, 32)
        for yy in range(14, 31):
            t = (yy - 14) / 16.0
            half = 7 - t * 5
            off = math.sin(yy * 0.5 + k * math.pi / 2) * 2
            for xx in range(32):
                u = xx + 0.5 - 16 - off
                if abs(u) < half:
                    band_i = int((u / half + 1) * 3 + yy * 0.6 + k) % 3
                    put(im, xx, yy, [w1, w2, w3][band_i])
        # the hat, tilting as it spins
        tilt = [0, 1, 0, -1][k]
        for yy in range(2, 11):
            for xx in range(10 + tilt, 22 + tilt):
                put(im, xx, yy, hat2 if xx < 13 + tilt else hat3 if xx > 19 + tilt else hat)
        for xx in range(10 + tilt, 22 + tilt):
            put(im, xx, 8, band)
        rows(im, 15 + tilt, 4, ["cc", "cc"], {"c": coin})
        for xx in range(6 + tilt, 26 + tilt):
            put(im, xx, 11, hat3 if xx in (6 + tilt, 25 + tilt) else hat)
            put(im, xx, 12, hat3)
        outline(im, hexc("0a0b18"))
        frames.append(im)
    return frames

# ---------------------------------------------------------------- Night Parade
def spirit_bat():
    """A spectral bat from the night parade: pale cyan, glowing eyes, a wispy
    tail. 32x32, 4 frames (drawn at half size)."""
    body, body2, wing, wing2, eye, tail = hexc("d8f6ff"), hexc("8fd8f0"), hexc("5ab0d8"), hexc("2f7aa8"), hexc("ffe14a"), hexc("8fd8f0", 150)
    frames = []
    for k in range(4):
        im = new(32, 32)
        lift = [0, -4, -6, -3][k]
        for i in range(8):  # wispy tail trailing down
            put(im, 16 + math.sin(i * 0.9 + k) * 1.5, 20 + i, tail)
        for side in (-1, 1):
            for i in range(13):
                x = 16 + side * (3 + i)
                yy = 15 + lift * (i / 12.0) + (i * i) * 0.02
                h = 6 - i * 0.35
                for y in range(int(yy - 1), int(yy + h)):
                    put(im, x, y, wing if (i % 4) else wing2)
        disc(im, 16, 16, 5, body2)
        disc(im, 16, 12, 3.6, body)
        put(im, 13, 8, body); put(im, 19, 8, body)
        put(im, 14, 12, eye); put(im, 18, 12, eye)
        outline(im, hexc("06182a"))
        frames.append(im)
    return frames

if __name__ == "__main__":
    A.save(sheet(maul_slash()), "maul_slash")
    A.save(sheet(storm_strike()), "storm_strike")
    A.save(sheet(bone_hand()), "bone_hand")
    A.save(sheet(eldritch_rift()), "eldritch_rift")
    A.save(sheet(haunted_lamp()), "haunted_lamp")
    A.save(sheet(tornado_hat()), "tornado_hat")
    A.save(sheet(spirit_bat()), "spirit_bat")
