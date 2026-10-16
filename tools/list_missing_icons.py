#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""列出缺失码点在 QML 中的全部引用上下文 (输出 UTF-8 文件, 避开 GBK 控制台)."""
import glob
import re
import io

MISS = ["E50F", "E1D7", "E6B1", "E6E3", "E1F7", "E4E0", "E1F6", "E2DC",
        "E205", "E9D5", "E2D0", "E1CC", "E1EB", "E1F9", "E2D4"]

PAT = re.compile("\\\\u([eE][0-9a-fA-F]{3})")

hits = {m: [] for m in MISS}
for f in sorted(glob.glob("qml/**/*.qml", recursive=True)):
    lines = open(f, encoding="utf-8").read().splitlines()
    for i, ln in enumerate(lines):
        for m in PAT.finditer(ln):
            c = m.group(1).upper()
            if c in hits:
                hits[c].append((f, i + 1, ln.strip()[:150]))

with io.open("tools/missing_icons_report.txt", "w", encoding="utf-8") as out:
    for m in MISS:
        out.write("=== U+%s  (%d refs) ===\n" % (m, len(hits[m])))
        for f, l, txt in hits[m]:
            out.write("   %s:%d\n       %s\n" % (f.replace("qml\\", "qml/"), l, txt))
        out.write("\n")

print("done -> tools/missing_icons_report.txt")
