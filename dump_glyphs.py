# -*- coding: utf-8 -*-
"""导出字体全部 PUA 码点 (每行 16 个), 供挑选替代图标."""
import os, struct

FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "assets", "fonts", "MaterialIcons-Regular.ttf")

def read_font_codepoints(path):
    data = open(path, "rb").read()
    numTables = struct.unpack(">H", data[4:6])[0]
    cmap_off = None
    for i in range(numTables):
        rec = 12 + i * 16
        if data[rec:rec+4] == b"cmap":
            cmap_off = struct.unpack(">I", data[rec+8:rec+12])[0]
            break
    n_sub = struct.unpack(">H", data[cmap_off+2:cmap_off+4])[0]
    codes = set()
    for s in range(n_sub):
        rec = cmap_off + 4 + s * 8
        off = cmap_off + struct.unpack(">I", data[rec+4:rec+8])[0]
        fmt = struct.unpack(">H", data[off:off+2])[0]
        if fmt == 4:
            segX2 = struct.unpack(">H", data[off+6:off+8])[0]
            seg = segX2 // 2
            ends = struct.unpack(">%dH" % seg, data[off+14:off+14+segX2])
            starts = struct.unpack(">%dH" % seg, data[off+16+segX2:off+16+2*segX2])
            for k in range(seg):
                for c in range(starts[k], ends[k]+1):
                    if c != 0xFFFF:
                        codes.add(c)
        elif fmt == 12:
            ngroups = struct.unpack(">I", data[off+12:off+16])[0]
            for g in range(ngroups):
                gr = off + 16 + g * 12
                sc, ec, _ = struct.unpack(">III", data[gr:gr+12])
                for c in range(sc, ec+1):
                    codes.add(c)
    return codes

codes = sorted(c for c in read_font_codepoints(FONT) if c >= 0xE000)
print("total PUA: %d" % len(codes))
for c in codes:
    print("U+%04X" % c, end="  ")
print()
