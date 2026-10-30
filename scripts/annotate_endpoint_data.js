#!/usr/bin/env node
// 端点数据补标 + 可证伪记录清理 (2026-10-27 #131)
//
//   ELECTRON_RUN_AS_NODE=1 "<Qoder.exe>" scripts/annotate_endpoint_data.js [--dry]
//
// 三件事, 全是机械规则, 不臆造任何地理信息:
//   1) 每条记录补 coord_precision_m / coord_source (travel.json 用驼峰同义键) ——
//      按坐标字面量的小数位数算"半格量化误差": 纬度 1 度 = 110948 m,
//      经度 1 度 = 111320·cos(lat) m; 一条记录四个数, 取最差的那个。
//      小数位数取自 JSON.parse 之后的最短表示, 所以 36.60 会被当成 1 位小数 ——
//      误差只会往"把精度说得更差"的方向偏, 不会反过来虚报精度。
//   2) E1: 性质是 穿越/单程 却给了起止同点(逐位相同) —— 这两件事不可能同时为真,
//      终点坐标是不可信的。处置: 删掉终点的 lat/lon, 保留名称与地址, 打
//      coord_unavailable 标记。(环线/往返 起止同点是正常的, 不动。)
//   3) E2: 两端直线距离 > 声明里程 + 2·(两端坐标精度之和) —— 路径长必然 ≥ 端点
//      直线距离, 超出量化误差范围即为可证伪。处置同 E1。
//      注意: 整数度坐标的半格就有 ±55 km, 绝大多数"里程比直线短"的样本落在这个
//      误差里, 属于"不精确"而不是"假", 因此由第 1 步的精度元数据去说, 不删坐标。
'use strict';
const fs = require('fs');
const path = require('path');

const DATA = path.join(__dirname, '..', 'assets', 'data');
const ROUTES = path.join(DATA, 'routes.json');
const TRAVEL = path.join(DATA, 'travel.json');
const DRY = process.argv.includes('--dry');
// 实测轨迹记录由 scripts/kml_to_routes.js 从两步路 KML 生成(输入在仓库外, 不进版本库),
// 这里只负责把它们并进来; 不给 --new 就是纯补标/清理。
const newIdx = process.argv.indexOf('--new');
const NEW_FILE = newIdx >= 0 ? process.argv[newIdx + 1] : null;

const M_PER_DEG_LAT = 110948;
const M_PER_DEG_EQ = 111320;

function decimals(v) {
    const s = String(v);
    if (s.indexOf('e') >= 0 || s.indexOf('E') >= 0) return 6;   // 极小值按最高精度算
    const dot = s.indexOf('.');
    return dot < 0 ? 0 : s.length - dot - 1;
}

// 单个数的半格量化误差(米)
function halfQuantumM(v, isLat) {
    const dp = decimals(v);
    const deg = Math.pow(10, -dp);
    const perDeg = isLat ? M_PER_DEG_LAT : M_PER_DEG_EQ * Math.abs(Math.cos(v * Math.PI / 180));
    return 0.5 * deg * perDeg;
}

// 一个点(经纬度)的位置误差 = 两个轴里差的那个
function pointPrecisionM(lat, lon) {
    return Math.max(halfQuantumM(lat, true), halfQuantumM(lon, false));
}

// 报 2 位有效数字, 向上取整到米 —— 别给人"±554.7 米"这种假精确, 也别往 INTEGER 列写小数
function round2sig(x) {
    if (!(x > 0)) return 0;
    const mag = Math.pow(10, Math.floor(Math.log10(x)));
    return Math.max(1, Math.round(Math.ceil(x / mag * 10) / 10 * mag));
}

function gapM(a, b) {
    if (!a || !b) return null;
    const mr = Math.PI / 180, R = 6371000;
    const x = (b.lon - a.lon) * mr * Math.cos((a.lat + b.lat) / 2 * mr);
    const y = (b.lat - a.lat) * mr;
    return Math.hypot(x, y) * R;
}

const hasCoord = o => o && Number.isFinite(o.lat) && Number.isFinite(o.lon)
                       && !(o.lat === 0 && o.lon === 0);

function dropEndpoint(obj, key) {
    const kept = { name: obj[key].name || '', address: obj[key].address || '' };
    if (obj[key].coord_unavailable !== undefined) kept.coord_unavailable = true;
    kept.coord_unavailable = true;
    obj[key] = kept;
}

// ── routes.json ────────────────────────────────────────────────────────
const routesRaw = fs.readFileSync(ROUTES, 'utf8');
const routesDoc = JSON.parse(routesRaw);
const news = NEW_FILE ? JSON.parse(fs.readFileSync(NEW_FILE, 'utf8')) : [];

const e1 = [], e2 = [];
for (const r of routesDoc.routes) {
    const nature = r.route_nature || r.routeNature || '穿越';
    const th = r.trailhead, te = r.trailend;

    if (hasCoord(th) && hasCoord(te) && th.lat === te.lat && th.lon === te.lon
        && (nature === '穿越' || nature === '单程')) {
        dropEndpoint(r, 'trailend');
        e1.push(`${r.id} (${nature}, 名称 "${th.name}" → "${te.name}")`);
        continue;
    }

    if (hasCoord(th) && hasCoord(te) && Number.isFinite(r.distance_km) && r.distance_km > 0) {
        const km = gapM(th, te) / 1000;
        const tolKm = 2 * (pointPrecisionM(th.lat, th.lon) + pointPrecisionM(te.lat, te.lon)) / 1000;
        if (km > r.distance_km + tolKm) {
            dropEndpoint(r, 'trailend');
            e2.push(`${r.id} 里程 ${r.distance_km}km < 端点直线 ${km.toFixed(1)}km (容差 ${tolKm.toFixed(1)}km)`);
        }
    }
}

