#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
审计 (并可选修复) 徒步路线 / 自驾游线路的导航起终点字段.

只做"不臆造地理信息"的确定性修复:
  R1 山名重复拼接   "华山华山山门" → "华山山门" (68 条)

审计口径里剩下的问题都不落盘, 因为修不出正确性, 只能在报告里点名:
  * 坐标 <=2 位小数 (约 1km) —— 要更准必须重新取数
  * 起终点同坐标 / 起终点同名 —— 方向区分交给展示层 ("起点:"/"终点:" 前缀
    与地图 S/E marker), 不把 "（起点）" 写进地名: 该串会同时被当成导航
    关键字发给高德, 加括号只会让检索更差.
  * 自驾游 startName/endName 全部只到城市级 —— 库里没有更细字段

坐标一律不动.

用法:
    python3 scripts/audit_poi.py            # 只审计, 打印报告
    python3 scripts/audit_poi.py --apply    # 审计 + 原地改写 assets/data/routes.json
"""
import json
import sys
import collections

ROUTES = "assets/data/routes.json"
TRAVELS = "assets/data/travel.json"

# 中国陆域粗范围, 只用于把明显越界的坐标点名出来.
# 北纬上界取 53.6: 漠河以北的黑龙江主航道中心线约 53.56, 取 53.5 会把
# route_hlj_hei (53.52) 这种正常数据误报成越境.
CN_BBOX = (3.5, 53.6, 73.5, 135.0)


def dec_places(v):
    s = repr(float(v))
    if "." not in s:
        return 0
    return len(s.split(".")[1].rstrip("0"))


def dedupe_prefix(mountain, name):
    """R1: 去掉被拼了两遍的山名前缀."""
    name = (name or "").strip()
    m = (mountain or "").strip()
    if len(m) >= 2 and name.startswith(m + m):
        return m + name[2 * len(m):]
    return name


def audit_routes(routes):
    stats = collections.Counter()
    samples = collections.defaultdict(list)

    def hit(key, rid, detail):
        stats[key] += 1
        if len(samples[key]) < 6:
            samples[key].append("%s: %s" % (rid, detail))

    for t in routes:
        rid = t.get("id", "?")
        mountain = t.get("mountain", "") or ""
        th, te = t.get("trailhead") or {}, t.get("trailend") or {}
        hname, ename = (th.get("name") or "").strip(), (te.get("name") or "").strip()
        hlat, hlon = th.get("lat"), th.get("lon")
        elat, elon = te.get("lat"), te.get("lon")

        if not hname:
            hit("route_起点名空", rid, "mountain=%r" % mountain)
        if not ename:
            hit("route_终点名空", rid, "mountain=%r" % mountain)
        if dedupe_prefix(mountain, hname) != hname or dedupe_prefix(mountain, ename) != ename:
            hit("route_山名重复拼接", rid, "%s / %s" % (hname, ename))
        if hname and hname == ename:
            hit("route_起终点同名", rid, hname)
        if not (th.get("address") or "").strip():
            hit("route_起点地址空", rid, "")
        if not (te.get("address") or "").strip():
            hit("route_终点地址空", rid, "")

        for tag, lat, lon in (("起点", hlat, hlon), ("终点", elat, elon)):
            if lat in (None, 0) and lon in (None, 0):
                hit("route_%s坐标缺失" % tag, rid, "%s,%s" % (lat, lon))
                continue
            if not (CN_BBOX[0] <= lat <= CN_BBOX[1] and CN_BBOX[2] <= lon <= CN_BBOX[3]):
                hit("route_%s坐标越境" % tag, rid, "%s,%s" % (lat, lon))
            if dec_places(lat) <= 2 or dec_places(lon) <= 2:
                hit("route_坐标<=2位小数(约1km)", rid, "%s,%s" % (lat, lon))

        if (hlat, hlon) == (elat, elon):
            hit("route_起终点同坐标", rid, "%s,%s" % (hlat, hlon))

    return stats, samples


def audit_travels(travels):
    stats = collections.Counter()
    samples = collections.defaultdict(list)

    def hit(key, rid, detail):
        stats[key] += 1
        if len(samples[key]) < 6:
            samples[key].append("%s: %s" % (rid, detail))

    for t in travels:
        rid = t.get("id", "?")
        sn, en = (t.get("startName") or "").strip(), (t.get("endName") or "").strip()
        sc, ec = (t.get("startCity") or "").strip(), (t.get("endCity") or "").strip()
        pair = (t.get("startLat"), t.get("startLon"), t.get("endLat"), t.get("endLon"))

        if not sn:
            hit("travel_起点名空", rid, "")
        if not en:
            hit("travel_终点名空", rid, "")
        if sn and sn == sc:
            hit("travel_起点只是城市名", rid, "%s→%s" % (sn, en))
        if en and en == ec:
            hit("travel_终点只是城市名", rid, "%s→%s" % (sn, en))
        if all(isinstance(v, (int, float)) for v in pair) and pair[0] == pair[2] and pair[1] == pair[3]:
            hit("travel_环线起终同坐标", rid, "%s→%s" % (sn, en))
        if sn == en and pair[0] == pair[2] and pair[1] == pair[3]:
            hit("travel_起终点完全同源", rid, sn)
        for k in ("startLat", "startLon", "endLat", "endLon"):
            v = t.get(k)
            if isinstance(v, (int, float)) and (
                    not (CN_BBOX[0] <= v <= CN_BBOX[1] if k.endswith("Lat")
                         else CN_BBOX[2] <= v <= CN_BBOX[3])):
                hit("travel_%s越境" % k, rid, str(v))
    return stats, samples


def fix_routes(routes):
    """R1: 去掉被拼了两遍的山名前缀. 返回 (改动条数, 改动字段数)."""
    touched = 0
    renamed = 0
    for t in routes:
        mountain = t.get("mountain", "") or ""
        changed = False
        for side in ("trailhead", "trailend"):
            node = t.get(side)
            if not isinstance(node, dict):
                continue
            raw = (node.get("name") or "").strip()
            new = dedupe_prefix(mountain, raw)
            if new and new != raw:
                node["name"] = new
                renamed += 1
                changed = True
        if changed:
            touched += 1
    return touched, renamed


def main():
    apply_fix = "--apply" in sys.argv
    with open(ROUTES, encoding="utf-8") as f:
        rdoc = json.load(f)
    with open(TRAVELS, encoding="utf-8") as f:
        tdoc = json.load(f)
    routes, travels = rdoc["routes"], tdoc["routes"]

    rs, rsamp = audit_routes(routes)
    ts, tsamp = audit_travels(travels)

    print("=" * 72)
    print("起终点审计  routes=%d  travel=%d" % (len(routes), len(travels)))
    print("=" * 72)
    print("\n--- 徒步路线 (routes.json) ---")
    for k in sorted(rs):
        print("%-30s %5d   例: %s" % (k, rs[k], rsamp[k][0]))
    print("\n--- 自驾游 (travel.json) ---")
    for k in sorted(ts):
        print("%-30s %5d   例: %s" % (k, ts[k], tsamp[k][0]))

    if not apply_fix:
        print("\n(未修改任何文件; 加 --apply 才落盘)")
        return

    touched, renamed = fix_routes(routes)
    print("\n--- 已应用的修复 ---")
    print("R1 去掉重复山名前缀, 改动地名数: %d" % renamed)
    print("改动的路线条数: %d / %d" % (touched, len(routes)))
    with open(ROUTES, "w", encoding="utf-8") as f:
        json.dump(rdoc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("已写回 %s" % ROUTES)


if __name__ == "__main__":
    main()
