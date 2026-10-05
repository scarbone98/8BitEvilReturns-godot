#!/usr/bin/env python3
"""Map props ("structures"), drawn pixel by pixel to sit with the original
graves and mausoleum: soft 3-tone shading with a little noise, no black
outline, mossy/teal tufts at the base where it fits.

Every prop is drawn with its feet on the bottom row (the game anchors props
by their feet). Animated props are horizontal strips.

Usage: tools/draw_props.py [OUT_DIR]   (default assets/sprites)"""
import math, os, random, sys
sys.path.insert(0, os.path.dirname(__file__))
import draw_weapon_art as A
from draw_weapon_art import hexc, new, put, rows, disc, poly, line, thick, paste, sheet, CLEAR, Image

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
A.OUT = OUT

STONE = (hexc("8b93a6"), hexc("6b7286"), hexc("4e5466"), hexc("363a48"))   # light, mid, dark, edge
MOSS = (hexc("4fa783"), hexc("37946e"))
WOOD = (hexc("b07a44"), hexc("8a5a2e"), hexc("5e3a1c"), hexc("3a220e"))
HAY = (hexc("f2d27a"), hexc("d6a84a"), hexc("a8782a"), hexc("6e4a14"))
SNOW = (hexc("ffffff"), hexc("e4ecf8"), hexc("b8c6de"), hexc("8292b0"))
BRICK = (hexc("8a5a4a"), hexc("6e4234"), hexc("4e2c22"), hexc("2e1812"))
BONE = (hexc("f2ecda"), hexc("d4cab0"), hexc("a69c82"), hexc("6e6652"))
IRON = (hexc("6a6f7e"), hexc("4a4e5a"), hexc("30333c"), hexc("1c1e24"))

