# -*- coding: utf-8 -*-
import json, os
from collections import Counter

DATA_DIR = r"H:/AI_Claude/work_dir/app/assets/data"

# field guide — 各自独立 key
for fn, key in [
    ('field_guide_plants.json','plants'),
    ('field_guide_animals.json','animals'),
    ('field_guide_insects.json','insects'),
    ('field_guide_mushrooms.json','mushrooms'),
]:
    with open(os.path.join(DATA_DIR, fn), encoding='utf-8') as f:
        data = json.load(f)
    items = data[key]
    print(f"\n=== {fn} ===  共 {len(items)} 条")
    cats = Counter(i.get('category','(空)') for i in items)
    for c, n in sorted(cats.items(), key=lambda x: -x[1]):
        print(f"  {c}: {n}")
    danger = Counter(i.get('danger_level','(空)') for i in items)
    print(f"  危险等级分布: {dict(danger)}")
    # 字段完整
    bad = []
    for i in items:
        if not i.get('id'): bad.append(f"{i.get('common_name','?')}: 缺 id")
        if not i.get('common_name'): bad.append(f"{i.get('id','?')}: 缺 common_name")
    if bad: print(f"  ⚠ {bad[:5]}")
    else: print(f"  ✓ 字段完整")

# danger_species — 看完整结构
with open(os.path.join(DATA_DIR, 'danger_species.json'), encoding='utf-8') as f:
    ds = json.load(f)
print(f"\n=== danger_species.json ===")
print(f"  顶层 type: {type(ds).__name__}")
if isinstance(ds, dict):
    for k, v in ds.items():
        print(f"  key '{k}': {type(v).__name__}", end="")
        if isinstance(v, list) and v:
            print(f" len={len(v)}, 样例字段: {list(v[0].keys())[:10]}")
            print(f"    第1条: {v[0]}")
        else:
            print()
    items = ds.get('species') or ds.get('items') or list(ds.values())[0]
    types = Counter(i.get('type','(空)') for i in items)
    print(f"  type 分布: {dict(types)}")
    print(f"  共 {len(items)} 条")

# firstaid — 看完整结构
with open(os.path.join(DATA_DIR, 'firstaid_entries.json'), encoding='utf-8') as f:
    fa = json.load(f)
print(f"\n=== firstaid_entries.json ===")
if isinstance(fa, dict):
    for k, v in fa.items():
        print(f"  key '{k}': {type(v).__name__}", end="")
        if isinstance(v, list) and v:
            print(f" len={len(v)}")
            print(f"    第1条字段: {list(v[0].keys())[:10]}")
            print(f"    第1条: {v[0]}")
        else:
            print()
    items = fa.get('entries') or fa.get('items') or list(fa.values())[0]
else:
    items = fa

cats = Counter(i.get('category', i.get('categoryName', '(空)')) for i in items)
print(f"  category 分布: {dict(cats)}")
levels = Counter(i.get('urgency', i.get('priority', '(空)')) for i in items)
print(f"  urgency 分布: {dict(levels)}")