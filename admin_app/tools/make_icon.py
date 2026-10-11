#!/usr/bin/env python3
"""Draws the launcher icon (dark square, brass magnifier) with plain Python: no Pillow, no copyrighted art.

    python3 tools/make_icon.py <android/app/src/main/res>

Writes mipmap-*/ic_launcher.png at the five Android densities.
"""
import math
import struct
import sys
import zlib
from pathlib import Path

BG = (23, 24, 26)
BRASS = (224, 165, 38)
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def coverage(x, y):
    """Is the point (0..1, 0..1) on the magnifier? ring + handle + a small glint."""
    ring = abs(math.hypot(x - 0.42, y - 0.42) - 0.21) <= 0.045
    handle = seg_dist(x, y, 0.58, 0.58, 0.80, 0.80) <= 0.055
    glint = seg_dist(x, y, 0.30, 0.40, 0.36, 0.30) <= 0.018
    return ring or handle or glint


def png(size):
    ss = 3
    rows = []
    for j in range(size):
        row = bytearray([0])
        for i in range(size):
            hits = sum(coverage((i + (a + .5) / ss) / size, (j + (b + .5) / ss) / size)
                       for a in range(ss) for b in range(ss))
            f = hits / (ss * ss)
            row += bytes(round(BG[k] + (BRASS[k] - BG[k]) * f) for k in range(3))
        rows.append(bytes(row))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))


def main():
    res = Path(sys.argv[1])
    for name, size in SIZES.items():
        d = res / f"mipmap-{name}"
        d.mkdir(parents=True, exist_ok=True)
        (d / "ic_launcher.png").write_bytes(png(size))
    print(f"icons written to {res}")


if __name__ == "__main__":
    main()
