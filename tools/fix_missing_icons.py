#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""问题3 修复: QML 中引用的 15 个码点在 bundled MaterialIcons-Regular.ttf
(v1.017, 2019-05, PUA 仅 U+E000..U+F23B 1506 glyph) 中不存在, Android 渲染成
方框 (用户截图 1.jpg "徒步路线/自驾游/装备清单 无图标").

策略: 只替换码点为字体中确实存在的旧版官方码点, 不改语义标签.
行尾策略: 以 newline='' 读/写, 逐文件保留原行尾 (零 EOL 变更).
输出: 小写码点 (与代码库既有风格 "\ue88a" 一致).
"""
import glob
import io
import re

# 旧码点 -> (新码点, 官方图标名, 用途)   所有新码点已由 find_icon_replacements.py 验证存在
MAP = {
    "e50f": ("e536", "directions_walk", "徒步/hiking"),
    "e1d7": ("e531", "directions_car", "自驾/car"),
    "e6b1": ("e153", "checklist", "检查/步骤/fact_check"),
    "e6e3": ("e922", "timeline", "路线/route"),
    "e1f7": ("e989", "local_gas_station", "加油/补给/费用"),
    "e4e0": ("e01d", "equalizer", "统计/条数"),
    "e1f6": ("e53f", "luggage", "背包/backpack"),
    "e2dc": ("e239", "emoji_nature", "蘑菇/菌类"),
    "e205": ("e406", "nature", "叶子/植物/eco"),
    "e9d5": ("e6dd", "fitness_center", "重量/monitor_weight"),
    "e2d0": ("e878", "event", "日期/季节"),
    "e1cc": ("e878", "event", "活跃月份"),
    "e1eb": ("e1bd", "widgets", "材料/work"),
    "e1f9": ("e1b5", "wb_sunny", "环境急症"),
    "e2d4": ("e2c8", "folder_open", "相册/文件夹"),
}

# 预编译: 匹配 \u 后跟 4 位 hex (e 打头), 大小写不敏感, 且后面不接第 5 位 hex
PATTERNS = {}
for old in MAP:
    pat = re.compile("\\\\u[eE]" +
                     "".join("[%s%s]" % (c, c.upper()) for c in old[1:]) +
                     "(?![0-9a-fA-F])")
    PATTERNS[old] = pat

changed = {}
TOTAL = 0

for f in sorted(glob.glob("qml/**/*.qml", recursive=True)):
    with io.open(f, encoding="utf-8", newline="") as fh:
        src = fh.read()
    out = src
    per_file = 0
    for old, (new, name, use) in MAP.items():
        out, n = PATTERNS[old].subn("\\\\u" + new, out)
        per_file += n
    if per_file:
        # newline="" 写出: 字符串里原有 \r\n / \n 原样落盘
        with io.open(f, "w", encoding="utf-8", newline="") as fh:
            fh.write(out)
        changed[f] = per_file
        TOTAL += per_file

for f, n in sorted(changed.items()):
    print("%-58s %d" % (f.replace("\\", "/"), n))
print("TOTAL %d sites, %d files" % (TOTAL, len(changed)))