// 小数位数算出来的是误差**下限**, 不是这条记录的标定精度: GPS 轨迹打印 6 位小数
// 仍然只有 ±3~10 m。所以只允许把精度往"更差"方向改, 已有的更大声明一律保留 ——
// 否则每次补标都会把实测轨迹的 ±10 m 改写成 ±1 m, 那就是虚报精度。
function notBetterThan(q, stored) {
    return Number.isFinite(stored) ? Math.max(q, stored) : q;
}

for (const r of routesDoc.routes) {
    const pts = [r.trailhead, r.trailend].filter(hasCoord);
    if (!pts.length) { r.coord_precision_m = 0; r.coord_source = r.coord_source || 'editorial_estimate'; continue; }
    r.coord_precision_m = notBetterThan(round2sig(Math.max(...pts.map(p => pointPrecisionM(p.lat, p.lon)))),
                                       r.coord_precision_m);
    r.coord_source = r.coord_source || 'editorial_estimate';
}

for (const n of news) {
    delete n._audit;
    if (!routesDoc.routes.some(x => x.id === n.id)) routesDoc.routes.push(n);
}

// ── travel.json ────────────────────────────────────────────────────────
const travelRaw = fs.readFileSync(TRAVEL, 'utf8');
const travelDoc = JSON.parse(travelRaw);
const te1 = [], te2 = [];
for (const t of travelDoc.routes) {
    const a = { lat: t.startLat, lon: t.startLon };
    const b = { lat: t.endLat, lon: t.endLon };
    const okA = hasCoord(a), okB = hasCoord(b);
    if (okA && okB && a.lat === b.lat && a.lon === b.lon && t.startName !== t.endName) {
        t.endLat = 0; t.endLon = 0; t.endCoordUnavailable = true;
        te1.push(`${t.id} ("${t.startName}" → "${t.endName}" 同点)`);
        continue;
    }
    if (okA && okB && t.distanceKm > 0) {
        const km = gapM(a, b) / 1000;
        const tolKm = 2 * (pointPrecisionM(a.lat, a.lon) + pointPrecisionM(b.lat, b.lon)) / 1000;
        if (km > t.distanceKm + tolKm) {
            t.endLat = 0; t.endLon = 0; t.endCoordUnavailable = true;
            te2.push(`${t.id} 里程 ${t.distanceKm}km < 端点直线 ${km.toFixed(1)}km (容差 ${tolKm.toFixed(1)}km)`);
        }
    }
}
for (const t of travelDoc.routes) {
    const a = { lat: t.startLat, lon: t.startLon };
    const b = { lat: t.endLat, lon: t.endLon };
    const pts = [a, b].filter(hasCoord);
    t.coordPrecisionM = pts.length
        ? notBetterThan(round2sig(Math.max(...pts.map(p => pointPrecisionM(p.lat, p.lon)))), t.coordPrecisionM)
        : 0;
    // 自驾库里 88/101 条的起点坐标与终点坐标逐位相同 —— 这不是"起止同点"(那已经被
    // E1 处理掉了, 且只有名称也相同才会留在这里), 而是两端都取了同一个城区中心
    // 点。语义标 city_center, UI 才能说清「端点=城区中心, 不是具体路口」,
    // 而不是让人把红点当成导航终点。
    if (!t.coordSource)
        t.coordSource = (hasCoord(a) && hasCoord(b) && a.lat === b.lat && a.lon === b.lon)
            ? 'city_center' : 'editorial_estimate';
}

console.log(`routes.json: ${routesDoc.routes.length} 条 (新增 ${news.length}) ` +
            `E1 起止同点 ${e1.length} · E2 里程矛盾 ${e2.length}`);
e1.forEach(x => console.log('  E1 ' + x));
e2.forEach(x => console.log('  E2 ' + x));
console.log(`travel.json: ${travelDoc.routes.length} 条 ` +
            `E1 ${te1.length} · E2 ${te2.length}`);
te1.forEach(x => console.log('  E1t ' + x));
te2.forEach(x => console.log('  E2t ' + x));

// 两个库的键名风格不同(routes 蛇形 / travel 驼峰), 分布表按各自键读;
// 读错键会打印 "undefinedm×N" —— 这就是假绿的一种, 必须能自己看出来。
const hist = (arr, key) => {
    const h = {};
    let unknown = 0;
    for (const x of arr) {
        const k = x[key];
        if (!Number.isFinite(k)) { unknown++; continue; }
        h[k] = (h[k] || 0) + 1;
    }
    const s = Object.entries(h).sort((a, b) => a[0] - b[0]).map(([k, v]) => `${k}m×${v}`).join(' ');
    return (unknown ? `??×${unknown} ` : '') + s;
};
console.log('routes 精度分布: ' + hist(routesDoc.routes, 'coord_precision_m'));
console.log('travel 精度分布: ' + hist(travelDoc.routes, 'coordPrecisionM'));
const srcHist = (arr, key) => {
    const h = {};
    for (const x of arr) { const k = x[key]; h[k] = (h[k] || 0) + 1; }
    return Object.entries(h).map(([k, v]) => `${k}×${v}`).join(' ');
};
console.log('routes 来源分布: ' + srcHist(routesDoc.routes, 'coord_source'));
console.log('travel 来源分布: ' + srcHist(travelDoc.routes, 'coordSource'));

if (DRY) { console.log('--dry: 未落盘'); process.exit(0); }
fs.writeFileSync(ROUTES, JSON.stringify(routesDoc, null, 2) + '\n');
fs.writeFileSync(TRAVEL, JSON.stringify(travelDoc, null, 2) + (travelRaw.endsWith('\n') ? '\n' : ''));
console.log('已写回 routes.json / travel.json');
