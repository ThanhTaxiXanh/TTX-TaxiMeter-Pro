#!/usr/bin/env python3
"""Sinh glyph PBF (SDF) cho MapLibre tu font DejaVu Sans (ho tro tieng Viet), chay offline.

  python3 tool/gen_glyphs.py            -> assets/glyphs/<stack>/<start>-<end>.pbf
Cac dai: 0-255, 256-511, 7680-7935 (Latin mo rong bo sung: a-hoi, a-nang...), 8192-8447 (dau cau).
Dinh dang: mapbox glyphs.proto (fontstack{name,range,glyphs{id,bitmap,width,height,left,top,advance}}).
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import distance_transform_edt

FONTS = {
    'DejaVuSans-Regular': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    'DejaVuSans-Bold': '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    'DejaVuSans-Oblique': '/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf',
}
RANGES = [(0, 255), (256, 511), (7680, 7935), (8192, 8447)]
SIZE, BUFFER, RADIUS, CUTOFF = 24, 3, 8.0, 0.25


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def zigzag(n):
    return (n << 1) ^ (n >> 31) if n >= 0 else ((-n) << 1) - 1


def fld(num, wt, payload):
    return varint(num << 3 | wt) + payload


def ldelim(num, data):
    return fld(num, 2, varint(len(data)) + data)


def glyph_msg(cp, font, ascender):
    ch = chr(cp)
    adv = font.getlength(ch)
    l, t, r, b = font.getbbox(ch, anchor='ls')  # relative to baseline origin
    w, h = max(r - l, 0), max(b - t, 0)
    if w == 0 or h == 0:
        return None if cp not in (32, 160) else (
            fld(1, 0, varint(cp)) + fld(3, 0, varint(0)) + fld(4, 0, varint(0)) +
            fld(5, 0, varint(zigzag(0))) + fld(6, 0, varint(zigzag(0))) + fld(7, 0, varint(round(adv))))
    W, H = w + 2 * BUFFER, h + 2 * BUFFER
    img = Image.new('L', (W, H), 0)
    ImageDraw.Draw(img).text((BUFFER - l, BUFFER - t), ch, font=font, fill=255, anchor='ls')
    cov = np.asarray(img, dtype=np.float32) / 255.0
    inside = cov > 0.5
    d = distance_transform_edt(~inside) - distance_transform_edt(inside)  # + ngoai, - trong
    val = 255.0 * (1.0 - (d / RADIUS + CUTOFF))
    bitmap = np.clip(val, 0, 255).astype(np.uint8).tobytes()
    left, top = l, -t - ascender  # top = bitmap_top - ascender (kieu fontnik)
    return (fld(1, 0, varint(cp)) + ldelim(2, bitmap) + fld(3, 0, varint(w)) + fld(4, 0, varint(h)) +
            fld(5, 0, varint(zigzag(left))) + fld(6, 0, varint(zigzag(top))) + fld(7, 0, varint(round(adv))))


def build(stack, path, lo, hi):
    font = ImageFont.truetype(path, SIZE)
    ascender = font.getmetrics()[0]
    body = ldelim(1, stack.encode()) + ldelim(2, f'{lo}-{hi}'.encode())
    n = 0
    for cp in range(lo, hi + 1):
        g = glyph_msg(cp, font, ascender)
        if g is not None:
            body += ldelim(3, g)
            n += 1
    return ldelim(1, body), n


if __name__ == '__main__':
    root = os.path.join(os.path.dirname(__file__), '..', 'assets', 'glyphs')
    for stack, path in FONTS.items():
        os.makedirs(os.path.join(root, stack), exist_ok=True)
        for lo, hi in RANGES:
            data, n = build(stack, path, lo, hi)
            with open(os.path.join(root, stack, f'{lo}-{hi}.pbf'), 'wb') as f:
                f.write(data)
            print(stack, lo, hi, n, len(data))
