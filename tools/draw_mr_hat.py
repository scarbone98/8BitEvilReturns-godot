#!/usr/bin/env python3
"""Mr. Hat, the playable merchant: the merchant's body sheet with his top hat
on his head, and feet on the bottom row so he stands on his shadow.
5 frames of 128x128 (the hero is drawn at scale 0.25).

Usage: tools/draw_mr_hat.py   (writes assets/sprites/mr_hat.png)"""
import os
from PIL import Image

D = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
body = Image.open(os.path.join(D, "merchant_body.png")).convert("RGBA")
hat = Image.open(os.path.join(D, "merchant_hat.png")).convert("RGBA")
DROP = 41  # body rows 15..86 move to 56..127; the hat's brim lands on his head
out = Image.new("RGBA", body.size, (0, 0, 0, 0))
for f in range(body.width // 128):
    fr = body.crop((f * 128, 0, f * 128 + 128, 128 - DROP))
    out.alpha_composite(fr, (f * 128, DROP))
    bob = 1 if f in (1, 3) else 0  # the hat rides the body's sway a little
    out.alpha_composite(hat.crop((0, 3, 64, 64)), (f * 128 + 28, bob))
out.save(os.path.join(D, "mr_hat.png"))
print("wrote mr_hat", out.size)
