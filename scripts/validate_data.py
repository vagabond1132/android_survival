# -*- coding: utf-8 -*-
"""数据完整性校验 — 全部 JSON 文件"""
import json, os, sys
from collections import Counter

DATA_DIR = r"H:/AI_Claude/work_dir/app/assets/data"

def load(name):
    with open(os.path.join(DATA_DIR, name), encoding='utf-8') as f:
        return json.load(f)

def check_routes():
    data = load('routes.json')
    routes = data['routes'] if isinstance(data, dict) else data
    print(f"\n=== routes.json ===  共 {len(routes)} 条")
    provinces = Counter(r.get('province','(空)') for r in routes)
    for p, c in sorted(provinces.items(), key=lambda x: -x[1]):
        print(f"  {p}: {c}")
    diff = Counter(r.get('difficulty', 0) for r in routes)
    print(f"  难度分布: {dict(sorted(diff.items()))}")
    # 异常字段
    bad = []
    for r in routes:
        if not r.get('id'): bad.append(f"{r.get('name','?')}: 缺 id")
        if not r.get('name'): bad.append(f"{r.get('id','?')}: 缺 name")
        if not r.get('province'): bad.append(f"{r.get('name','?')}: 缺 province")
        if not (1 <= r.get('difficulty',0) <= 5): bad.append(f"{r.get('name','?')}: 难度越界 {r.get('difficulty')}")
        if not r.get('routeNature'): bad.append(f"{r.get('name','?')}: 缺 routeNature")
    if bad:
        print(f"  ⚠ 异常 {len(bad)} 条:")
        for b in bad[:20]: print(f"    - {b}")
    else:
        print(f"  ✓ 字段完整")

def check_travel():
    data = load('travel.json')
    items = data['travels'] if isinstance(data, dict) and 'travels' in data else data
    if isinstance(data, dict):
        items = data.get('travels') or data.get('routes') or list(data.values())[0]
    print(f"\n=== travel.json ===  共 {len(items)} 条")
    provinces = Counter(r.get('province','(空)') for r in items)
    for p, c in sorted(provinces.items(), key=lambda x: -x[1]):
        print(f"  {p}: {c}")
    bad = [f"{r.get('name','?')}: 缺 id" for r in items if not r.get('id')]
    bad += [f"{r.get('id','?')}: 缺 name" for r in items if not r.get('name')]
    if bad:
        print(f"  ⚠ {len(bad)}: {bad[:5]}")
    else:
        print(f"  ✓ 字段完整")

def check_equipment():
    base = load('equipment_base.json')
    rules = load('equipment_rules.json')
    base_items = base if isinstance(base, list) else base.get('items', [])
    print(f"\n=== equipment_base.json ===  共 {len(base_items)} 条")
    cats = Counter(i.get('category','(空)') for i in base_items)
    for c, n in sorted(cats.items(), key=lambda x: -x[1]):
        print(f"  {c}: {n}")
    rules_list = rules if isinstance(rules, list) else rules.get('rules', [])
    print(f"\n=== equipment_rules.json ===  共 {len(rules_list)} 条规则")

def check_field_guide():
    total = 0
    # 2026-09-24: photo_sources 覆盖度检查. 该字段是图册(ImageFetcherService)唯一的
    #   检索词来源; 一旦缺失, 详情页图册直接 return 不发起下载 → 永远"暂无图片".
    #   历史上 animals/insects/mushrooms 全量为空且长期无人发现, 故纳入常规校验.
    missing_ps = []
    for fn, key in [('field_guide_plants.json','plants'),
                    ('field_guide_animals.json','animals'),
                    ('field_guide_insects.json','insects'),
                    ('field_guide_mushrooms.json','mushrooms')]:
        data = load(fn)
        items = data if isinstance(data, list) else data.get(key, data.get('items', data.get('species', [])))
        print(f"\n=== {fn} ===  共 {len(items)} 条")
        if items:
            sample = items[0]
            print(f"  字段示例: id={sample.get('id','-')[:8]}... name={sample.get('commonName') or sample.get('name','-')[:20]}")
        no_ps = [i.get('id','?') for i in items if not i.get('photo_sources')]
        print(f"  photo_sources 覆盖: {len(items)-len(no_ps)}/{len(items)}")
        missing_ps += [(fn, i) for i in no_ps]
        total += len(items)
    if missing_ps:
        print(f"\n  ⚠ photo_sources 缺失 {len(missing_ps)} 条 (图册将无图):")
        for fn, i in missing_ps[:20]:
            print(f"    - {fn}: {i}")
        print("    修复: python scripts/add_photo_sources.py")
    else:
        print(f"\n  ✓ photo_sources 全部覆盖")
    print(f"\n图鉴总条目: {total}")

def check_danger_species():
    data = load('danger_species.json')
    items = data if isinstance(data, list) else data.get('species', data.get('items', []))
    print(f"\n=== danger_species.json ===  共 {len(items)} 条")
    types = Counter(i.get('type','(空)') for i in items)
    for t, n in sorted(types.items(), key=lambda x: -x[1]):
        print(f"  {t}: {n}")

def check_firstaid():
    data = load('firstaid_entries.json')
    items = data if isinstance(data, list) else data.get('entries', data.get('items', []))
    print(f"\n=== firstaid_entries.json ===  共 {len(items)} 条")
    cats = Counter(i.get('category','(空)') for i in items)
    for c, n in sorted(cats.items(), key=lambda x: -x[1]):
        print(f"  {c}: {n}")

def check_knots():
    data = load('knots.json')
    items = data if isinstance(data, list) else data.get('knots', data.get('items', []))
    print(f"\n=== knots.json ===  共 {len(items)} 条结")

def check_survival():
    data = load('survival_items.json')
    items = data if isinstance(data, list) else data.get('items', data.get('survivals', []))
    print(f"\n=== survival_items.json ===  共 {len(items)} 条")

def check_checklists():
    data = load('checklists.json')
    items = data if isinstance(data, list) else data.get('checklists', data.get('items', []))
    print(f"\n=== checklists.json ===  共 {len(items)} 条清单")
    for cls in items[:5]:
        print(f"  - {cls.get('name','?')}  分类:{cls.get('category','?')}  装备数:{len(cls.get('items', []))}")

if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    check_routes()
    check_travel()
    check_equipment()
    check_field_guide()
    check_danger_species()
    check_firstaid()
    check_knots()
    check_survival()
    check_checklists()