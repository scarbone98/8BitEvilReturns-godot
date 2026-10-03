#!/usr/bin/env python3
"""Recolours pixel art by brightness onto a new gradient, keeping the pattern.

    tools/recolor.py in.png out.png "#3a2418,#5a3a22,#7a5230"

Each pixel's brightness (relative to the darkest and lightest in the image)
picks a colour along the gradient; alpha is kept. Used to make new stage
floors from the original graveyard floor so they share its look.
"""
import struct, sys, zlib

def load(path):
    d = open(path, 'rb').read()
    w, h = struct.unpack('>II', d[16:24]); ct = d[25]
    idat = b''; i = 8; plte = trns = None
    while i < len(d):
        l = struct.unpack('>I', d[i:i + 4])[0]; t = d[i + 4:i + 8]
        if t == b'IDAT': idat += d[i + 8:i + 8 + l]
        if t == b'PLTE': plte = d[i + 8:i + 8 + l]
        if t == b'tRNS': trns = d[i + 8:i + 8 + l]
        i += 12 + l
    raw = zlib.decompress(idat); bpp = {6: 4, 2: 3, 3: 1, 4: 2, 0: 1}[ct]; stride = w * bpp + 1
    prev = bytearray(stride - 1); px = []
    for y in range(h):
        f = raw[y * stride]; line = bytearray(raw[y * stride + 1:(y + 1) * stride])
        for x in range(len(line)):
            a = line[x - bpp] if x >= bpp else 0; b = prev[x]; c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        row = []
        for x in range(w):
            if ct == 6: row.append(tuple(line[x * 4:x * 4 + 4]))
            elif ct == 2: row.append(tuple(line[x * 3:x * 3 + 3]) + (255,))
            elif ct == 3:
                k = line[x]; row.append(tuple(plte[k * 3:k * 3 + 3]) + ((trns[k] if trns and k < len(trns) else 255),))
            else: raise SystemExit('unsupported PNG type %d' % ct)
        px.append(row)
    return w, h, px

def save(path, w, h, px):
    raw = b''.join(b'\x00' + bytes(v for p in row for v in p) for row in px)
    def chunk(t, data): return struct.pack('>I', len(data)) + t + data + struct.pack('>I', zlib.crc32(t + data) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

def main():
    src, dst, stops = sys.argv[1], sys.argv[2], [s.strip().lstrip('#') for s in sys.argv[3].split(',')]
    stops = [tuple(int(s[i:i + 2], 16) for i in (0, 2, 4)) for s in stops]
    w, h, px = load(src)
    lum = lambda p: 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]
    lums = [lum(p) for row in px for p in row if p[3] > 0]
    lo, hi = min(lums), max(lums)
    def grad(t):
        t = max(0.0, min(1.0, t)) * (len(stops) - 1); i = min(int(t), len(stops) - 2); f = t - i
        return tuple(round(stops[i][k] + (stops[i + 1][k] - stops[i][k]) * f) for k in range(3))
    out = [[grad((lum(p) - lo) / ((hi - lo) or 1)) + (p[3],) for p in row] for row in px]
    save(dst, w, h, out)

main()
