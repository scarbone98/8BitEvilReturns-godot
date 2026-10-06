#!/usr/bin/env python3
"""Stationary shooting monsters and their slow shots, drawn pixel by pixel
in the style of the original monster sheets (soft shading, dark outline).

Monsters: 24x24, 4-frame idle strips, feet on the bottom rows, facing right.
Shots: 8x8 strips.

Usage: tools/draw_monsters.py [OUT_DIR]   (default assets/sprites)"""
import math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import draw_weapon_art as A
from draw_weapon_art import hexc, new, put, rows, outline, disc, poly, line, thick, paste, sheet, CLEAR, Image

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
A.OUT = OUT
OL = hexc("120a14")

def shade_disc(im, cx, cy, r, pal):
    l, m, d = pal
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            if dx * dx + dy * dy <= r * r:
                lit = -(dx + dy) / (r * 1.4)
                put(im, x, y, l if lit > 0.35 else d if lit < -0.45 else m)

# ---------------------------------------------------------------- Evil Eye
def eye_stalk():
    """An eyeball on a fleshy stalk rooted in the ground; the pupil darts
    about and the stalk sways."""
    flesh = (hexc("d88aa8"), hexc("a8507a"), hexc("6e2a50"))
    white = (hexc("ffffff"), hexc("e8e0e8"), hexc("b8a8c0"))
    frames = []
    for k in range(4):
        im = new(24, 24)
        sway = [0, 1, 0, -1][k]
        # roots / mound
        for x in range(6, 18):
            put(im, x, 23, flesh[2]); put(im, x, 22, flesh[1] if 8 < x < 16 else flesh[2])
        # stalk
        for y in range(12, 22):
            x = 12 + round(sway * (22 - y) / 10)
            put(im, x - 1, y, flesh[0]); put(im, x, y, flesh[1]); put(im, x + 1, y, flesh[2])
        # eyeball
        cx = 12 + sway
        shade_disc(im, cx, 8, 6.2, white)
        for a in range(10):  # veins
            t = a * 0.63 + k * 0.1
            put(im, cx + math.cos(t) * 5, 8 + math.sin(t) * 5, hexc("d84a6a"))
        look = [(2, 0), (1, 1), (2, -1), (0, 0)][k]
        disc(im, cx + look[0], 8 + look[1], 3, hexc("7a3df0"))
        disc(im, cx + look[0], 8 + look[1], 1.6, hexc("12041e"))
        put(im, cx + look[0] - 1, 7 + look[1], hexc("ffffff"))
        outline(im, OL)
        frames.append(im)
    return frames

def orb_purple():
    frames = []
    for k in range(2):
        im = new(8, 8)
        disc(im, 4, 4, 3.2, hexc("8a3df0"))
        disc(im, 4, 4, 2.0, hexc("c38bff"))
        put(im, 3, 3, hexc("ffffff"))
        if k:
            for (x, y) in [(0, 4), (7, 3), (4, 0), (3, 7)]:
                put(im, x, y, hexc("c38bff"))
        frames.append(im)
    return frames

# ---------------------------------------------------------------- Pumpkin Patch
def gourd_spitter():
    """A jack-o'-lantern on a thorny vine, mouth glowing as it spits."""
    orange = (hexc("ffb046"), hexc("f07a1e"), hexc("a8480c"))
    vine, vine2 = hexc("5a8a2a"), hexc("3a5a1a")
    frames = []
    for k in range(4):
        im = new(24, 24)
        for x in range(3, 21):
            put(im, x, 23, vine2)
            if (x * 5 + k) % 4 == 0:
                put(im, x, 22, vine)
        for i in range(8):
            put(im, 11 + round(math.sin(i * 0.8 + k * 0.6)), 22 - i, vine)
            put(im, 12 + round(math.sin(i * 0.8 + k * 0.6)), 22 - i, vine2)
        squash = [0, 1, 0, -1][k]
        for y in range(4, 16):
            for x in range(3, 22):
                dx, dy = (x + 0.5 - 12) / (8.5 + squash * 0.3), (y + 0.5 - 10) / (6 - squash * 0.2)
                if dx * dx + dy * dy < 1:
                    put(im, x, y, orange[0] if dx < -0.4 and dy < 0 else orange[2] if dx > 0.5 or dy > 0.6 else orange[1])
        for x in (8, 16):
            line(im, x, 5, x, 15, orange[2])
        glow = [hexc("ffe14a"), hexc("fff2a8"), hexc("ffe14a"), hexc("ffb238")][k]
        rows(im, 7, 7, ["gg...gg", "g.....g"], {"g": glow})
        mouth = ["ggggggggg", ".g.ggg.g.", "..ggggg.."] if k in (1, 2) else ["ggggggggg", ".g.g.g.g."]
        rows(im, 8, 11, mouth, {"g": glow})
        rows(im, 11, 1, ["vv", ".v", ".v"], {"v": vine})
        outline(im, OL)
        frames.append(im)
    return frames

