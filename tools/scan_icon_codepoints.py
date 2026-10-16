#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""扫描 QML 中的原始 Material Icons 转义, 校验 ttf cmap 是否覆盖."""
import struct
import re
import glob
import sys

TTF = "assets/fonts/MaterialIcons-Regular.ttf"


def load_codepoints(path):
    data = open(path, "rb").read()
    _, num_tables = struct.unpack(">IH", data[0:6])
    tables = {}
    off = 12
    for _ in range(num_tables):
        tag = data[off:off + 4].decode("latin1")
        _, o, l = struct.unpack(">III", data[off + 4:off + 16])
        tables[tag] = (o, l)
        off += 16
    o, l = tables["cmap"]
    cmap = data[o:o + l]
    num_sub = struct.unpack(">H", cmap[2:4])[0]
    cp = set()
    for i in range(num_sub):
        pid, eid, so = struct.unpack(">HHI", cmap[4 + i * 8:12 + i * 8])
        fmt = struct.unpack(">H", cmap[so:so + 2])[0]
        if fmt == 4:
            seg_x2 = struct.unpack(">H", cmap[so + 6:so + 8])[0]
            seg = seg_x2 // 2
            end_c = [struct.unpack(">H", cmap[so + 14 + i * 2:so + 16 + i * 2])[0] for i in range(seg)]
            start_c = [struct.unpack(">H", cmap[so + 16 + seg_x2 + i * 2:so + 18 + seg_x2 + i * 2])[0] for i in range(seg)]
            for i in range(seg):
                if start_c[i] != 0xFFFF:
                    cp.update(range(start_c[i], end_c[i] + 1))
        elif fmt == 12:
            n = struct.unpack(">I", cmap[so + 12:so + 16])[0]
            for g in range(n):
                a, b, _ = struct.unpack(">III", cmap[so + 16 + g * 12:so + 28 + g * 12])
                cp.update(range(a, b + 1))
    return cp


PAT = re.compile("\\\\u([eE][0-9a-fA-F]{3})")


def main():
    cp = load_codepoints(TTF)
    print("font codepoints: %d (PUA %d)" % (len(cp), len([c for c in cp if 0xE000 <= c <= 0xF8FF])))
    print(r"=== raw \uXXXX escapes in qml/ ===")
    missing = []
    for f in sorted(glob.glob("qml/**/*.qml", recursive=True)):
        txt = open(f, encoding="utf-8").read()
        for m in PAT.finditer(txt):
            c = int(m.group(1), 16)
            line = txt[:m.start()].count("\n") + 1
            ok = c in cp
            if not ok:
                missing.append((f, line, m.group(1)))
            print("  %-52s :%-4d U+%s  %s" % (f, line, m.group(1).upper(), "OK" if ok else "*** MISSING ***"))
    print()
    print("MISSING total: %d" % len(missing))
    for f, line, cpv in missing:
        print("   MISSING %s:%d U+%s" % (f, line, cpv.upper()))
    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main())
