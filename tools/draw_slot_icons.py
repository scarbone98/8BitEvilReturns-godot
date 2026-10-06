#!/usr/bin/env python3
"""Shop icons for the extra slot power-ups: an empty inventory slot with a
gold plus, and what goes in it (a sword or a gem) peeking from the corner.
32x32. Usage: tools/draw_slot_icons.py [OUT_DIR]   (default assets/sprites)"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import draw_weapon_art as A
from draw_weapon_art import hexc, new, put, rows, outline, line, thick

A.OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
OL = hexc("120a14")
GOLD, GOLD2, GOLD3 = hexc("ffe27a"), hexc("f0b030"), hexc("a86a10")

def slot_frame(im, fill, edge, hi):
    for y in range(3, 27):
        for x in range(3, 27):
            put(im, x, y, fill)
    for i in range(3, 27):  # bevel: light top/left, dark bottom/right
        put(im, i, 3, hi); put(im, 3, i, hi)
        put(im, i, 26, edge); put(im, 26, i, edge)
    for x in range(6, 24, 3):  # dashed inner border: "empty"
        put(im, x, 6, edge); put(im, x, 23, edge)
        put(im, 6, x, edge); put(im, 23, x, edge)

def plus(im, cx, cy):
    for d in range(-4, 5):
        for w in (-1, 0, 1):
            put(im, cx + d, cy + w, GOLD2 if w else GOLD); put(im, cx + w, cy + d, GOLD2 if w else GOLD)
    put(im, cx - 4, cy - 1, GOLD); put(im, cx - 1, cy - 4, GOLD)

def weapon_slot():
    im = new(32, 32)
    slot_frame(im, hexc("3a2440"), hexc("1e1024"), hexc("6a4a78"))
    plus(im, 14, 14)
    # a little sword in the corner
    steel, steel2 = hexc("e8eef6"), hexc("8d96a8")
    line(im, 19, 29, 29, 19, steel); line(im, 20, 29, 29, 20, steel2)
    line(im, 18, 25, 23, 30, GOLD3); put(im, 17, 30, hexc("5a3a24")); put(im, 18, 30, hexc("5a3a24"))
    outline(im, OL)
    return im

def passive_slot():
    im = new(32, 32)
    slot_frame(im, hexc("1f3040"), hexc("0e1824"), hexc("4a6a88"))
    plus(im, 14, 14)
    # a gem on a gold setting in the corner
    rows(im, 21, 21, ["..ggg..", ".gcccg.", "gcwccdg", "gccccdg", ".gcddg.", "..ggg.."],
         {"g": GOLD2, "c": hexc("4ad8ff"), "w": hexc("ffffff"), "d": hexc("1a7ab8")})
    outline(im, OL)
    return im

if __name__ == "__main__":
    A.save(weapon_slot(), "weapon_slot_icon")
    A.save(passive_slot(), "passive_slot_icon")
