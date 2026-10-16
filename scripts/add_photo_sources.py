#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
给 JSON 加 photo_sources 字段 (检索词, 不是真实 URL)

2026-09-24: 覆盖全量图鉴. 旧版只填了 danger_species(33) + plants 的 wild_vegetable(38),
  导致 animals(50) / insects(30) / mushrooms(30) 以及 plants 其余类目全部没有检索词,
  详情页图册因 `photoSources.length === 0` 提前 return, 永远不发起下载 → "暂无图片".
  现在 4 个 field_guide_*.json 全类目 + danger_species 全量补齐.
  已有 photo_sources 的条目保持不变 (幂等).
"""
import json
import re
from pathlib import Path

DATA = Path(r"H:\AI_Claude\work_dir\app\assets\data")


def make_sources(sci_name: str, common_name: str, kingdom_hint: str = "") -> list:
    """生成检索词列表 (从精确到宽泛)

    Wikimedia Commons 以学名索引最可靠, 学名放最前; 中文名 + 类别词兜底.
    kingdom_hint 用于中文名兜底的类别词 (plant/animal/insect/mushroom),
    避免给"眼镜蛇"拼出 "眼镜蛇 plant" 这种错类别检索词.
    """
    out = []
    if sci_name:
        out.append(sci_name)
        # genus + species 双名法缩写 (部分图有命名人, 命中率高)
        m = re.match(r"^([A-Z][a-z]+)\s+([a-z]+)", sci_name)
        if m:
            out.append(f"{m.group(1)} {m.group(2)}")
    if common_name:
        out.append(f"{common_name} {kingdom_hint}".strip())
    return out


def process(json_file: str, key: str, kingdom_hint: str, filter_fn=None):
    p = DATA / json_file
    with open(p, "r", encoding="utf-8") as f:
        data = json.load(f)
    items = data.get(key, [])
    added = 0
    kept = 0
    for e in items:
        if filter_fn and not filter_fn(e):
            continue
        # 幂等: 已有 photo_sources 的不动
        if e.get("photo_sources"):
            kept += 1
            continue
        sources = make_sources(e.get("scientific_name", ""),
                               e.get("common_name", ""),
                               kingdom_hint)
        if sources:
            e["photo_sources"] = sources
            added += 1
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"{json_file}: 新增 {added} 条, 保留 {kept} 条 (总 {len(items)})")
    return added


# 危险物种 (legacy): 全加
process("danger_species.json", "species", "animal")

# 四大类图鉴: 全量补齐
process("field_guide_plants.json", "plants", "plant")
process("field_guide_animals.json", "animals", "animal")
process("field_guide_insects.json", "insects", "insect")
process("field_guide_mushrooms.json", "mushrooms", "mushroom")