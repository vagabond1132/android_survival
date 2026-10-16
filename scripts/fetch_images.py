#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 Wikimedia Commons 批量下载危险物种 + 常见植物的图片
- 危险物种 -> assets/images/danger/<id>.jpg
- 常见植物 -> assets/images/plants/<id>.jpg
- 同时更新对应 JSON 的 photos 字段

依赖: 标准库 (urllib, json)
"""

import json
import os
import re
import time
import urllib.request
import urllib.parse
import urllib.error
from pathlib import Path

UA = "OutdoorSurvivalApp/1.0 (contact: github batch-image-fetcher; python-urllib)"
API = "https://commons.wikimedia.org/w/api.php"
SLEEP = 0.6  # 请求间隔, 避免触发限流

ROOT = Path("/h/AI_Claude/work_dir/app")
DATA = ROOT / "assets/data"
IMG = ROOT / "assets/images"


def http_get_json(url, timeout=15):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def http_download(url, out, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        with open(out, "wb") as f:
            f.write(r.read())


# 关键词清洗: 中文常用词 + 学术词, 避免搜出无关图
STOP = {
    "的", "一", "是", "在", "不", "了", "和", "有", "也", "就", "都", "很",
    "植物", "野", "生", "草", "本", "种", "类", "属", "亚", "变", "型",
}


def search_files(query, limit=3):
    """按文件名搜索 (srnamespace=6 是 File 命名空间)"""
    url = (f"{API}?action=query&format=json&list=search"
           f"&srsearch={urllib.parse.quote(query)}"
           f"&srnamespace=6&srlimit={limit}&srprop=snippet")
    try:
        d = http_get_json(url)
    except Exception as e:
        print(f"    search err: {e}")
        return []
    return [h["title"] for h in d.get("query", {}).get("search", [])]


def thumb_url(title, width=800):
    """取 File:XXX 的 thumburl (width 像素宽)"""
    url = (f"{API}?action=query&format=json&prop=imageinfo"
           f"&titles={urllib.parse.quote(title)}"
           f"&iiprop=url&iiurlwidth={width}")
    try:
        d = http_get_json(url)
    except Exception as e:
        print(f"    imageinfo err: {e}")
        return None
    pages = d.get("query", {}).get("pages", {})
    for p in pages.values():
        infos = p.get("imageinfo", [])
        if infos:
            return infos[0].get("thumburl") or infos[0].get("url")
    return None


def is_plantish(title):
    """粗筛: 标题包含植物学相关词, 或明确图片格式 (.jpg/.jpeg/.png)"""
    t = title.lower()
    if not (t.endswith(".jpg") or t.endswith(".jpeg") or t.endswith(".png")):
        return False
    bad = ["map", "logo", "icon", "diagram", "chart", "graph", "anatomy_diagram",
           "schematic", "sketch", "drawing", "coat_of_arms", "flag",
           "distribution", "range_map"]
    return not any(b in t for b in bad)


def fetch_one(sci_name, common_name):
    """尝试多种 query 取第一张合适的图"""
    queries = []
    if sci_name and len(sci_name) > 3:
        queries.append(sci_name)
        # 双名法 genus+species
        m = re.match(r"^([A-Z][a-z]+)\s+([a-z]+)", sci_name)
        if m:
            queries.append(f"{m.group(1)} {m.group(2)}")
    # 中文常见名作为兜底
    if common_name and len(common_name) >= 2:
        queries.append(f"{common_name} plant")

    for q in queries:
        hits = search_files(q, limit=4)
        for h in hits:
            if is_plantish(h):
                url = thumb_url(h)
                if url:
                    return url, h
        time.sleep(SLEEP)

    return None, None


def process_species(json_file, key, kind_dir):
    """处理单个 JSON 文件"""
    p = DATA / json_file
    with open(p, "r", encoding="utf-8") as f:
        data = json.load(f)
    items = data.get(key, [])
    print(f"\n=== {json_file}: {len(items)} 条 ===")

    results = []
    for i, e in enumerate(items):
        sid = e.get("id", "")
        sci = e.get("scientific_name", "")
        cn = e.get("common_name", "")
        out_path = IMG / kind_dir / f"{sid}.jpg"
        if out_path.exists():
            size = out_path.stat().st_size
            if size > 1000:  # 已有图 (>1KB), 跳过
                print(f"  [{i+1}/{len(items)}] {sid} 已有图 ({size//1024}KB), 跳过")
                results.append((sid, str(out_path.relative_to(ROOT)).replace("\\", "/")))
                continue

        url, title = fetch_one(sci, cn)
        if url:
            try:
                http_download(url, out_path)
                sz = out_path.stat().st_size
                print(f"  [{i+1}/{len(items)}] {sid} ✓ {title} ({sz//1024}KB)")
                rel = str(out_path.relative_to(ROOT)).replace("\\", "/")
                results.append((sid, rel))
            except Exception as ex:
                print(f"  [{i+1}/{len(items)}] {sid} 下载失败: {ex}")
        else:
            print(f"  [{i+1}/{len(items)}] {sid} ✗ 未找到 ({sci})")

        time.sleep(SLEEP)

    return results


def main():
    danger_results = process_species("danger_species.json", "species", "danger")
    plant_results = process_species("field_guide_plants.json", "plants", "plants")
    print(f"\n=== 下载完成: 危险 {len(danger_results)}, 植物 {len(plant_results)} ===")


if __name__ == "__main__":
    main()