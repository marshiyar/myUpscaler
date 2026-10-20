#!/usr/bin/env python3
"""Writes a 1280x720 PNG test picture (sky, sun, textured hills) to the path given, for screenshots and runs."""
import math
import struct
import sys
import zlib

w, h = 1280, 720
rows = []
for y in range(h):
    row = bytearray([0])
    for x in range(w):
        if math.hypot(x - 900, y - 200) < 70:
            c = (255, 220, 120)
        elif y > 480 + 40 * math.sin(x / 90):
            c = (int(40 + 30 * math.sin(x / 7 + y / 5)), int(110 + 20 * math.sin(x / 13)), 50)
        else:
            c = (int(90 + 80 * y / h), int(140 + 60 * y / h), int(220 - 40 * y / h))
        row += bytes(c)
    rows.append(bytes(row))


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 6)) + chunk(b"IEND", b"")
with open(sys.argv[1], "wb") as out:
    out.write(png)