def seed_fire():
    frames = []
    for k in range(2):
        im = new(8, 8)
        disc(im, 4, 4, 2.6, hexc("f0571e"))
        disc(im, 4, 4, 1.4, hexc("ffe14a"))
        for (x, y) in ([(1, 4), (0, 3)] if k else [(1, 3), (0, 5)]):
            put(im, x, y, hexc("ffb238"))
        frames.append(im)
    return frames

# ---------------------------------------------------------------- Snowbound
def frost_totem():
    """A totem of carved ice with a scowling face; its eyes flare."""
    ice = (hexc("e8f8ff"), hexc("9fd8f0"), hexc("4a8ab8"))
    frames = []
    for k in range(4):
        im = new(24, 24)
        for y in range(2, 24):
            half = 6 if y > 4 else 4
            for x in range(12 - half, 12 + half):
                c = ice[0] if x < 9 else ice[2] if x > 15 else ice[1]
                if y in (9, 16):
                    c = ice[2]
                put(im, x, y, c)
        for (x, y) in [(5, 4), (18, 4), (12, 0)]:  # icy spikes on top
            line(im, x, y + 3, x, y, ice[0])
        eye = [hexc("7ff3ff"), hexc("ffffff"), hexc("7ff3ff"), hexc("21b5d1")][k]
        rows(im, 8, 11, ["ee..ee", "e....e"], {"e": eye})
        rows(im, 8, 6, ["kkk..kkk"], {"k": ice[2]})  # brow
        rows(im, 9, 18, ["kkkkkk", "k.kk.k"], {"k": hexc("21508a")})
        for x in range(4, 20):
            put(im, x, 23, hexc("ffffff"))
        outline(im, hexc("0a1e2e"))
        frames.append(im)
    return frames

def ice_shard():
    im = new(8, 8)
    poly(im, [(0, 3), (5, 2), (7, 4), (5, 5), (0, 4)], hexc("9fd8f0"))
    line(im, 1, 3, 6, 3, hexc("ffffff"))
    put(im, 7, 4, hexc("ffffff"))
    return [im]

# ---------------------------------------------------------------- Sewers
def sludge_toad():
    """A fat sewer toad half sunk in sludge, throat puffing before it spits."""
    skin = (hexc("8ac85a"), hexc("5a9a3a"), hexc("2f5a1e"))
    frames = []
    for k in range(4):
        im = new(24, 24)
        puff = [0, 1, 2, 0][k]
        for y in range(8, 21):
            for x in range(2, 22):
                dx, dy = (x + 0.5 - 12) / 9.5, (y + 0.5 - 15) / 6.5
                if dx * dx + dy * dy < 1:
                    put(im, x, y, skin[0] if dy < -0.4 and dx < 0.3 else skin[2] if dy > 0.5 else skin[1])
        for (x, y) in [(6, 12), (10, 10), (15, 13), (17, 11)]:  # warts
            put(im, x, y, skin[2])
        for cx in (8, 16):  # bulging eyes
            disc(im, cx, 8, 2.6, skin[1])
            disc(im, cx, 8, 1.6, hexc("ffe14a"))
            put(im, cx, 8, hexc("1a1a0a"))
        disc(im, 12, 17, 2 + puff, hexc("c8e88a"))  # throat sac
        line(im, 6, 15, 18, 15, skin[2])  # mouth
        for x in range(0, 24):  # sludge it sits in
            put(im, x, 21, hexc("6fa82a")); put(im, x, 22, hexc("4a7a14")); put(im, x, 23, hexc("2a4a0a"))
            if (x + k) % 5 == 0:
                put(im, x, 20, hexc("8ae02a"))
        outline(im, hexc("0c1406"))
        frames.append(im)
    return frames

def goo_glob():
    frames = []
    for k in range(2):
        im = new(8, 8)
        disc(im, 4, 4, 3 if k == 0 else 2.6, hexc("6fe01f"))
        disc(im, 3.5, 3.5, 1.5, hexc("c8ff4a"))
        put(im, 1, 6 - k, hexc("4a9a14"))
        frames.append(im)
    return frames

