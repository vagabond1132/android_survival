# -*- coding: utf-8 -*-
"""扫描 QML 中所有 \\uXXXX 字面量, 与字体 cmap 比对, 输出缺失清单."""
import os, re, struct, sys

FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "assets", "fonts", "MaterialIcons-Regular.ttf")
QML_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qml")

def read_font_codepoints(path):
    data = open(path, "rb").read()
    numTables = struct.unpack(">H", data[4:6])[0]
    cmap_off = None
    for i in range(numTables):
        rec = 12 + i * 16
        tag = data[rec:rec+4]
        if tag == b"cmap":
            cmap_off = struct.unpack(">I", data[rec+8:rec+12])[0]
            break
    if cmap_off is None:
        raise RuntimeError("no cmap")
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

def main():
    font = read_font_codepoints(FONT)
    print("font codepoints: %d" % len(font))
    pat = re.compile(r"\\u([0-9a-fA-F]{4})")
    found = {}   # code -> set(files)
    for dirpath, _, files in os.walk(QML_ROOT):
        for fn in files:
            if not fn.endswith(".qml"):
                continue
            p = os.path.join(dirpath, fn)
            try:
                txt = open(p, encoding="utf-8").read()
            except Exception:
                continue
            for m in pat.finditer(txt):
                code = int(m.group(1), 16)
                found.setdefault(code, set()).add(os.path.relpath(p, QML_ROOT))
    missing = {c: v for c, v in found.items() if c not in font}
    print("used codepoints: %d ; missing: %d" % (len(found), len(missing)))
    for c in sorted(missing):
        print("MISSING \\u%04X : %s" % (c, ", ".join(sorted(missing[c]))))

if __name__ == "__main__":
    main()
