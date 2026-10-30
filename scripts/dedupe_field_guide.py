#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A35 图鉴同名重复合并 (2026-10-28).

assets/data/field_guide_{plants,animals,insects,mushrooms}.json 里有 30 组
「同一界内 common_name + scientific_name 完全相同」的记录, 外加 1 组跨界同名
(灵芝同时挂在 plants 和 mushrooms), 以及 3 组同名不同种 (山蛭 / 毒芹 / 白条草蜥).
重复是历次 add_plants_*.js / add_animals_*.js 补数据时按不同 id 各写一遍造成的:
同一物种两条记录一条字段全一条字段缺, 于是图鉴列表出现两行同名, 「易混种」
和统计数也被虚增.

为什么必须合并而不是留两条: FieldGuideIndex::loadAll() 之后还有旧 danger_species.json
的兼容加载, 它按 **id** 去重 (src/species/FieldGuideIndex.cpp:68). 两条同名不同 id
的条目在去重逻辑看来是两个物种, 谁也不会被跳过.

跑法 (容器内, /project = app 目录):
    docker exec -i outdoor-survival-builder python3 /project/scripts/dedupe_field_guide.py
    docker exec -i outdoor-survival-builder python3 /project/scripts/dedupe_field_guide.py --check

--check 只判定不写文件, 合并后用它在门禁里守住"不再有同名重复".
"""

import argparse
import collections
import json
import os

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "assets", "data")

KINGDOM_FILES = [
    ("plants", "field_guide_plants.json"),
    ("animals", "field_guide_animals.json"),
    ("insects", "field_guide_insects.json"),
    ("mushrooms", "field_guide_mushrooms.json"),
]

# 跨界同名特例. 灵芝 (Ganoderma lucidum) 是真菌, 原来同时有 plant_ganoderma
# (kingdom=plantae, category=medicinal, 字段厚) 和 mushroom_ganoderma
# (kingdom=fungi, category=edible_mushroom, 内容很薄). 留在植物界是错的,
# 但 edible_mushroom 同样是假读数 —— 它自己 protective_gear 写着"木质化不可食,药用".
# 所以: id/界 固定在 mushroom_ganoderma, 内容按通用规则并过来, 类别改 medicinal
# (speciesCategoryLabel 已有该键中文, 不会把英文键印到页面上).
CROSS_KINGDOM = [dict(keep="mushroom_ganoderma", drop=["plant_ganoderma"],
                      category="medicinal")]

# 同名但不同种: 只改显示名, id 与 scientific_name 一律不动.
#   毒芹  : Flora China 里 Conium maculatum 正名「毒参」(毒参属), Cicuta virosa 才是「毒芹」
#   山蛭  : animal_hirudo 是 Haemadipsa 属级条目, animal_haemadipsa 是 H. japonica 这个种
#   白条草蜥: Takydromus wolteri 正名白条草蜥; T. septentrionalis 正名北草蜥
RENAME = [
    dict(id="plant_conium", old="毒芹", new="毒参"),
    dict(id="animal_haemadipsa", old="山蛭", new="日本山蛭"),
    dict(id="animal_takydromus_septentrionalis", old="白条草蜥", new="北草蜥"),
]

# 这些 id 被 field_guide 之外的数据文件引用, 删掉会让引用断链:
#   routes.json 的物种列表按 id 查, 查不到就少一行
#   danger_species.json 里同 id 的旧条目, loadAll() 是"guide 里已有此 id 就跳过";
#     guide 里一旦没有, 那条 legacy 记录以 kingdom="" 落进 m_all —— 四个界的列表都不含它,
#     这条物种从图鉴里直接消失.
# 因此选保留条目时, 被外部引用的 id 优先.
EXTERNAL_REF_FILES = ["routes.json", "danger_species.json", "survival_items.json",
                      "knots.json", "first_aid_entries.json", "drive_routes.json"]

TEXT_FIELDS = ["description", "source", "reviewer", "first_aid_id", "taste",
               "harvest_tips", "nutrition", "venom_type", "venom_location",
               "active_time", "mortality_rate", "poisoning_type", "protection_level"]
INT_MAX_FIELDS = ["danger_level", "attack_distance_cm", "max_elevation", "latency_hours"]
INT_MIN_FIELDS = ["min_elevation"]
LIST_FIELDS = ["alias", "features", "distribution", "habitats", "active_months",
               "symptoms", "look_alike", "protective_gear", "route_associations",
               "images", "photo_sources", "edible_part", "edible_months",
               "edible_method", "hibernation_months"]
DICT_FIELDS = ["first_aid_links", "representative_color"]
BOOL_FIELDS = ["raw_edible", "must_cook"]


def is_empty(v):
    return v is None or v == "" or v == [] or v == {} or v == 0


def richness(rec):
    return sum(1 for k, v in rec.items() if not k.startswith("_") and not is_empty(v))


def external_refs(ids):
    hits = collections.Counter()
    for fname in EXTERNAL_REF_FILES:
        path = os.path.join(DATA_DIR, fname)
        if not os.path.exists(path):
            continue
        blob = open(path, encoding="utf-8").read()
        for sid in ids:
            if '"%s"' % sid in blob:
                hits[sid] += 1
    return hits


def load():
    return {fname: json.load(open(os.path.join(DATA_DIR, fname), encoding="utf-8"))
            for _, fname in KINGDOM_FILES}


def rows(datasets):
    for key, fname in KINGDOM_FILES:
        for rec in datasets[fname][key]:
            rec["_key"] = key
            yield key, rec


def find_dup_groups(datasets):
    """界内 (common_name, scientific_name) 完全相同的组, 只有 >1 条的"""
    g = collections.defaultdict(list)
    for key, rec in rows(datasets):
        g[(key, rec["common_name"], rec["scientific_name"])].append(rec)
    return {k: v for k, v in g.items() if len(v) > 1}


def find_name_conflicts(datasets):
    """同名跨界的 与 同名不同 scientific_name 的 (两者都是"一行两个物种"的观感)"""
    by_name = collections.defaultdict(list)
    for key, rec in rows(datasets):
        by_name[rec["common_name"]].append((key, rec))
    cross = {}
    homonym = {}
    for name, items in by_name.items():
        keys = {k for k, _ in items}
        if len(keys) > 1:
            cross[name] = items
        if len({r["scientific_name"] for _, r in items}) > 1:
            homonym[name] = items
    return cross, homonym


def pick_survivor(group, refs):
    return sorted(group, key=lambda r: (-refs.get(r["id"], 0), -richness(r), r["id"]))[0]


def item_key(it):
    # look_alike / route_associations 是 dict 列表, 不能直接进 set
    if isinstance(it, dict):
        return json.dumps(it, sort_keys=True, ensure_ascii=False)
    return it


def merge_into(survivor, others):
    """把 others 的内容并进 survivor (原地改), 返回字段增量说明列表"""
    notes = []
    for field in LIST_FIELDS:
        base = list(survivor.get(field) or [])
        seen = set(item_key(x) for x in base)
        added = []
        for o in others:
            for item in (o.get(field) or []):
                if item_key(item) not in seen:
                    seen.add(item_key(item))
                    added.append(item)
        if added:
            survivor[field] = base + added
            notes.append("%s+%d" % (field, len(added)))
    for field in TEXT_FIELDS:
        best = survivor.get(field) or ""
        for o in others:
            v = o.get(field) or ""
            if len(v) > len(best):
                best = v
        if survivor.get(field, "") != best:
            survivor[field] = best
            notes.append(field + ":longer")
    for field in INT_MAX_FIELDS:
        vals = [survivor.get(field)] + [o.get(field) for o in others]
        vals = [v for v in vals if isinstance(v, (int, float))]
        if vals and survivor.get(field) != max(vals):
            survivor[field] = max(vals)
            notes.append(field + ":max")
    for field in INT_MIN_FIELDS:
        vals = [survivor.get(field)] + [o.get(field) for o in others]
        vals = [v for v in vals if isinstance(v, (int, float))]
        if vals and survivor.get(field) != min(vals):
            survivor[field] = min(vals)
            notes.append(field + ":min")
    for field in DICT_FIELDS:
        cur = survivor.get(field) or {}
        for o in others:
            for k, v in (o.get(field) or {}).items():
                cur.setdefault(k, v)
        if cur:
            survivor[field] = cur
    for field in BOOL_FIELDS:
        for o in others:
            if field not in survivor and field in o:
                survivor[field] = o[field]
                notes.append(field + ":fill")
    return notes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只判定, 不写文件")
    args = ap.parse_args()

    datasets = load()
    by_id = {rec["id"]: rec for _, rec in rows(datasets)}
    refs = external_refs(list(by_id))
    report = []
    removed = set()
    corpus = set(by_id)

    # 易混条目按 id 跳转, 这里统一算"指向库里没有的条目"的 id
    def dangling_ids():
        return sorted({e["id"] for _, rec in rows(datasets)
                       for e in (rec.get("look_alike") or [])
                       if isinstance(e, dict) and e.get("id") and e["id"] not in corpus})

    dup_groups = find_dup_groups(datasets)
    drop_to_kept = {}
    for (key, cname, sname), group in sorted(dup_groups.items()):
        survivor = pick_survivor(group, refs)
        others = [r for r in group if r["id"] != survivor["id"]]
        notes = merge_into(survivor, others)
        removed.update(r["id"] for r in others)
        drop_to_kept.update((r["id"], survivor["id"]) for r in others)
        report.append("MERGE  %-8s %s / %s -> 留 %s (外部引用 %d) 删 %s [%s]" % (
            key, cname, sname, survivor["id"], refs.get(survivor["id"], 0),
            ",".join(r["id"] for r in others), " ".join(notes) or "无字段增量"))

    for spec in CROSS_KINGDOM:
        keep_rec = by_id.get(spec["keep"])
        if keep_rec is None:
            report.append("SKIP   跨界 %s 已不在库里" % spec["keep"])
            continue
        group = [by_id[i] for i in spec["drop"] if i in by_id]
        if not group:
            report.append("SKIP   跨界 %s 的 %s 已不在库里" % (spec["keep"], spec["drop"]))
            continue
        notes = merge_into(keep_rec, group)
        keep_rec["category"] = spec["category"]
        removed.update(r["id"] for r in group)
        drop_to_kept.update((r["id"], keep_rec["id"]) for r in group)
        report.append("CROSS  %s %s / %s -> 留 %s (界=%s 类=%s) 删 %s [%s]" % (
            keep_rec["_key"], keep_rec["common_name"], keep_rec["scientific_name"],
            keep_rec["id"], keep_rec["kingdom"], keep_rec["category"],
            ",".join(spec["drop"]), " ".join(notes) or "无字段增量"))

    renamed = 0
    for spec in RENAME:
        rec = by_id.get(spec["id"])
        if rec is None:
            report.append("SKIP   改名 %s 已不在库里" % spec["id"])
        elif rec["common_name"] == spec["new"]:
            report.append("SKIP   改名 %s 已是「%s」" % (spec["id"], spec["new"]))
        elif spec["new"] in {r["common_name"] for _, r in rows(datasets)
                             if r["id"] not in removed}:
            # 只跟"合并后留下来的记录"比撞名: 即将被并掉的那条同名记录不算冲突
            report.append("SKIP   改名 %s -> 「%s」会撞名" % (spec["id"], spec["new"]))
        else:
            rec["common_name"] = spec["new"]
            renamed += 1
            report.append("RENAME %-8s 「%s」->「%s」 (%s)" % (
                rec["_key"], spec["old"], spec["new"], spec["id"]))

    for key, fname in KINGDOM_FILES:
        datasets[fname][key] = [r for r in datasets[fname][key] if r["id"] not in removed]

    # look_alike 是按 id 跳转的 (FieldGuideDetailPage.qml:1010 的 _clickable),
    # 被合并掉的 id 必须重指向保留条目, 否则点"易混"跳到不存在的物种.
    # 同名不同种的 look_alike.name 不动 —— 两条记录的 common_name 本来就一样.
    remap_count = 0
    dedup_count = 0
    for _, rec in rows(datasets):
        la = rec.get("look_alike") or []
        if la:
            out = []
            seen_id = set()
            for e in la:
                if not isinstance(e, dict) or not e.get("id"):
                    out.append(e)   # 只写了名字的条目 (不可跳转) 原样保留
                    continue
                eid = e["id"]
                if eid in removed:
                    e = dict(e)
                    e["id"] = drop_to_kept[eid]
                    remap_count += 1
                if e["id"] in seen_id:
                    dedup_count += 1
                    continue
                seen_id.add(e["id"])
                out.append(e)
            rec["look_alike"] = out
    corpus -= removed
    # 剩下的悬空 id 是合并前就有的: 全是属级指针 (鹨属 / 沙蜥属 / 壁虎属 …),
    # 库里压根没有这个属的条目. FieldGuideDetailPage.qml:1010 的 _clickable 只看
    # "有没有 id", 于是点下去 getById 返回 {} → 详情页字段全空
    # (跟 FieldGuideIndex.cpp:51 记的那次事故同一个形状).
    # 处置: 摘掉 id、留着 name/distinction —— 行照样显示"鹨属(近缘) 区别:…",
    # 只是不再是个通向空白页的假链接 (「不给假读数」).
    stripped = 0
    for _, rec in rows(datasets):
        for e in (rec.get("look_alike") or []):
            if isinstance(e, dict) and e.get("id") and e["id"] not in corpus:
                del e["id"]
                stripped += 1
    dangling_all = dangling_ids()
    left = find_dup_groups(datasets)
    cross, homonym = find_name_conflicts(datasets)
    broken = sorted(sid for sid in refs if sid in removed)

    print("\n".join(report))
    print("-" * 72)
    print("合并删除 %d 条 (界内 %d 组 + 跨界 %d), 改名 %d 条" % (
        len(removed), len(dup_groups), len(CROSS_KINGDOM), renamed))
    for key, fname in KINGDOM_FILES:
        print("  %-9s %d 条" % (key, len(datasets[fname][key])))
    print("残留: 界内重名 %d 组 / 跨界同名 %d / 同名不同种 %d / 外部引用断链 %d / 易混悬空 id %d" % (
        len(left), len(cross), len(homonym), len(broken), len(dangling_all)))
    print("易混 id 重指向 %d 处, 同一条内去重 %d 处" % (remap_count, dedup_count))
    if stripped:
        print("NOTE 摘掉 %d 处指向库里不存在条目的易混 id (行仍显示, 只是不再是假链接)" % stripped)
    if left or cross or homonym or broken or dangling_all:
        print("FAIL 界内=%s 跨界=%s 同种名=%s 断链=%s 悬空=%s" % (
            list(left), list(cross), list(homonym), broken, dangling_all))
        return 1
    if args.check:
        print("CHECK OK: 无同名重复, 未写文件")
        return 0

    for key, fname in KINGDOM_FILES:
        obj = datasets[fname]
        obj["updated_at"] = "2026-10-28"
        obj[key] = [{k: v for k, v in r.items() if not k.startswith("_")}
                    for r in obj[key]]
        path = os.path.join(DATA_DIR, fname)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(obj, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print("WROTE %s (%d 条)" % (fname, len(obj[key])))
    return 0



if __name__ == "__main__":
    main()