def shade_fill(im, mask_fn, w, h, pal, light_dir=(-1, -1), seed=0, noise=0.06):
    """Fills every (x, y) where mask_fn is true, lit from the top left, with a
    sprinkle of texture noise like the original stones."""
    l, m, d, e = pal
    rng = random.Random(seed)
    inside = [[mask_fn(x, y) for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            if not inside[y][x]:
                continue
            edge_l = x == 0 or not inside[y][x - 1]
            edge_t = y == 0 or not inside[y - 1][x]
            edge_r = x == w - 1 or not inside[y][x + 1]
            edge_b = y == h - 1 or not inside[y + 1][x]
            c = m
            if edge_l or edge_t:
                c = l
            elif edge_r or edge_b:
                c = d
            r = rng.random()
            if r < noise:
                c = l if c == m else m
            elif r < noise * 2:
                c = d if c == m else c
            put(im, x, y, c)
    # a darker rim on the bottom/right silhouette, like the originals
    for y in range(h):
        for x in range(w):
            if inside[y][x] and ((x == w - 1 or not inside[y][x + 1]) and (y == h - 1 or not inside[y + 1][x])):
                put(im, x, y, e)

def tufts(im, x0, x1, y, pal=MOSS, seed=1):
    rng = random.Random(seed)
    for x in range(x0, x1):
        if rng.random() < 0.6:
            h = rng.randint(1, 3)
            for k in range(h):
                put(im, x, y - k, pal[0] if k == h - 1 else pal[1])

def snow_cap(im, seed=2, depth=2):
    """Snow settles on every top-facing edge."""
    w, h = im.size
    src = im.copy()
    for x in range(w):
        for y in range(h):
            if src.getpixel((x, y))[3]:
                for k in range(depth + (1 if (x * 7 + seed) % 3 == 0 else 0)):
                    if y + k < h and src.getpixel((x, y + k))[3]:
                        put(im, x, y + k, SNOW[0] if k == 0 else SNOW[1])
                if y > 0 and (x + seed) % 4 == 0:
                    put(im, x, y - 1, SNOW[1])
                break

# ================================================================ Graveyard

def angel_statue():
    """A weeping angel on a plinth, face buried in her hands, wings folded
    behind. 28x52, rare."""
    w, h = 28, 52
    im = new(w, h)
    wing_pal = (hexc("7d8496"), hexc("626879"), hexc("4a4f5e"), hexc("343844"))
    # wings: two tall folded shapes behind the shoulders
    for side in (-1, 1):
        def wing(x, y, side=side):
            u = (x + 0.5 - 14) * side
            return 2 < u < 12 and 5 <= y < 38 and y > 5 + (12 - u) * 0.2 and y < 38 - (u - 2) * 1.4
        shade_fill(im, wing, w, h, wing_pal, seed=3 + side, noise=0.0)
        for f in range(3):
            line(im, 14 + side * (5 + f * 2), 9 + f * 2, 14 + side * (4 + f * 2), 30 - f * 3, wing_pal[2])
    def body(x, y):
        if 42 <= y < 52 and 3 <= x < 25:
            return True
        if 16 <= y < 42:
            return abs(x + 0.5 - 14) < 3.5 + (y - 16) * 0.2
        if 9 <= y < 17:
            return (x + 0.5 - 14) ** 2 / 10 + (y + 0.5 - 13) ** 2 / 14 < 1
        return False
    shade_fill(im, body, w, h, (hexc("a8afc0"), hexc("878ea0"), hexc("666c7e"), hexc("444856")), seed=4, noise=0.03)
    # hands over the face, elbows out
    rows(im, 10, 13, ["hhhhhhhh", ".hh..hh.", "..h..h.."], {"h": hexc("c4cad8")})
    line(im, 9, 15, 10, 19, hexc("878ea0")); line(im, 19, 15, 18, 19, hexc("878ea0"))
    # robe folds
    for x0 in (12, 16):
        line(im, x0, 21, x0 - (1 if x0 < 14 else -1) * 2, 41, hexc("666c7e"))
    line(im, 3, 42, 24, 42, hexc("a8afc0"))
    line(im, 4, 46, 23, 46, hexc("666c7e"))
    tufts(im, 2, 26, 51, seed=5)
    return im

def open_grave():
    """A freshly dug grave: a dark pit, a dirt heap and a shovel. 36x26."""
    w, h = 36, 26
    im = new(w, h)
    dirt = (hexc("6e5038"), hexc("553c28"), hexc("3e2c1c"), hexc("2a1d12"))
    shade_fill(im, lambda x, y: (x + 0.5 - 26) ** 2 / 90 + (y + 0.5 - 18) ** 2 / 40 < 1, w, h, dirt, seed=6)
    for y in range(12, 25):
        for x in range(3, 21):
            put(im, x, y, hexc("120c08") if 4 <= x < 20 and 13 <= y < 24 else dirt[2])
    line(im, 3, 12, 20, 12, dirt[0])
    for x in range(5, 19, 3):
        put(im, x, 14, hexc("2a1d12"))
    # the shovel stuck in the heap
    thick(im, 31, 2, 28, 14, 0.6, WOOD[1])
    poly(im, [(26, 13), (30, 13), (30, 18), (28, 20), (26, 18)], IRON[0])
    line(im, 26, 13, 26, 18, IRON[2])
    tufts(im, 0, 36, 25, seed=7)
    return im

# ================================================================ Crimson Crypt

def blood_fountain():
    """A stone fountain running with blood. 40x40, 4 frames."""
    w, h = 40, 40
    frames = []
    for k in range(4):
        im = new(w, h)
        # basin
        shade_fill(im, lambda x, y: 26 <= y < 38 and abs(x + 0.5 - 20) < 18 - max(0, y - 34) * 1.5, w, h, STONE, seed=8)
        # pillar and top bowl
        shade_fill(im, lambda x, y: (12 <= y < 28 and abs(x + 0.5 - 20) < 3) or (8 <= y < 13 and abs(x + 0.5 - 20) < 9 - (12 - y) * 0.4), w, h, STONE, seed=9)
        # blood in the basin, rippling
        for x in range(4, 36):
            put(im, x, 27 + ((x + k) % 4 == 0), hexc("c0102a"))
            put(im, x, 28, hexc("8a0a20"))
        # spilling over the top bowl in two arcs, splashing into the basin
        for side in (-1, 1):
            for i in range(18):
                t = i / 17.0
                x = 20 + side * (9 + t * 5)
                y = 9 + t * t * 17
                c = hexc("ff6a6a") if (i + k * 2) % 5 == 0 else hexc("e0283a")
                put(im, x, y, c); put(im, x + side, y, hexc("a3122f"))
            put(im, 20 + side * 14, 26 - (k % 2), hexc("ff9a9a"))
        for x in range(12, 29):
            put(im, x, 8, hexc("c0102a"))
        put(im, 20, 7 - (k % 2), hexc("ff6a6a"))
        tufts(im, 2, 38, 39, pal=(hexc("a3434f"), hexc("7a2a36")), seed=10)
        frames.append(im)
    return frames

def gibbet():
    """An iron cage hung from a post, a skeleton slumped inside. 30x52, rare."""
    w, h = 30, 52
    im = new(w, h)
    shade_fill(im, lambda x, y: 2 <= x < 6 and 2 <= y < 52, w, h, WOOD, seed=11)
    shade_fill(im, lambda x, y: 2 <= y < 6 and 2 <= x < 24, w, h, WOOD, seed=12)
    line(im, 21, 6, 21, 10, IRON[1])
    # cage: an iron bell of bars
    for x in range(12, 31, 3):
        pass
    cx = 21
    for i in range(-2, 3):
        for y in range(11, 34):
            half = 2 + (y - 11) * 0.28 if y < 20 else 4.5
            put(im, cx + i * half / 2, y, IRON[0] if i < 0 else IRON[1])
    for y in (11, 20, 33):
        line(im, cx - 5, y, cx + 5, y, IRON[2])
    # skeleton inside
    rows(im, 18, 14, [".bbb.", "bebeb", ".bbb.", "..b..", ".bbb.", "b.b.b", ".bbb.", "..b..", ".b.b.", ".b.b."],
         {"b": BONE[1], "e": hexc("2a1a14")})
    # ground
    tufts(im, 0, 12, 51, pal=(hexc("a3434f"), hexc("7a2a36")), seed=13)
    return im

def blood_obelisk():
    """A black obelisk with runes glowing red. 20x58, 4 frames, rare."""
    w, h = 20, 58
    frames = []
    glow = [hexc("ff3b3b"), hexc("ff6a5a"), hexc("ff9a7a"), hexc("ff6a5a")]
    for k in range(4):
        im = new(w, h)
        dark = (hexc("4a4458"), hexc("332e40"), hexc("221e2c"), hexc("16121e"))
        shade_fill(im, lambda x, y: (y >= 6 and abs(x + 0.5 - 10) < 3.5 + (y - 6) * 0.07) or (y < 6 and abs(x + 0.5 - 10) < y * 0.6), w, h, dark, seed=14)
        shade_fill(im, lambda x, y: 50 <= y < 58 and 1 <= x < 19, w, h, dark, seed=15)
        for i, y in enumerate(range(12, 46, 6)):
            rune = [["x.x", ".x.", "x.x"], [".x.", "xxx", ".x."], ["xx.", ".x.", ".xx"], ["x..", "xxx", "..x"]][i % 4]
            rows(im, 9, y, rune, {"x": glow[(k + i) % 4]})
        tufts(im, 0, 20, 57, pal=(hexc("a3434f"), hexc("7a2a36")), seed=16)
        frames.append(im)
    return frames

# ================================================================ Pumpkin Patch

def hay_bale():
    w, h = 32, 22
    im = new(w, h)
    shade_fill(im, lambda x, y: 2 <= y < 22 and 1 <= x < 31, w, h, HAY, seed=17, noise=0.25)
    for x in range(2, 31):
        for y in range(3, 21):
            if (x * 3 + y * 5) % 11 == 0:
                put(im, x, y, HAY[2])
    for x in (9, 22):
        line(im, x, 2, x, 21, hexc("8a2a1a"))
    for x in range(1, 31, 2):
        put(im, x, 1, HAY[0])
    return im

def pumpkin_pile():
    w, h = 32, 24
    im = new(w, h)
    orange = (hexc("ffb046"), hexc("f07a1e"), hexc("b8500c"), hexc("7a3006"))
    for (cx, cy, rx, ry) in [(9, 17, 8, 6), (23, 17, 8, 6), (16, 9, 7, 6)]:
        shade_fill(im, lambda x, y, cx=cx, cy=cy, rx=rx, ry=ry: (x + 0.5 - cx) ** 2 / rx ** 2 + (y + 0.5 - cy) ** 2 / ry ** 2 < 1, w, h, orange, seed=cx)
        for dx in (-3, 3):
            line(im, cx + dx, cy - ry + 2, cx + dx, cy + ry - 2, orange[2])
        rows(im, cx - 1, cy - ry - 2, ["gg", ".g"], {"g": hexc("4a7a2a")})
    # one is a jack-o'-lantern
    rows(im, 13, 7, ["y...y", "yy.yy", ".....", "yyyyy", ".y.y."], {"y": hexc("ffe14a")})
    tufts(im, 0, 32, 23, pal=(hexc("6a8a3a"), hexc("4a6a2a")), seed=18)
    return im

def corn_stalks():
    """A clump of dead corn. 26x44, rare-ish height."""
    w, h = 26, 44
    im = new(w, h)
    stalk, leaf, leaf2, cob = hexc("b8a05a"), hexc("8a7a3a"), hexc("6a5a2a"), hexc("f2c94a")
    rng = random.Random(19)
    for i, x0 in enumerate([5, 10, 15, 20]):
        top = 4 + rng.randint(0, 8)
        lean = rng.choice([-1, 0, 1])
        for y in range(top, 44):
            put(im, x0 + lean * (44 - y) // 18, y, stalk if i % 2 else leaf)
        for j in range(3):
            y = top + 6 + j * 9
            side = 1 if (i + j) % 2 else -1
            line(im, x0, y, x0 + side * 6, y + 4 + j, leaf2 if j % 2 else leaf)
        if i in (1, 2):
            rows(im, x0 + 1, top + 12, ["c", "c", "c", "k"], {"c": cob, "k": leaf2})
    tufts(im, 0, 26, 43, pal=(hexc("6a8a3a"), hexc("4a6a2a")), seed=20)
    return im

def wood_fence():
    w, h = 40, 24
    im = new(w, h)
    for x0 in (2, 18, 34):
        shade_fill(im, lambda x, y, x0=x0: x0 <= x < x0 + 4 and (2 + (x - x0 == 1 or x - x0 == 2) * -1) <= y < 24, w, h, WOOD, seed=x0)
    for y0 in (7, 15):
        shade_fill(im, lambda x, y, y0=y0: y0 <= y < y0 + 3 and 0 <= x < 40, w, h, WOOD, seed=y0)
    put(im, 25, 8, WOOD[3]); put(im, 9, 16, WOOD[3])
    tufts(im, 0, 40, 23, pal=(hexc("6a8a3a"), hexc("4a6a2a")), seed=21)
    return im

def scarecrow_post():
    """A ragged scarecrow on a cross post, pumpkin head. 30x56, rare."""
    w, h = 30, 56
    im = new(w, h)
    shade_fill(im, lambda x, y: 13 <= x < 17 and 8 <= y < 56, w, h, WOOD, seed=22)
    shade_fill(im, lambda x, y: 2 <= x < 28 and 16 <= y < 19, w, h, WOOD, seed=23)
    shirt = (hexc("8a4a6a"), hexc("6a3050"), hexc("4a1e38"), hexc("2e1022"))
    shade_fill(im, lambda x, y: (18 <= y < 34 and abs(x + 0.5 - 15) < 6 + (y - 18) * 0.15) or (17 <= y < 22 and 4 <= x < 26), w, h, shirt, seed=24, noise=0.2)
    for y in range(34, 38):  # tattered hem
        for x in range(9, 22):
            if (x + y) % 3:
                put(im, x, y, shirt[2])
    for (x, y) in [(3, 22), (26, 22), (12, 38), (18, 38)]:
        rows(im, x - 1, y, ["h.h", ".h."], {"h": HAY[1]})
    orange = (hexc("ffb046"), hexc("f07a1e"), hexc("b8500c"), hexc("7a3006"))
    shade_fill(im, lambda x, y: (x + 0.5 - 15) ** 2 / 36 + (y + 0.5 - 10) ** 2 / 25 < 1, w, h, orange, seed=25)
    rows(im, 12, 8, ["y.y", "...", "yyy"], {"y": hexc("ffe14a")})
    rows(im, 13, 4, ["gg"], {"g": hexc("4a7a2a")})
    # a hat
    rows(im, 9, 3, ["..kkkkkkk..", "kkkkkkkkkkkk"], {"k": hexc("3a2a1a")})
    tufts(im, 6, 24, 55, pal=(hexc("6a8a3a"), hexc("4a6a2a")), seed=26)
    return im

# ================================================================ Snowbound

def snow_pine():
    """A dark pine heavy with snow. 34x60, rare."""
    w, h = 34, 60
    im = new(w, h)
    pine = (hexc("2f5a4a"), hexc("214238"), hexc("162e28"), hexc("0e1e1a"))
    shade_fill(im, lambda x, y: 15 <= x < 19 and 50 <= y < 60, w, h, WOOD, seed=27)
    for tier, (top, bot, half) in enumerate([(2, 22, 8), (12, 36, 12), (24, 52, 16)]):
        shade_fill(im, lambda x, y, top=top, bot=bot, half=half: top <= y < bot and abs(x + 0.5 - 17) < (y - top + 1) / (bot - top) * half, w, h, pine, seed=28 + tier)
        for x in range(34):
            yb = bot - 1
            if abs(x + 0.5 - 17) < half:
                put(im, x, yb, SNOW[1] if x % 3 else SNOW[2])
    snow_cap(im, seed=3, depth=2)
    return im

def snowman():
    """A lopsided snowman with coal eyes and a stick grin. 24x32."""
    w, h = 24, 32
    im = new(w, h)
    for (cx, cy, r) in [(12, 24, 8), (12, 13, 6), (12, 5, 4.5)]:
        shade_fill(im, lambda x, y, cx=cx, cy=cy, r=r: (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 < r * r, w, h, SNOW, seed=cx + cy)
    rows(im, 10, 4, ["k.k", "...", "kkk"], {"k": hexc("1a1a22")})
    put(im, 12, 5, hexc("f07a1e")); put(im, 13, 5, hexc("f07a1e"))
    for y in (12, 15, 19):
        put(im, 12, y, hexc("1a1a22"))
    line(im, 6, 12, 1, 7, WOOD[2]); line(im, 18, 12, 23, 9, WOOD[2])
    rows(im, 7, 9, ["rrrrrrrrrr", "....rr...."], {"r": hexc("b8352f")})
    return im

def ice_grave():
    """The original cross grave, frozen in a block of ice with icicles. 32x34."""
    w, h = 32, 34
    im = new(w, h)
    g = Image.open(os.path.join(os.path.dirname(__file__), "..", "assets", "sprites", "grave_2.png")).convert("RGBA")
    paste(im, g, 0, 2)
    ice = hexc("bfe6ff", 130)
    for y in range(4, 34):
        for x in range(3, 29):
            if im.getpixel((x, y))[3] and (x + y) % 2 == 0:
                put(im, x, y, Image.alpha_composite(Image.new("RGBA", (1, 1), im.getpixel((x, y))), Image.new("RGBA", (1, 1), ice)).getpixel((0, 0)))
    snow_cap(im, seed=5, depth=2)
    for x in (8, 13, 19, 24):
        for k in range(2 + x % 3):
            put(im, x, 22 + k, hexc("e8f6ff"))
    # no moss under snow: cover the tufts
    for x in range(0, 32):
        for y in range(29, 34):
            if im.getpixel((x, y))[3]:
                r, gg, b, a = im.getpixel((x, y))
                if gg > r + 30:
                    put(im, x, y, SNOW[1] if (x + y) % 3 else SNOW[2])
    return im

def snow_angel_statue():
    im = angel_statue()
    snow_cap(im, seed=7, depth=2)
    for x in range(28):
        for y in range(46, 52):
            if im.getpixel((x, y))[3]:
                r, gg, b, a = im.getpixel((x, y))
                if gg > r + 30:
                    put(im, x, y, SNOW[1])
    return im

# ================================================================ Sewers

def sewer_pipe():
    """A brick wall section with a pipe pouring green ooze. 40x40, 4 frames."""
    w, h = 40, 40
    frames = []
    for k in range(4):
        im = new(w, h)
        shade_fill(im, lambda x, y: 2 <= y < 32 and 0 <= x < 40, w, h, BRICK, seed=30, noise=0.08)
        for y in range(2, 32):
            for x in range(40):
                if y % 5 == 1 or (x + (y // 5) * 4) % 9 == 0:
                    put(im, x, y, BRICK[2])
        disc(im, 20, 16, 7, IRON[1]); disc(im, 20, 16, 5, IRON[3]); disc(im, 19, 15, 6.5, IRON[0]) if False else None
        for a in range(12):
            t = a * math.pi / 6
            put(im, 20 + math.cos(t) * 6.5, 16 + math.sin(t) * 6.5, IRON[0])
        # ooze pouring out and pooling
        o1, o2, o3 = hexc("c8ff4a"), hexc("8ae02a"), hexc("4a9a14")
        for y in range(19, 38):
            wd = 2 if y < 30 else 2 + (y - 30)
            for x in range(20 - wd, 21 + wd):
                c = o1 if (y + k * 2) % 6 == 0 and abs(x - 20) < 2 else o2 if abs(x - 20) < wd - 0.5 else o3
                put(im, x, y, c)
        for x in range(10, 31):
            put(im, x, 38, o3)
            put(im, x, 39, hexc("2a5a0a"))
        put(im, 20 + (k % 3) - 1, 37 - k, o1)
        frames.append(im)
    return frames

def barrel_stack():
    w, h = 32, 30
    im = new(w, h)
    for (x0, y0) in [(1, 14), (16, 14), (8, 0)]:
        shade_fill(im, lambda x, y, x0=x0, y0=y0: x0 <= x < x0 + 15 and y0 <= y < y0 + 16 and not ((x == x0 or x == x0 + 14) and (y == y0 or y == y0 + 15)), w, h, WOOD, seed=x0 + y0)
        for yy in (y0 + 3, y0 + 12):
            line(im, x0, yy, x0 + 14, yy, IRON[1])
        rows(im, x0 + 5, y0 + 6, ["yyyy", "ykky", "yyyy"], {"y": hexc("e0c03a"), "k": hexc("2a2a1a")})
    return im

def brick_pillar():
    w, h = 22, 54
    im = new(w, h)
    shade_fill(im, lambda x, y: 3 <= x < 19 and 4 <= y < 54, w, h, BRICK, seed=31, noise=0.08)
    shade_fill(im, lambda x, y: 1 <= x < 21 and 0 <= y < 5, w, h, STONE, seed=32)
    for y in range(5, 54):
        for x in range(3, 19):
            if y % 5 == 0 or (x + (y // 5) * 3) % 8 == 0:
                put(im, x, y, BRICK[2])
    # slime streaks
    for x in (6, 15):
        for y in range(5, 20 + x):
            put(im, x, y, hexc("6fa82a") if y % 3 else hexc("4a7a14"))
    return im

# ================================================================ Crypt Depths

def sarcophagus():
    w, h = 40, 30
    im = new(w, h)
    lid = (hexc("a8a294"), hexc("847e70"), hexc("625c50"), hexc("443f36"))
    shade_fill(im, lambda x, y: 2 <= x < 38 and 10 <= y < 30, w, h, STONE, seed=33)
    shade_fill(im, lambda x, y: 0 <= x < 40 and 4 <= y < 11 and not (y < 6 and (x < 2 or x > 37)), w, h, lid, seed=34)
    # a carved effigy on the lid
    rows(im, 12, 4, ["..ooo.............", ".ooooo...oooooooo.", "..ooo...ooooooooo."], {"o": lid[0]})
    line(im, 3, 11, 37, 11, STONE[3])
    for x in range(6, 36, 6):
        rows(im, x, 15, ["dd", "d."], {"d": STONE[2]})
    # the lid slid aside a little: dark gap
    for x in range(30, 37):
        put(im, x, 10, hexc("0c0a10"))
    return im

def broken_pillar():
    w, h = 22, 46
    im = new(w, h)
    def m(x, y):
        if 40 <= y < 46:
            return 1 <= x < 21
        top = 6 + (x * 5) % 7 if x < 11 else 2 + (x * 3) % 5
        return 4 <= x < 18 and top <= y < 40
    shade_fill(im, m, w, h, STONE, seed=35)
    for x in (7, 11, 15):
        line(im, x, 10, x, 39, STONE[2])
    rows(im, 0, 43, ["..ss", "sss."], {"s": STONE[1]})
    tufts(im, 0, 22, 45, seed=36)
    return im

def candelabra():
    """A tall iron candelabra with three guttering candles. 20x40, 4 frames."""
    w, h = 20, 40
    frames = []
    for k in range(4):
        im = new(w, h)
        line(im, 10, 14, 10, 38, IRON[1]); line(im, 11, 14, 11, 38, IRON[2])
        rows(im, 6, 37, ["iiiiiiii", ".iiiiii."], {"i": IRON[1]})
        line(im, 3, 14, 17, 14, IRON[1])
        line(im, 3, 11, 3, 14, IRON[1]); line(im, 17, 11, 17, 14, IRON[1])
        for (x, top) in [(3, 6), (10, 3), (17, 6)]:
            for y in range(top + 3, 12 if x != 10 else 14):
                put(im, x, y, hexc("f2ecd8"))
                put(im, x + 1, y, hexc("cfc6aa"))
            fl = [(0, 0), (1, 0), (0, -1), (-1, 0)][(k + x) % 4]
            rows(im, x + fl[0], top + fl[1], [".y", "yo", "oo"], {"y": hexc("fff2a8"), "o": hexc("ffa12b")})
            put(im, x, top + 3, hexc("3a2a1a"))
        # wax drips
        put(im, 4, 13, hexc("f2ecd8")); put(im, 9, 15, hexc("f2ecd8"))
        frames.append(im)
    return frames

def bone_pile():
    w, h = 32, 20
    im = new(w, h)
    rng = random.Random(37)
    for i in range(9):
        x0, y0 = rng.randint(2, 22), rng.randint(8, 16)
        x1, y1 = x0 + rng.randint(5, 9), y0 + rng.randint(-4, 3)
        thick(im, x0, y0, x1, y1, 0.8, BONE[1])
        disc(im, x0, y0, 1.3, BONE[0]); disc(im, x1, y1, 1.3, BONE[0])
    for (x, y) in [(8, 4), (19, 6)]:
        rows(im, x, y, [".bbbb.", "bbbbbb", "beebeb", "bbbbbb", ".b.b.."], {"b": BONE[0], "e": hexc("2a1a14")})
    for y in range(h):
        for x in range(w):
            c = im.getpixel((x, y))
            if c[3] and (x == w - 1 or not im.getpixel((x + 1, y))[3]) and (y == h - 1 or not im.getpixel((x, y + 1))[3]):
                put(im, x, y, BONE[3])
    return im

# ================================================================ Quest relics (16x16)

GOLD = (hexc("fff2a8"), hexc("f2c94a"), hexc("c08a1a"), hexc("6e4a0a"))

def _outline(im, col=hexc("1a1206")):
    A.outline(im, col)
    return im

def relic_locket():
    im = new(16, 16)
    line(im, 5, 1, 8, 4, GOLD[2]); line(im, 11, 1, 8, 4, GOLD[2])   # chain
    shade_fill(im, lambda x, y: (x + 0.5 - 8) ** 2 / 20 + (y + 0.5 - 10) ** 2 / 20 < 1, 16, 16, GOLD, seed=40, noise=0.0)
    rows(im, 6, 8, ["r.r.", "rrr.", ".r.."], {"r": hexc("c22a43")})
    put(im, 6, 8, hexc("ff8a9a"))
    return _outline(im)

def relic_chalice():
    im = new(16, 16)
    shade_fill(im, lambda x, y: (2 <= y < 8 and abs(x + 0.5 - 8) < 6 - (y - 2) * 0.5) or (8 <= y < 12 and abs(x + 0.5 - 8) < 1.2) or (12 <= y < 15 and abs(x + 0.5 - 8) < 4), 16, 16, GOLD, seed=41, noise=0.0)
    for x in range(3, 14):
        put(im, x, 2, hexc("c0102a"))
    put(im, 8, 1, hexc("e0283a"))
    rows(im, 6, 4, ["g.g"], {"g": hexc("7ad7ff")})
    return _outline(im)

def relic_gourd():
    im = new(16, 16)
    shade_fill(im, lambda x, y: (x + 0.5 - 8) ** 2 / 36 + (y + 0.5 - 10) ** 2 / 22 < 1, 16, 16, GOLD, seed=42, noise=0.0)
    for x in (5, 11):
        line(im, x, 7, x, 13, GOLD[2])
    rows(im, 7, 2, ["gg", ".g", ".g"], {"g": hexc("4a7a2a")})
    rows(im, 4, 9, ["w"], {"w": hexc("ffffff")})
    return _outline(im)

def relic_frozen_heart():
    im = new(16, 16)
    ice = (hexc("e8f8ff"), hexc("9fd8f0"), hexc("5aa8d0"), hexc("2a6a90"))
    for y in range(16):
        for x in range(16):
            u = (x + 0.5 - 8) / 6.0
            v = -(y + 0.5 - 8.5) / 6.0
            if (u * u + v * v - 1) ** 3 - u * u * v ** 3 <= 0:
                put(im, x, y, ice[1])
    shade_fill(im, lambda x, y: im.getpixel((x, y))[3] > 0, 16, 16, ice, seed=43, noise=0.0)
    rows(im, 5, 5, ["ww", "w."], {"w": hexc("ffffff")})
    line(im, 9, 6, 11, 10, ice[3])
    return _outline(im, hexc("0a1e2a"))

def relic_key():
    im = new(16, 16)
    rust = (hexc("d8a05a"), hexc("a8702a"), hexc("6e4214"), hexc("3a220a"))
    shade_fill(im, lambda x, y: 9 < (x + 0.5 - 5) ** 2 + (y + 0.5 - 5) ** 2 < 20, 16, 16, rust, seed=44, noise=0.0)
    thick(im, 8, 8, 14, 14, 0.8, rust[1])
    rows(im, 11, 12, ["r.", "rr", ".r"], {"r": rust[1]})
    rows(im, 13, 9, ["r", "rr"], {"r": rust[1]})
    put(im, 2, 9, hexc("8ae02a")); put(im, 3, 10, hexc("6fb82a"))  # sewer slime
    return _outline(im)

def relic_crown():
    im = new(16, 16)
    rows(im, 1, 4, [
        "b.....b.....b.",
        "bb...bbb...bb.",
        "bbb.bbbbb.bbb.",
        "bbbbbbbbbbbbb.",
        "bbbbbbbbbbbbb.",
        "bkbbkbbkbbkbb.",
        "bbbbbbbbbbbbb.",
    ], {"b": BONE[0], "k": hexc("2a1a14")})
    shade_fill(im, lambda x, y: im.getpixel((x, y))[3] > 0 and im.getpixel((x, y))[:3] != (42, 26, 20), 16, 16, BONE, seed=45, noise=0.0)
    for x in (2, 7, 13):
        put(im, x, 4, hexc("c22a43"))
    put(im, 7, 7, hexc("7a3df0"))
    return _outline(im)

if __name__ == "__main__":
    A.save(angel_statue(), "prop_angel")
    A.save(open_grave(), "prop_open_grave")
    A.save(sheet(blood_fountain()), "prop_blood_fountain")
    A.save(gibbet(), "prop_gibbet")
    A.save(sheet(blood_obelisk()), "prop_obelisk")
    A.save(hay_bale(), "prop_hay_bale")
    A.save(pumpkin_pile(), "prop_pumpkin_pile")
    A.save(corn_stalks(), "prop_corn")
    A.save(wood_fence(), "prop_fence")
    A.save(scarecrow_post(), "prop_scarecrow")
    A.save(snow_pine(), "prop_snow_pine")
    A.save(snowman(), "prop_snowman")
    A.save(ice_grave(), "prop_ice_grave")
    A.save(snow_angel_statue(), "prop_snow_angel")
    A.save(sheet(sewer_pipe()), "prop_sewer_pipe")
    A.save(barrel_stack(), "prop_barrels")
    A.save(brick_pillar(), "prop_brick_pillar")
    A.save(sarcophagus(), "prop_sarcophagus")
    A.save(broken_pillar(), "prop_broken_pillar")
    A.save(sheet(candelabra()), "prop_candelabra")
    A.save(bone_pile(), "prop_bones")
    A.save(relic_locket(), "relic_locket")
    A.save(relic_chalice(), "relic_chalice")
    A.save(relic_gourd(), "relic_gourd")
    A.save(relic_frozen_heart(), "relic_frozen_heart")
    A.save(relic_key(), "relic_key")
    A.save(relic_crown(), "relic_crown")