# ---------------------------------------------------------------- The Reaper
def reaper():
    """Death himself: a floating black-robed skeleton with a huge scythe,
    eyes burning, robe tatters drifting. 36x40, 4 frames (drawn at boss size)."""
    robe, robe2, robe3 = hexc("2a2236"), hexc("1a1424"), hexc("0c0812")
    bone, bone2 = hexc("efe8d6"), hexc("b8ae96")
    eye = hexc("ff3b3b")
    wood, blade, blade2 = hexc("5a3a24"), hexc("d8dde6"), hexc("8d96a8")
    frames = []
    for k in range(4):
        im = new(36, 40)
        bob = [0, -1, -2, -1][k]
        # scythe behind: a long shaft and a curved blade over his head
        line(im, 29, 38 + bob, 25, 3 + bob, wood)
        line(im, 30, 38 + bob, 26, 3 + bob, hexc("3a2414"))
        for i in range(18):
            t = i / 17.0
            x = 25 - t * 21
            y = 3 + bob + math.sin(t * math.pi) * -1 + t * t * 7
            put(im, x, y, blade); put(im, x, y + 1, blade); put(im, x + 1, y + 2, blade2)
        # robe: a hooded bell, tatters at the hem waving
        for y in range(4, 36):
            half = 5 + (y - 4) * 0.33 if y > 10 else 6 - abs(y - 7) * 0.3
            for x in range(int(17 - half), int(17 + half) + 1):
                c = robe if x < 15 else robe2
                if y > 30 and (x + y + k) % 3 == 0:
                    continue  # tatters
                put(im, x, y + bob, c)
        for x in range(9, 26, 2):  # ragged hem
            put(im, x, 36 + bob + (x + k) % 2, robe2)
        # hood opening and skull
        for y in range(6, 14):
            for x in range(13, 21):
                if (x + 0.5 - 17) ** 2 / 12 + (y + 0.5 - 10) ** 2 / 14 < 1:
                    put(im, x, y + bob, robe3)
        rows(im, 14, 8 + bob, [".bbbb.", "bebbeb", "bbbbbb", ".bmbm.", "..bb.."], {"b": bone, "e": eye, "m": bone2})
        # bony hand on the shaft
        rows(im, 25, 18 + bob, ["bb", "bb"], {"b": bone})
        line(im, 19, 17 + bob, 25, 19 + bob, robe2)
        # eye glow flicker
        if k % 2 == 0:
            put(im, 15, 9 + bob, hexc("ff7a3a")); put(im, 18, 9 + bob, hexc("ff7a3a"))
        outline(im, hexc("000000"))
        frames.append(im)
    return frames

# ---------------------------------------------------------------- Elite mark
def elite_mark():
    """Floats over Nightmare's elites: a little horned skull wreathed in red
    flame. 12x12, 4 flicker frames."""
    bone, bone2, eye = hexc("efe8d6"), hexc("b8ae96"), hexc("ff2a2a")
    horn = hexc("6a1a1a")
    flame = [hexc("ffd23a"), hexc("ff7a1a"), hexc("d81e1e"), hexc("7a0a14")]
    frames = []
    for k in range(4):
        im = new(12, 12)
        # flames licking up behind the skull, a different shape each frame
        tips = [[2, 0, 3, 1, 0, 2], [0, 2, 1, 3, 1, 0], [3, 1, 0, 2, 0, 1], [1, 3, 2, 0, 2, 3]][k]
        for i, t in enumerate(tips):
            x = 3 + i
            for y in range(t, 9):
                c = flame[3] if y > 6 else flame[2] if y > 4 else flame[1] if y > t + 1 else flame[0]
                put(im, x, y, c)
        put(im, 2, 5 + k % 2, flame[2]); put(im, 9, 6 - k % 2, flame[2])
        # horns and skull
        rows(im, 2, 3, ["h......h", "hh....hh"], {"h": horn})
        rows(im, 3, 4, [".bbbb.", "bbbbbb", "beebee", "bbbbbb", ".mbbm.", "..mm.."],
             {"b": bone, "e": eye, "m": bone2})
        if k % 2 == 0:
            put(im, 4, 6, hexc("ffb0a0")); put(im, 7, 6, hexc("ffb0a0"))
        outline(im, hexc("1a0408"))
        frames.append(im)
    return frames

if __name__ == "__main__":
    A.save(sheet(eye_stalk()), "eye_stalk")
    A.save(sheet(gourd_spitter()), "gourd_spitter")
    A.save(sheet(frost_totem()), "frost_totem")
    A.save(sheet(sludge_toad()), "sludge_toad")
    A.save(sheet(orb_purple()), "orb_purple")
    A.save(sheet(seed_fire()), "seed_fire")
    A.save(sheet(ice_shard()), "ice_shard")
    A.save(sheet(goo_glob()), "goo_glob")
    A.save(sheet(reaper()), "reaper")
    A.save(sheet(elite_mark()), "elite_mark")
