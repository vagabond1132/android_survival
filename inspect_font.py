# -*- coding: utf-8 -*-
"""读 TTF name table (版本信息) + post table (glyph 名), 判断字体身份."""
import os, struct

FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "assets", "fonts", "MaterialIcons-Regular.ttf")
data = open(FONT, "rb").read()
numTables = struct.unpack(">H", data[4:6])[0]
tables = {}
for i in range(numTables):
    rec = 12 + i * 16
    tag = data[rec:rec+4].decode("latin1")
    off = struct.unpack(">I", data[rec+8:rec+12])[0]
    ln = struct.unpack(">I", data[rec+12:rec+16])[0]
    tables[tag] = (off, ln)
print("tables:", sorted(tables.keys()))

# --- name table ---
if "name" in tables:
    off, _ = tables["name"]
    cnt = struct.unpack(">H", data[off+2:off+4])[0]
    strOff = off + struct.unpack(">H", data[off+4:off+6])[0]
    for i in range(cnt):
        r = off + 6 + i*12
        pid, eid, lid, nid, ln, so = struct.unpack(">HHHHHH", data[r:r+12])
        if nid in (1, 2, 3, 4, 5, 6):
            raw = data[strOff+so:strOff+so+ln]
            try:
                txt = raw.decode("utf-16-be") if pid in (0, 3) else raw.decode("latin1")
            except Exception:
                txt = repr(raw)
            if pid == 3 and eid == 1 and lid == 0x409 or pid == 1:
                print("  name[%d] pid=%d eid=%d: %r" % (nid, pid, eid, txt))

# --- post table (v2 -> glyph names) ---
if "post" in tables:
    off, _ = tables["post"]
    ver = struct.unpack(">I", data[off:off+4])[0]
    print("post version: %08x" % ver)
    if ver == 0x00020000:
        ng = struct.unpack(">H", data[off+32:off+34])[0]
        idxs = struct.unpack(">%dH" % ng, data[off+34:off+34+2*ng])
        p = off + 34 + 2*ng
        names = []
        while p < len(data):
            ln = data[p]
            if ln == 0:
                break
            names.append(data[p+1:p+1+ln].decode("latin1"))
            p += 1 + ln
        print("post glyphs: %d, named: %d" % (ng, len(names)))
        # 打印前 40 个 + 全部非 uniXXXX 名
        sample = [n for n in names if not n.startswith("uni")][:60]
        print("non-uni glyph names sample:", sample)
        print("first 30 names:", names[:30])
        # 找 hiking / directions_car
        for kw in ("hiking", "car", "backpack", "menu_book", "equalizer"):
            hit = [n for n in names if kw in n]
            print("  contains %r: %s" % (kw, hit[:10]))
