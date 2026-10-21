#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""导出 MaterialIcons-Regular.ttf 的 码位 -> 字形名 映射.

字形名来自字体自身的 post 表 (format 2), 比任何在线 codepoints 清单都权威:
它就是这个 ttf 里真实存在的名字, 不会因版本对不上而错位.

用法:
    python3 tools/dump_glyph_names.py            # 全部
    python3 tools/dump_glyph_names.py --used     # 只列 qml 里实际用到的码位
"""
import struct
import sys
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TTF = os.path.join(ROOT, "assets", "fonts", "MaterialIcons-Regular.ttf")


def tables(data):
    num = struct.unpack(">H", data[4:6])[0]
    out = {}
    for i in range(num):
        rec = 12 + i * 16
        tag = data[rec:rec + 4].decode("latin1")
        off, length = struct.unpack(">II", data[rec + 8:rec + 16])
        out[tag] = (off, length)
    return out


def cmap_cp_to_gid(data, tabs):
    """返回 {codepoint: glyph_id}, 覆盖 format 4 / format 12 子表."""
    off, _ = tabs["cmap"]
    n_sub = struct.unpack(">H", data[off + 2:off + 4])[0]
    result = {}
    for i in range(n_sub):
        rec = off + 4 + i * 8
        sub = off + struct.unpack(">I", data[rec + 4:rec + 8])[0]
        fmt = struct.unpack(">H", data[sub:sub + 2])[0]
        if fmt == 4:
            seg_x2 = struct.unpack(">H", data[sub + 6:sub + 8])[0]
            seg = seg_x2 // 2
            ends = struct.unpack(">%dH" % seg, data[sub + 14:sub + 14 + seg_x2])
            so = sub + 16 + seg_x2
            starts = struct.unpack(">%dH" % seg, data[so:so + seg_x2])
            deltas = struct.unpack(">%dh" % seg, data[so + seg_x2:so + 2 * seg_x2])
            range_off_pos = so + 2 * seg_x2
            range_offs = struct.unpack(">%dH" % seg, data[range_off_pos:range_off_pos + seg_x2])
            for s in range(seg):
                for c in range(starts[s], ends[s] + 1):
                    if c == 0xFFFF:
                        continue
                    ro = range_offs[s]
                    if ro == 0:
                        g = (c + deltas[s]) & 0xFFFF
                    else:
                        gi = range_off_pos + s * 2 + ro // 2 + (c - starts[s])
                        if gi + 2 > len(data):
                            continue
                        gi_val = struct.unpack(">H", data[gi:gi + 2])[0]
                        g = 0 if gi_val == 0 else (gi_val + deltas[s]) & 0xFFFF
                    if g:
                        result.setdefault(c, g)
        elif fmt == 12:
            n_groups = struct.unpack(">I", data[sub + 12:sub + 16])[0]
            for gi in range(n_groups):
                base = sub + 16 + gi * 12
                sc, ec, sg = struct.unpack(">III", data[base:base + 12])
                for c in range(sc, ec + 1):
                    result.setdefault(c, sg + (c - sc))
    return result


def post_names(data, tabs):
    """返回 {glyph_id: name} (post format 2)."""
    off, _ = tabs["post"]
    fmt = struct.unpack(">I", data[off:off + 4])[0]
    if fmt != 0x00020000:
        return {}
    ng = struct.unpack(">H", data[off + 32:off + 34])[0]
    idx = struct.unpack(">%dH" % ng, data[off + 34:off + 34 + ng * 2])
    p = off + 34 + ng * 2
    strings = []
    while p < len(data):
        ln = data[p]
        if ln == 0 and not strings and False:
            break
        name = data[p + 1:p + 1 + ln].decode("latin1")
        strings.append(name)
        p += 1 + ln
    mac = [""] * 258
    names = {}
    for gid, mi in enumerate(idx):
        if mi >= 0xFFFF:
            continue
        if mi < 258:
            names[gid] = mac[mi] or str(gid)
        else:
            s = mi - 258
            names[gid] = strings[s] if s < len(strings) else str(gid)
    return names


def used_codepoints():
    """扫 qml/ 找出实际写死的 PUA 码位."""
    used = set()
    for dirpath, _, files in os.walk(os.path.join(ROOT, "qml")):
        for fn in files:
            if not fn.endswith(".qml"):
                continue
            txt = open(os.path.join(dirpath, fn), encoding="utf-8", errors="replace").read()
            for m in re.finditer(r"\\u([eE][0-9a-fA-F]{3}|[fF][0-9a-fA-F]{3})", txt):
                used.add(int(m.group(1), 16))
    return used


def main():
    data = open(TTF, "rb").read()
    tabs = tables(data)
    if "post" not in tabs:
        print("该字体没有 post 表, 无法取字形名")
        return
    names = post_names(data, tabs)
    if not names:
        print("post 表不是 format 2, 取不到字形名")
        return
    cp2gid = cmap_cp_to_gid(data, tabs)
    print("# glyph_id -> name 共 %d 条, cmap 码位 %d 个" % (len(names), len(cp2gid)))
    pairs = sorted((cp, names.get(gid, "?")) for cp, gid in cp2gid.items()
                   if 0xE000 <= cp <= 0xF8FF)
    if "--used" in sys.argv:
        want = used_codepoints()
        pairs = [(cp, nm) for cp, nm in pairs if cp in want]
    for cp, nm in pairs:
        print("U+%04X\t%s" % (cp, nm))


if __name__ == "__main__":
    main()
