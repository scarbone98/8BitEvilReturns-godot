#!/usr/bin/env python3
"""Second batch of weapon art (see draw_weapon_art.py for the helpers and
style): skill cards for the base weapons that used a bare sprite as their
icon, and own icons/shots for the evolutions and unions that were recolours.

Usage: tools/draw_weapon_art2.py [OUT_DIR]   (default assets/sprites)"""
import math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import draw_weapon_art as A
from draw_weapon_art import (hexc, new, put, rows, outline, disc, poly, line, thick, paste, sheet,
                             card, item_on_card, CLEAR, Image)

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
A.OUT = OUT
SRC = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")

def save(im, name):
    A.save(im, name)

def frame(path, frames, i=0):
    im = Image.open(os.path.join(SRC, path + ".png")).convert("RGBA")
    w = im.width // frames
    return im.crop((i * w, 0, i * w + w, im.height))

def fit(item, box=46):
    """Crop to content and scale by the largest whole number that fits `box`."""
    item = item.crop(item.getbbox())
    big = max(item.width, item.height)
    if big > box:
        d = -(-big // box)  # shrink by a whole factor
        return item.resize((item.width // d, item.height // d), Image.NEAREST)
    k = max(1, box // big)
    return item.resize((item.width * k, item.height * k), Image.NEAREST) if k > 1 else item

def on_card(item, colors, dark, box=46, outline_it=True, at=None):
    c = card(*colors)
    it = fit(item, box)
    if outline_it:
        big = new(it.width + 2, it.height + 2)
        paste(big, it, 1, 1)
        it = outline(big, dark)
    x, y = at if at else (32 - it.width // 2, 32 - it.height // 2)
    paste(c, it, x, y)
    return c

def compose(*layers, size=64):
    im = new(size, size)
    for img, x, y in layers:
        paste(im, img, x, y)
    return im

def scaled(img, k):
    return img.resize((img.width * k, img.height * k), Image.NEAREST)

# ---------------------------------------------------------------- motifs

def flames(im, cx, base_y, width, height, pal, seed=0):
    """Upward tongues of fire across `width`, bottom at base_y."""
    c0, c1, c2, c3 = pal
    for x in range(int(cx - width / 2), int(cx + width / 2) + 1):
        u = (x - cx) / (width / 2)
        h = height * (1 - u * u) * (0.75 + 0.25 * math.sin(x * 1.7 + seed))
        for y in range(int(base_y - h), int(base_y) + 1):
            t = (base_y - y) / max(h, 1)
            c = c0 if t < 0.25 and abs(u) < 0.5 else c1 if t < 0.5 else c2 if t < 0.8 else c3
            put(im, x, y, c)

FIRE = (hexc("fff3b0"), hexc("ffb238"), hexc("f0571e"), hexc("8c1a16"))
GREEN_FIRE = (hexc("e6ffcf"), hexc("8bff6a"), hexc("2fd36b"), hexc("0d6b38"))
PURPLE_FIRE = (hexc("f3e2ff"), hexc("c38bff"), hexc("8a3df0"), hexc("3d1270"))

def ghost(im, x, y, body=hexc("dfe8ff"), shade=hexc("9fb0d8"), eye=hexc("1a1430")):
    rows(im, x, y, [
        "..bbbb..",
        ".bbbbbb.",
        "bbebbebb",
        "bbebbebb",
        "bbbbbbbs",
        "bbbbbbbs",
        "bbbbbbss",
        "b.bb.bb.",
    ], {"b": body, "s": shade, "e": eye})

def bat_shape(im, x, y, body, wing, eye):
    rows(im, x, y, [
        "w.......k.k.......w",
        "ww......kkk......ww",
        "www....kkkkk....www",
        "wwwww.kkekekk.wwwww",
        ".wwwwwkkkkkkkwwwww.",
        "..wwwwwkkkkkwwwww..",
        "...ww.w.kkk.w.ww...",
        "........k.k........",
    ], {"w": wing, "k": body, "e": eye})

# ---------------------------------------------------------------- shots

def vampire_bat():
    # 32x32, 4 frames of wing flaps; red eyes and fangs (the game draws it at half size).
    body, wing, wing2, eye, fang = hexc("2a0d1a"), hexc("5c1030"), hexc("8a1a3e"), hexc("ff3b3b"), hexc("ffffff")
    frames = []
    for k in range(4):
        im = new(32, 32)
        lift = [0, -4, -6, -3][k]
        for side in (-1, 1):
            for i in range(13):
                x = 16 + side * (3 + i)
                yy = 15 + lift * (i / 12.0) + (i * i) * 0.02
                h = 6 - i * 0.35
                for y in range(int(yy - 1), int(yy + h)):
                    put(im, x, y, wing if (i % 4) else wing2)
            # wing finger tips
            put(im, 16 + side * 15, 15 + lift - 1, wing2)
        disc(im, 16, 16, 5, body)
        disc(im, 16, 12, 3.6, body)
        put(im, 13, 8, body); put(im, 19, 8, body)
        put(im, 14, 12, eye); put(im, 18, 12, eye)
        put(im, 15, 15, fang); put(im, 17, 15, fang)
        outline(im, hexc("0c0308"))
        frames.append(im)
    return frames

def ghost_lantern_orb():
    # A little iron lantern with a cyan ghost flame. 16x16, 4 frames.
    iron, iron2, glass, f0, f1, f2 = hexc("3a3f4c"), hexc("6d7486"), hexc("1d4a5a"), hexc("e8ffff"), hexc("7ff3ff"), hexc("21b5d1")
    frames = []
    for k in range(4):
        im = new(16, 16)
        rows(im, 4, 0, ["..ii..", ".i..i.", "iiiiii"], {"i": iron2})
        for y in range(3, 13):
            for x in range(4, 12):
                put(im, x, y, iron if x in (4, 11) or y in (3, 12) else glass)
        sway = [0, 1, 0, -1][k]
        flames(im, 8 + sway * 0.5, 11, 5, 6 + (k % 2), (f0, f1, f2, f2), seed=k)
        rows(im, 4, 13, ["iiiiii", ".iiii."], {"i": iron2})
        outline(im, hexc("0a0d12"))
        frames.append(im)
    return frames

def toxic_barrel():
    # A leaking toxic barrel with a skull label. 16x16 (the game spins it).
    im = new(16, 16)
    m, l, d, g, g2 = hexc("3d6b2a"), hexc("6ea84a"), hexc("1f3a16"), hexc("b8ff3a"), hexc("6fe01f")
    for y in range(2, 15):
        for x in range(3, 13):
            c = l if x < 6 else d if x > 10 else m
            if y in (4, 11):
                c = d
            put(im, x, y, c)
    rows(im, 6, 6, ["yyyy", "ykky", "yyyy", ".yy."], {"y": hexc("f5e14a"), "k": hexc("1b1b10")})
    rows(im, 4, 0, ["gggggg", ".g..g."], {"g": g})
    rows(im, 12, 13, ["g.", "gg", ".g"], {"g": g2})
    outline(im, hexc("0b1406"))
    return im

def jack_flame():
    # A jack-o-lantern on fire. 16x16, 4 frames.
    frames = []
    pump = frame("pumpkin", 6, 0)
    for k in range(4):
        im = new(16, 16)
        flames(im, 8, 9, 14, 8 + (k % 2) * 2, FIRE, seed=k * 1.3)
        paste(im, pump, 0, 1)
        frames.append(im)
    return frames

def gold_coin_spin():
    frames = []
    for f in A.coin_spin():
        g = new(f.width, f.height)
        for y in range(f.height):
            for x in range(f.width):
                r, gg, b, a = f.getpixel((x, y))
                if a == 0:
                    continue
                if (r, gg, b) == (179, 36, 58):  # keep the red eyes
                    g.putpixel((x, y), (r, gg, b, a)); continue
                lum = (r + gg + b) / 3 / 255
                g.putpixel((x, y), (int(70 + 185 * lum), int(40 + 170 * lum), int(10 + 60 * lum), a))
        frames.append(g)
    return frames

def storm_skull():
    # Skull Storm: a skull in purple storm-fire. 16x16, 4 frames.
    out = []
    for f in A.flame_skull():
        g = new(16, 16)
        for y in range(16):
            for x in range(16):
                c = f.getpixel((x, y))
                if c[3] == 0:
                    continue
                r, gg, b, a = c
                if gg > r + 30 and gg > b:  # the green flame -> violet
                    lum = gg / 255
                    c = (int(120 + 120 * lum), int(40 + 150 * lum * lum), 255, a)
                g.putpixel((x, y), c)
        out.append(g)
    return out

def lollipop():
    # A spinning swirl lollipop. 12x12, 4 frames.
    cols = [hexc("ff4d8d"), hexc("fff1f7"), hexc("7ad7ff"), hexc("fff1f7")]
    frames = []
    for k in range(4):
        im = new(12, 12)
        for y in range(12):
            for x in range(12):
                dx, dy = x + 0.5 - 6, y + 0.5 - 6
                d = math.hypot(dx, dy)
                if d < 5.2:
                    a = math.atan2(dy, dx) + d * 0.9 + k * math.pi / 2
                    put(im, x, y, cols[int((a / (2 * math.pi)) * 4) % 4])
        outline(im, hexc("4a0f2a"))
        frames.append(im)
    return frames

def silver_stake():
    im = A.wood_stake()
    rows(im, 1, 0, [".ss.", "sSSs", "sSSs"], {"s": hexc("f4f7fb"), "S": hexc("aeb7c6")})
    rows(im, 0, 7, ["osssSo"], {"o": hexc("2b1a10"), "s": hexc("f4f7fb"), "S": hexc("aeb7c6")})
    return im

def royale_rang():
    # Ricochet Royale: a golden boomerang with a coin set in the elbow. 16x16.
    im = new(16, 16)
    g, g2, g3 = hexc("ffe07a"), hexc("e0a83a"), hexc("8a5a12")
    thick(im, 2, 3, 10, 3, 1.6, g2)
    thick(im, 11, 4, 11, 13, 1.6, g2)
    line(im, 2, 2, 10, 2, g)
    line(im, 10, 5, 10, 13, g3)
    disc(im, 11, 3, 3.2, hexc("cfd5df"))
    disc(im, 10.5, 2.5, 1.6, hexc("ffffff"))
    outline(im, hexc("2a1806"))
    return im

# ---------------------------------------------------------------- cards

def base_cards():
    t = {}
    t["onion_ring_skill"] = on_card(frame("onion", 13, 0), (hexc("1a0a1c"), hexc("3d1640"), hexc("62225f")), hexc("0a030b"), box=62)
    t["heartbeat_skill"] = on_card(frame("heartbeat", 8, 0), (hexc("22050a"), hexc("4d0c16"), hexc("7a1424")), hexc("0d0204"))
    t["holy_cross_skill"] = on_card(frame("holy_cross", 10, 0), (hexc("221a05"), hexc("4d3a0c"), hexc("7a5e14")), hexc("0d0902"))
    t["pumpkin_bomb_skill"] = on_card(frame("pumpkin", 6, 0), (hexc("2a1304"), hexc("5a2a08"), hexc("8a4510")), hexc("120702"))
    t["grave_hand_skill"] = on_card(frame("hand", 4, 3), (hexc("0c1a12"), hexc("1d3a28"), hexc("2f5c40")), hexc("040a06"))
    t["tentacle_skill"] = on_card(frame("tentacle", 12, 6), (hexc("0a1418"), hexc("173238"), hexc("255058")), hexc("030709"), box=62)
    t["street_lamp_skill"] = on_card(frame("street_lamp", 4, 0), (hexc("0e0f1c"), hexc("22264a"), hexc("3a3f78")), hexc("05060c"), box=62)
    t["merchant_hat_skill"] = on_card(frame("merchant_hat", 1, 0), (hexc("0e1024"), hexc("232858"), hexc("363f88")), hexc("05060f"))
    # Blood Trail: drops falling into a spreading puddle
    it = new(64, 64)
    r1, r2, r3 = hexc("ff5a5a"), hexc("c0102a"), hexc("6a0716")
    for y in range(64):
        for x in range(64):
            dx, dy = (x + 0.5 - 30) / 22, (y + 0.5 - 46) / 8
            if dx * dx + dy * dy < 1:
                put(it, x, y, r2 if dy < 0.2 else r3)
    for (x, y, s) in [(30, 10, 1.0), (44, 22, 0.8), (18, 24, 0.7)]:
        disc(it, x, y + 6 * s, 4 * s, r2)
        poly(it, [(x - 3 * s, y + 5 * s), (x, y - 3 * s), (x + 3 * s, y + 5 * s)], r2)
        put(it, x - 1, y + 4 * s, r1)
    rows(it, 22, 42, ["rrr..", ".r..."], {"r": r1})
    t["blood_trail_skill"] = item_on_card(card(hexc("1c0406"), hexc("400a10"), hexc("661018")), it, hexc("0a0102"))
    return t

def evo_cards():
    t = {}
    # Bear Maul: a huge bear paw with bloody claws
    it = new(64, 64)
    fur, fur2, pad, claw = hexc("5a3a24"), hexc("8a5a36"), hexc("2a1a14"), hexc("f2ece0")
    disc(it, 32, 38, 15, fur); disc(it, 30, 36, 11, fur2); disc(it, 32, 40, 8, pad)
    for i, (x, y) in enumerate([(16, 22), (24, 15), (34, 13), (44, 18)]):
        disc(it, x, y, 5, fur); disc(it, x, y + 1, 3, pad)
        poly(it, [(x - 2, y - 4), (x + 2 - i % 2, y - 4), (x + 1, y - 11)], claw)
        put(it, x + 1, y - 10, hexc("c0102a")); put(it, x + 1, y - 9, hexc("c0102a"))
    t["bear_maul_skill"] = item_on_card(card(hexc("1f0606"), hexc("4a0e0e"), hexc("761616")), it, hexc("0a0202"))

    # Thunderstorm: a storm cloud raining lightning
    it = new(64, 64)
    cl, cl2, cl3 = hexc("cfd8ea"), hexc("8d9ab8"), hexc("4f5a78")
    for (x, y, r) in [(20, 22, 9), (32, 16, 11), (44, 22, 9), (28, 26, 9), (38, 27, 8)]:
        disc(it, x, y, r, cl2)
    for (x, y, r) in [(20, 20, 6), (31, 13, 7), (43, 20, 5)]:
        disc(it, x, y, r, cl)
    for x in range(10, 54):
        for y in range(28, 34):
            if it.getpixel((x, y))[3]:
                put(it, x, y, cl3)
    for path in [[(24, 34), (20, 42), (26, 43), (20, 56)], [(40, 34), (37, 44), (43, 45), (38, 58)]]:
        for a, b in zip(path, path[1:]):
            thick(it, *a, *b, 1.3, hexc("fff27a"))
            line(it, *a, *b, hexc("ffffff"))
    t["thunderstorm_skill"] = item_on_card(card(hexc("080c1e"), hexc("17204a"), hexc("26357a")), it, hexc("03040c"))

    # Toxic Flood: the barrel tipped over, flooding
    it = new(64, 64)
    paste(it, scaled(toxic_barrel(), 3), 6, 2)
    for y in range(64):
        for x in range(64):
            dx, dy = (x + 0.5 - 34) / 28, (y + 0.5 - 52) / 9
            if dx * dx + dy * dy < 1 and not it.getpixel((x, y))[3]:
                put(it, x, y, hexc("6fe01f") if dy < -0.2 else hexc("3a9a14"))
    for (x, y) in [(46, 44), (52, 48), (20, 48)]:
        disc(it, x, y, 2, hexc("d6ff7a"))
    t["toxic_flood_skill"] = item_on_card(card(hexc("0c1a06"), hexc("1f3a0e"), hexc("33601a")), it, hexc("040a02"))

    it = new(64, 64)
    vb = vampire_bat()
    paste(it, vb[2], 16, 4); paste(it, vb[0], 0, 26); paste(it, vb[1], 30, 30)
    t["vampire_swarm_skill"] = on_card(it, (hexc("1a040c"), hexc("40081c"), hexc("660e2c")), hexc("0a0105"), box=62)
    t["ghost_lantern_skill"] = on_card(ghost_lantern_orb()[1], (hexc("041418"), hexc("0b343c"), hexc("125560")), hexc("010608"))

    # Thriller Aura: zombie hands rising inside a green ring
    it = new(64, 64)
    for y in range(64):
        for x in range(64):
            d = math.hypot(x + 0.5 - 32, (y + 0.5 - 44) * 2.2)
            if 22 < d < 26:
                put(it, x, y, hexc("8bff6a"))
    hand = ["..g.g.g.", ".gg.g.gg", ".gggggg.", "gggggggg", ".gggggg.", "..gggg..", "..gggg..", "..gggg..", "..gggg..", "..gggg.."]
    hand_im = new(8, 10)
    rows(hand_im, 0, 0, [r.replace("g", "G") for r in hand], {"G": hexc("6c9a5a")})
    rows(hand_im, 1, 1, hand[:4], {"g": hexc("9cc98a")})
    for (x, y) in [(10, 14), (36, 8)]:
        paste(it, scaled(hand_im, 2), x, y)
    for x in range(10, 56):
        put(it, x, 44 + (x % 3 == 0), hexc("3a2a1a"))
        put(it, x, 45, hexc("3a2a1a"))
    t["thriller_aura_skill"] = item_on_card(card(hexc("0a1a08"), hexc("1c3a14"), hexc("2e6020")), it, hexc("030a02"))

    # Tell-Tale Heart: the heart beating under the floorboards
    it = new(64, 64)
    hb = fit(frame("heartbeat", 8, 3), 34)
    for y in range(36, 60):
        for x in range(6, 58):
            plank = (x // 13) % 2
            put(it, x, y, hexc("6a4428") if plank else hexc("7d5432"))
            if x % 13 == 0 or y in (36, 59):
                put(it, x, y, hexc("3a2414"))
    for x in range(20, 46):
        for y in range(36, 42):
            put(it, x, y, CLEAR)
    paste(it, hb, 32 - hb.width // 2, 28 - hb.height // 2)
    for (x, y) in [(12, 22), (52, 22)]:
        rows(it, x, y, ["r.r", ".r.", "r.r"], {"r": hexc("ff5a5a")})
    t["tell_tale_heart_skill"] = item_on_card(card(hexc("1c0606"), hexc("3f0c0c"), hexc("651414")), it, hexc("0a0202"))

    # Divine Judgment: the cross descending in a beam of light
    c = card(hexc("231a04"), hexc("4d3a0c"), hexc("806212"))
    for y in range(64):
        for x in range(64):
            w = 6 + y * 0.2
            if abs(x + 0.5 - 32) < w and (x + y) % 2 == 0 and c.getpixel((x, y))[3]:
                put(c, x, y, hexc("fff2a8"))
    cr = fit(frame("holy_cross", 10, 0), 46)
    big = new(cr.width + 2, cr.height + 2)
    paste(big, cr, 1, 1)
    cr = outline(big, hexc("0d0902"))
    paste(c, cr, 32 - cr.width // 2, 32 - cr.height // 2)
    t["divine_judgment_skill"] = c

    t["sugar_rush_skill"] = on_card(compose((scaled(lollipop()[0], 3), 14, 6), (scaled(A.candy_shot()[0], 2), 6, 44), (scaled(A.candy_shot()[1], 2), 34, 48)),
                                    (hexc("2a0820"), hexc("5a1046"), hexc("8a1a6c")), hexc("12030e"), box=56)
    t["jacks_inferno_skill"] = on_card(jack_flame()[1], (hexc("2a0d04"), hexc("5a1c08"), hexc("8a2c10")), hexc("120502"))

    # Jackpot: a pile of gold skull coins
    it = new(64, 64)
    gc = gold_coin_spin()[0]
    for (x, y) in [(8, 40), (20, 42), (32, 40), (44, 42), (14, 30), (28, 30), (40, 30), (22, 20), (34, 20), (28, 10)]:
        paste(it, scaled(gc, 1), x, y)
    t["jackpot_skill"] = on_card(it, (hexc("231a04"), hexc("4d3a0c"), hexc("806212")), hexc("0d0902"), box=60)

    it = new(48, 32)
    ss = storm_skull()
    paste(it, ss[0], 0, 14); paste(it, ss[2], 16, 4); paste(it, ss[1], 30, 14)
    t["skull_storm_skill"] = on_card(it, (hexc("12061f"), hexc("2c0f4a"), hexc("481a78")), hexc("05020a"), box=60)

    # Necromancer's Grip: a skeletal hand clawing up, green magic around it
    it = new(64, 64)
    bone, bone2 = hexc("efe8d6"), hexc("a89e86")
    for y in range(64):
        for x in range(64):
            d = math.hypot(x + 0.5 - 32, y + 0.5 - 30)
            if 20 < d < 23 and (x + y) % 2 == 0:
                put(it, x, y, hexc("6fe08a"))
    thick(it, 32, 58, 32, 40, 2.5, bone2)  # wrist
    disc(it, 32, 36, 7, bone)
    for i, (x, y) in enumerate([(20, 14), (27, 8), (35, 8), (42, 13)]):
        thick(it, 28 + i * 3, 32, x, y, 1.4, bone)
        disc(it, (28 + i * 3 + x) / 2, (32 + y) / 2, 1.8, bone2)
        put(it, x, y - 1, bone2)
    thick(it, 26, 38, 16, 32, 1.4, bone)  # thumb
    t["necromancers_grip_skill"] = item_on_card(card(hexc("061a0c"), hexc("0e3a1c"), hexc("16602c")), it, hexc("020a04"))

    # Eldritch Horror: one great eye with tentacles curling round it
    it = new(64, 64)
    for k, a in enumerate([0.3, 1.5, 2.6, 3.8, 5.0]):
        for t2 in range(30):
            r = 10 + t2 * 0.7
            ang = a + math.sin(t2 * 0.25 + k) * 0.5
            disc(it, 32 + math.cos(ang) * r, 32 + math.sin(ang) * r, 3.4 - t2 * 0.1, hexc("2f6a5a") if t2 % 6 else hexc("4a9a82"))
    disc(it, 32, 32, 11, hexc("f2ecd8"))
    disc(it, 33, 32, 6, hexc("c0102a"))
    disc(it, 33, 32, 3, hexc("120408"))
    put(it, 30, 29, hexc("ffffff")); put(it, 31, 29, hexc("ffffff"))
    t["eldritch_horror_skill"] = item_on_card(card(hexc("06121a"), hexc("0f2a3a"), hexc("184460")), it, hexc("02060a"))

    # Arc Reactor: a glowing ring core throwing arcs
    it = new(64, 64)
    for y in range(64):
        for x in range(64):
            d = math.hypot(x + 0.5 - 32, y + 0.5 - 32)
            if d < 15:
                put(it, x, y, hexc("ffffff") if d < 5 else hexc("b8f0ff") if d < 8 else hexc("3a3f4c") if d > 12 else hexc("4ac8ff"))
    for a in range(8):
        ang = a * math.pi / 4
        put(it, 32 + math.cos(ang) * 13.5, 32 + math.sin(ang) * 13.5, hexc("8a93a6"))
    for path in [[(44, 22), (50, 18), (49, 12), (56, 8)], [(20, 42), (14, 46), (16, 52), (8, 56)], [(46, 42), (52, 48), (58, 47)]]:
        for a2, b2 in zip(path, path[1:]):
            thick(it, *a2, *b2, 1.0, hexc("7ad7ff"))
            line(it, *a2, *b2, hexc("ffffff"))
    t["arc_reactor_skill"] = item_on_card(card(hexc("04101e"), hexc("0b2a4a"), hexc("12447a")), it, hexc("01050a"))

    # River of Blood: a wave of blood with a fang crest
    it = new(64, 64)
    for x in range(4, 60):
        top = 34 + math.sin(x * 0.22) * 6 - (8 if 22 < x < 40 else 0) * math.sin((x - 22) / 18 * math.pi)
        for y in range(int(top), 58):
            put(it, x, y, hexc("ff5a5a") if y < top + 2 else hexc("c0102a") if y < top + 9 else hexc("6a0716"))
    rows(it, 26, 22, ["w.....w", "ww...ww", ".w...w."], {"w": hexc("ffffff")})
    t["river_of_blood_skill"] = item_on_card(card(hexc("1c0406"), hexc("400a10"), hexc("661018")), it, hexc("0a0102"))

    # Haunted Boulevard: two lamps with a ghost between them
    it = new(64, 64)
    lamp = scaled(frame("street_lamp", 4, 1), 1)
    paste(it, lamp, 6, 0); paste(it, lamp, 42, 0)
    ghost(it, 26, 22)
    t["haunted_boulevard_skill"] = on_card(it, (hexc("0e0f1c"), hexc("22264a"), hexc("3a3f78")), hexc("05060c"), box=62)

    # Van Helsing: crossed silver stakes over a cross
    it = new(64, 64)
    st = scaled(silver_stake(), 3)
    a = st.rotate(-35, expand=True, resample=Image.NEAREST)
    b = st.rotate(35, expand=True, resample=Image.NEAREST)
    paste(it, a, 8, 2); paste(it, b, 22, 2)
    t["van_helsing_skill"] = on_card(it, (hexc("1a1206"), hexc("3a2a0e"), hexc("5e4416")), hexc("0a0702"), box=60)

    # Carpet Bombing: a bomber (side view) dropping a string of bombs
    it = new(64, 64)
    pl, pl2, pl3, glass = hexc("5a6070"), hexc("9aa3b6"), hexc("2c3038"), hexc("7ad7ff")
    for y in range(64):
        for x in range(64):
            dx, dy = (x + 0.5 - 30) / 24, (y + 0.5 - 14) / 5
            if dx * dx + dy * dy < 1:
                put(it, x, y, pl2 if dy < -0.3 else pl if dy < 0.5 else pl3)
    poly(it, [(8, 12), (4, 2), (10, 2), (16, 11)], pl)        # tail fin
    poly(it, [(6, 15), (16, 15), (14, 19), (4, 19)], pl3)     # tailplane
    poly(it, [(24, 14), (38, 14), (30, 26), (20, 26)], pl3)   # wing (near side)
    rows(it, 44, 10, ["ggg.", "gggg"], {"g": glass})             # cockpit
    thick(it, 55, 9, 55, 19, 0.7, hexc("cfd5df"))                # propeller blur
    rows(it, 26, 6, ["rrr", "rwr", "rrr"], {"r": hexc("b8352f"), "w": hexc("ffffff")})
    for i, (x, y) in enumerate([(22, 32), (28, 40), (34, 48), (40, 56)]):
        disc(it, x, y, 3, hexc("23262e"))
        put(it, x - 1, y - 1, hexc("8a93a6"))
        rows(it, x - 1, y - 6, ["rr", "r."], {"r": hexc("b8352f")})
    t["carpet_bombing_skill"] = item_on_card(card(hexc("2b1405"), hexc("5a2c0b"), hexc("8a4510")), it, hexc("120803"))

    # Top Hat Tornado: the hat spinning on a tornado
    it = new(64, 64)
    for y in range(20, 62):
        w = 4 + (62 - y) * 0.45
        off = math.sin(y * 0.35) * 3
        for x in range(int(32 + off - w), int(32 + off + w)):
            if (x + y * 2) % 7 < 5:
                put(it, x, y, hexc("b8c4d8") if (x + y) % 3 else hexc("e8eef8"))
    hat = fit(frame("merchant_hat", 1, 0), 28)
    paste(it, hat, 32 - hat.width // 2, 2)
    t["top_hat_tornado_skill"] = item_on_card(card(hexc("0e1024"), hexc("232858"), hexc("363f88")), it, hexc("05060f"))

    it = new(64, 64)
    g, g2, g3 = hexc("ffe07a"), hexc("e0a83a"), hexc("8a5a12")
    thick(it, 10, 22, 34, 14, 4.2, g2)
    thick(it, 34, 14, 52, 34, 4.2, g2)
    thick(it, 10, 20, 33, 12, 1.5, g)
    thick(it, 36, 18, 53, 37, 1.2, g3)
    for (x, y) in [(18, 18), (44, 26)]:
        thick(it, x - 2, y - 3, x + 2, y + 3, 1.0, hexc("b8352f"))
    disc(it, 34, 16, 7, hexc("cfd5df")); disc(it, 33, 15, 4.5, hexc("f4f7fb"))
    rows(it, 31, 13, ["kkkk", "kekk", "kkkk"], {"k": hexc("454b59"), "e": hexc("c22a43")})
    for (x, y) in [(12, 40), (24, 48), (40, 50)]:
        paste(it, A.coin_spin()[(x // 12) % 6], x, y)
    t["ricochet_royale_skill"] = item_on_card(card(hexc("231a04"), hexc("4d3a0c"), hexc("806212")), it, hexc("0d0902"))

    # Chain Lightning: one bolt jumping between three skulls
    it = new(64, 64)
    pts = [(10, 46), (30, 20), (52, 40)]
    for p0, p1 in zip(pts, pts[1:]):
        mx, my = (p0[0] + p1[0]) / 2 + 5, (p0[1] + p1[1]) / 2 + 4
        for a2, b2 in [(p0, (mx, my)), ((mx, my), p1)]:
            thick(it, *a2, *b2, 1.4, hexc("ffd23a"))
            line(it, *a2, *b2, hexc("fff8d0"))
    for (x, y) in pts:
        rows(it, x - 4, y - 4, [".bbbbbb.", "bbbbbbbb", "bkkbbkkb", "bkkbbkkb", "bbbbbbbb", ".bbkkbb.", ".b.b.b.."],
             {"b": hexc("eef3ff"), "k": hexc("1a2448")})
    t["chain_lightning_skill"] = item_on_card(card(hexc("1a1404"), hexc("3d300a"), hexc("665010")), it, hexc("0a0802"))

    # Night Parade: a bat, a wisp and a ghost marching
    it = new(64, 64)
    bat = vampire_bat()[1]
    paste(it, bat, 0, 2)
    ghost(it, 36, 14)
    wisp = frame("willOWisp", 6, 0).resize((24, 24), Image.NEAREST)
    paste(it, wisp, 22, 34)
    t["night_parade_skill"] = on_card(it, (hexc("0a0614"), hexc("1f1240"), hexc("2e1c66")), hexc("030208"), box=62)
    return t

if __name__ == "__main__":
    save(sheet(vampire_bat()), "vampire_bat")
    save(sheet(ghost_lantern_orb()), "ghost_lantern_orb")
    save(toxic_barrel(), "toxic_barrel")
    save(sheet(jack_flame()), "jack_flame")
    save(sheet(gold_coin_spin()), "gold_coin_spin")
    save(sheet(storm_skull()), "storm_skull")
    save(sheet(lollipop()), "lollipop")
    save(silver_stake(), "silver_stake")
    save(royale_rang(), "royale_rang")
    for name, im in {**base_cards(), **evo_cards()}.items():
        save(im, name)
