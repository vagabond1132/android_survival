# -*- coding: utf-8 -*-
import json, os
DATA_DIR = r"H:/AI_Claude/work_dir/app/assets/data"

for fn in ['field_guide_plants.json','field_guide_animals.json','field_guide_insects.json','field_guide_mushrooms.json']:
    with open(os.path.join(DATA_DIR, fn), encoding='utf-8') as f:
        data = json.load(f)
    print(f"\n{fn}: type={type(data).__name__}")
    if isinstance(data, dict):
        for k, v in data.items():
            if isinstance(v, list):
                print(f"  key '{k}': list[{len(v)}], 样例字段: {list(v[0].keys())[:8] if v else '空'}")
                if v:
                    print(f"    第1条: name={v[0].get('commonName') or v[0].get('name','-')[:30]}")
                break
            else:
                print(f"  key '{k}': {type(v).__name__}")