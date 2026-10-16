#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为 15 个缺失码点寻找字体中真实存在的替代码点.

输出: tools/icon_replacement_candidates.txt
"""
import struct
import io

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


cp = load_codepoints(TTF)

# 标准 Material Icons (v3.x / 字体 1.017, 2019-05) 名称 -> 老码点
CANDIDATES = {
    "hiking(缺)": {
        "directions_walk e536": 0xE536,
        "directions_run e566": 0xE566,
        "terrain e564": 0xE564,
        "landscape e55f": 0xE55F,
        "directions_bike e530": 0xE530,
        "emoji_nature e239": 0xE239,
        "nature e406": 0xE406,
        "forest": 0xE5FF,
        "hiking_new e50f": 0xE50F,
    },
    "car(缺)": {
        "directions_car e531": 0xE531,
        "local_shipping e569": 0xE569,
        "directions_bus e532": 0xE532,
        "directions_transit e535": 0xE535,
        "train e570": 0xE570,
        "flight e539": 0xE539,
        "luggage e53f": 0xE53F,
        "boat e532": 0xE532,
    },
    "check/步骤(缺)": {
        "checklist e153": 0xE153,
        "playlist_add_check e065": 0xE065,
        "assignment e85d": 0xE85D,
        "check_circle e86c": 0xE86C,
        "list e896": 0xE896,
        "done e876": 0xE876,
        "fact_check_new": 0xE166,
        "build e14c": 0xE14C,
        "description e873": 0xE873,
    },
    "route/路面(缺)": {
        "map e55b": 0xE55B,
        "navigation e568": 0xE568,
        "timeline e922": 0xE922,
        "call_split e0b6": 0xE0B6,
        "alt_route e0b6": 0xE0B6,
        "linear_scale e260": 0xE260,
        "terrain e564": 0xE564,
        "route_new e6e3": 0xE6E3,
    },
    "加油/补给(缺)": {
        "local_shipping e569": 0xE569,
        "local_gas_station e989": 0xE989,
        "shopping_cart e8cc": 0xE8CC,
        "store e8d1": 0xE8D1,
        "restaurant e56c": 0xE56C,
        "local_dining e561": 0xE561,
        "attach_money e227": 0xE227,
        "monetization_on e263": 0xE263,
        "local_gas_station_new e1f7": 0xE1F7,
    },
    "统计/条数(缺)": {
        "equalizer e01d": 0xE01D,
        "bar_chart e26b": 0xE26B,
        "list e896": 0xE896,
        "view_list e8ef": 0xE8EF,
        "format_list_numbered e242": 0xE242,
        "assessment e85d": 0xE85D,
        "insert_chart e24b": 0xE24B,
        "equalizer_new e4e0": 0xE4E0,
    },
    "背包(缺)": {
        "luggage e53f": 0xE53F,
        "shopping_bag e8f6": 0xE8F6,
        "portable_wifi": 0xE88A,
        "work e8f9": 0xE8F9,
        "business_center e8f9": 0xE8F9,
        "backpack_new e1f6": 0xE1F6,
        "backpack_new2 e1f7": 0xE1F7,
    },
    "蘑菇(缺)": {
        "emoji_nature e239": 0xE239,
        "park e8a2": 0xE8A2,
        "spa e2dc": 0xE2DC,
        "grass? e4ca": 0xE4CA,
        "filter_vintage e3e3": 0xE3E3,
        "nature e406": 0xE406,
        "local_florist e545": 0xE545,
    },
    "叶子/植物(缺)": {
        "eco e205": 0xE205,
        "spa e2dc": 0xE2DC,
        "nature e406": 0xE406,
        "local_florist e545": 0xE545,
        "filter_vintage e3e3": 0xE3E3,
        "grass e4ca": 0xE4CA,
        "park e8a2": 0xE8A2,
        "forest": 0xE5FF,
        "tree": 0xE5FF,
    },
    "重量(缺)": {
        "fitness_center e6dd": 0xE6DD,
        "scale e1f6": 0xE1F6,
        "line_weight e259": 0xE259,
        "swap_vert e8d5": 0xE8D5,
        "monitor_weight": 0xE9D5,
        "fitness_center2 e9d5": 0xE9D5,
    },
    "日期/季节(缺)": {
        "event e878": 0xE878,
        "today e8df": 0xE8DF,
        "date_range e916": 0xE916,
        "calendar_today e935": 0xE935,
        "schedule e8b5": 0xE8B5,
        "access_time e192": 0xE192,
        "event_note e616": 0xE616,
        "wc? e2d0": 0xE2D0,
    },
    "材料(缺)": {
        "build e14c": 0xE14C,
        "handyman": 0xE8F9,
        "construction": 0xE8F9,
        "widgets e1bd": 0xE1BD,
        "extension e87b": 0xE87B,
        "category e574": 0xE574,
        "work e1eb": 0xE1EB,
    },
    "环境急症(缺)": {
        "warning e002": 0xE002,
        "wb_sunny e1b5": 0xE1B5,
        "ac_unit e193": 0xE193,
        "bolt e1b7": 0xE1B7,
        "terrain e564": 0xE564,
        "sos e1b1": 0xE1B1,
        "report e160": 0xE160,
    },
    "相册/文件夹(缺)": {
        "folder e2c7": 0xE2C7,
        "folder_open e2c8": 0xE2C8,
        "photo_library e413": 0xE413,
        "collections e3b6": 0xE3B6,
        "image e3f4": 0xE3F4,
        "photo e412": 0xE412,
        "insert_photo e24f": 0xE24F,
    },
}

with io.open("tools/icon_replacement_candidates.txt", "w", encoding="utf-8") as out:
    for group, cands in CANDIDATES.items():
        out.write("=== %s ===\n" % group)
        for name, c in cands.items():
            out.write("   U+%04X  %-28s %s\n" % (c, name, "OK ✓" if c in cp else "missing"))
        avail = ["%X" % x for x in sorted(c for c in cands.values() if c in cp)]
        out.write("   -> 可用: %s\n\n" % " ".join(avail))

print("done -> tools/icon_replacement_candidates.txt")
