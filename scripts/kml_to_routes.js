#!/usr/bin/env node
// 两步路(2bulu) KML → routes.json 路线记录 (含实测 waypoints)
//
// 宿主机没有 node/python, 用 Electron 当 node 跑:
//   ELECTRON_RUN_AS_NODE=1 "<Qoder.exe>" scripts/kml_to_routes.js <out.json> <a.kml> [b.kml ...]
//
// 口径 (2026-10-27 #131):
//   - 里程/累计升降/用时 一律取文件里 <ExtendedData> 的 Distance / ElevationGain /
//     ElevationLoss / TimeUsed —— 那是两步路自己按原始轨迹算的数, 与用户在这步路 App
//     里看到的读数一致; 我自己重算的折线长度(如 8722 m vs 其 8505 m)只当交叉校验。
//   - 最高/最低海拔取逐点 alt 列 (GPS 高程, 未经大地水准面改正, 与图上的等高线会有
//     几十米系统偏差 —— 记在 description 里, 不假装它是测绘高程)。
//   - 折线用 Douglas–Peucker 抽稀, 命名标注点与起终点/最高最低点强制保留。
//   - 坐标按 KML/GPX 交换规范记作 WGS-84 (两步路可与六只脚等互换 GPX, 导出的是原始
//     GPS 记录; GCJ-02 只发生在它的显示层)。此判定未经真机底图核对, 若叠加后发现
//     整条线系统性偏 ~500 m, 第一件要改的就是这个 datum。
'use strict';
const fs = require('fs');

const OUT = process.argv[2];
const FILES = process.argv.slice(3);
if (!OUT || FILES.length === 0) {
    console.error('usage: kml_to_routes.js <out.json> <track.kml> [more.kml ...]');
    process.exit(2);
}

// 每条轨迹的入库规格(人工核定, 脚本不猜地名归属): id / name / 行政区 / 难度 / 性质等。
const SPEC = {
  '2026-10-25 藏龙涧-聚仙台-大小天坑-藏秀峰-老龙头-阳关道-望龙台-老军崖': {
    id: 'route_sd_canglongjian', name: '藏龙涧-聚仙台-大小天坑-老军崖环线',
    city: '济南', area: '历下', mountain: '藏龙涧', difficulty: 2, type: '徒步',
    route_nature: '环线', is_wild: true, has_permit: false, permit_info: '龙洞风景区一带, 雨季涧内湿滑',
    terrain: ['峡谷', '山脊', '土路'], tags: ['实测轨迹', '半日', '野线'],
    best_season: ['3月', '4月', '5月', '9月', '10月', '11月'],
  },
  '2025-10-26 空心山-拔槊泉-劈山-万粮峪村-响呼噜泉': {
    id: 'route_sd_pishan_kongxinshan', name: '空心山-拔槊泉-劈山-万粮峪-响呼噜泉环线',
    city: '济南', area: '历城', mountain: '劈山', difficulty: 3, type: '徒步',
    route_nature: '环线', is_wild: true, has_permit: false, permit_info: '',
    terrain: ['山脊', '机耕路', '村路'], tags: ['实测轨迹', '一日', '野线', '泉群'],
    best_season: ['4月', '5月', '9月', '10月', '11月'],
  },
  '空心山-拔槊泉-劈山': {
    id: 'route_sd_humen_yuhequan', name: '虎门西—拔槊泉—劈山—空心山—玉河泉穿越',
    city: '济南', area: '历城', mountain: '空心山', difficulty: 3, type: '徒步',
    route_nature: '穿越', is_wild: true, has_permit: false, permit_info: '',
    terrain: ['山脊', '村路', '机耕路'], tags: ['实测轨迹', '一日', '野线', '泉群'],
    best_season: ['4月', '5月', '9月', '10月', '11月'],
  },
  '2026-10-18 0919济南市中区到历下区': {
    id: 'route_sd_shizhong_lizxia_ridge', name: '阳光舜城—皇宫停车场 市区山脊纵走',
    city: '济南', area: '历下', mountain: '佛慧山', difficulty: 2, type: '休闲徒步',
    route_nature: '穿越', is_wild: false, has_permit: false, permit_info: '',
    terrain: ['石阶', '步道'], tags: ['实测轨迹', '半日', '市区'],
    best_season: ['3月', '4月', '5月', '9月', '10月', '11月'],
  },
  '济南望星谷徒步路线': {
    id: 'route_sd_wangxinggu', name: '于科村—望星谷—于科水库—高山草甸—锯齿崖环线',
    city: '济南', area: '历城', mountain: '望星谷', difficulty: 2, type: '徒步',
    route_nature: '环线', is_wild: false, has_permit: false,
    permit_info: '有路牌可循; 部分路段岩石松动, 雨天有滑坡/泥石流风险',
    terrain: ['山路', '水泥路'], tags: ['实测轨迹', '半日', '亲子友好'],
    best_season: ['3月', '4月', '5月', '9月', '10月', '11月'],
  },
  '劈山空心山': {
    id: 'route_sd_yuhequan_kongxinshan', name: '玉河泉村—空心山旅游区北门 山脊穿越',
    city: '济南', area: '历城', mountain: '空心山', difficulty: 3, type: '徒步',
    route_nature: '穿越', is_wild: true, has_permit: false, permit_info: '',
    terrain: ['山脊', '村路', '机耕路'], tags: ['实测轨迹', '一日', '野线', '泉群'],
    best_season: ['4月', '5月', '9月', '10月', '11月'],
  },
};

// 手头 6 个 KML 里, 空心山那片有三条线 —— 同一条山脊、三个不同的日子, 各建一条是**对的**:
//   '...响呼噜泉'      TrackId 73642217, BeginTime 2025-10-26 08:39, 15.59 km, 环线
//                      起 虎门村村委会 → 终 彩石街道虎门村村务监督委员会 (自距 15 m, 环线天然如此)
//   '空心山-拔槊泉-劈山'  TrackId 91355646, BeginTime 2026-10-11 09:28, 13.90 km, 穿越
//                      起 虎门西公交车站 → 终 玉河泉村 (自距 999 m)
//   '劈山空心山'       TrackId 73762016, BeginTime 2025-10-25 09:03, 11.63 km, 穿越
//                      起 玉河泉村村委会 → 终 空心山旅游区(北门) (自距 1193 m)
//   两两互相覆盖 89~100%(200 m 容差), 但按库自己的合并口径(同山 + 起终点<0.5 km +
//   里程差<1 km)一条都不成立: 里程差 1.69 / 2.27 / 3.97 km。
//   最接近的一次是后两条 —— 它们其实是同一条脊的反向走法(起↔彼终 33 m、终↔彼起 286 m),
//   可就算允许反向配对, 里程差 2.27 km 也远超 1 km, 且相隔一年、TrackId 不同。
//   判据全部来自 KML 的 BeginTime/TrackId/Distance 与首末 gx:coord, 不是文件名日期。
// 下面两个文件**故意不入库**, 别当成漏跑:
//   '2024-10-26 1020 爬山'(目录里两份字节相同的副本): 与 route_sd_shizhong_lizxia_ridge
//     起点相距 155 m、终点 211 m, 互相覆盖 96%/99%, 8.29 vs 8.4 km —— 同一条线的重复记录。
//   '2026-08-15 0916 徒步': 文件里没有 TrackId/里程/升降, 起终点地名与标注全为空
//     (0 个 placemark), 而库内最近的一条在 11.7 km 外(淄博·博山·鲁山)。山名与行政区
//     只能靠猜 —— 脚本不猜地名归属, 等核定归属后再加 SPEC 入库。

const MAX_POINTS = 180;
const EPS_LADDER = [8, 12, 16, 20, 25, 30, 40, 55, 75];

const strip = t => String(t == null ? '' : t)
  .replace(/<!\[CDATA\[|\]\]>/g, '').replace(/<[^>]+>/g, ' ')
  .replace(/[\r\n]+/g, ' ').trim();

function readExtendedData(text) {
  const docM = text.match(/<Document[^>]*>([\s\S]*?)<Folder/);
  const scope = docM ? docM[1] : text;
  const out = {};
  for (const m of scope.matchAll(/<Data name="([^"]+)">\s*<value>([\s\S]*?)<\/value>/g)) {
    out[m[1]] = strip(m[2]);
  }
  return out;
}

function readTrack(text) {
  const coords = [...text.matchAll(/<gx:coord>([^<]+)<\/gx:coord>/g)].map(m => {
    const p = m[1].trim().split(/\s+/).map(Number);
    return { lon: p[0], lat: p[1], alt: Number.isFinite(p[2]) ? p[2] : null };
  }).filter(p => Number.isFinite(p.lat) && Number.isFinite(p.lon)
                  && !(p.lat === 0 && p.lon === 0));
  const when = [...text.matchAll(/<when>([^<]+)<\/when>/g)].map(m => m[1].trim());
  // 两步路的 gx:Track 把所有 <gx:coord> 写在前面、所有 <when> 写在后面, 按下标配对;
  // when 条数可能多于 coord (暂停/标注时段), 以 coord 为准。
  const pts = coords.map((p, i) => ({ ...p, t: when[i] || null }));
  const dedup = [];
  for (const p of pts) {
    const last = dedup[dedup.length - 1];
    if (last && last.lat === p.lat && last.lon === p.lon) continue;
    dedup.push(p);
  }
  return dedup;
}

function readAnnotations(text) {
  const ann = [];
  for (const m of text.matchAll(/<Placemark[^>]*>([\s\S]*?)<\/Placemark>/g)) {
    const body = m[1];
    const co = body.match(/<Point>[\s\S]*?<coordinates>([^<]+)<\/coordinates>/);
    if (!co) continue;
    const nm = strip((body.match(/<name>([\s\S]*?)<\/name>/) || [])[1]);
    const [lon, lat, alt] = co[1].trim().split(',').map(Number);
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || (lat === 0 && lon === 0)) continue;
    if (!nm || nm === '起点' || nm === '终点') continue;
    ann.push({ name: nm, lat, lon, alt: Number.isFinite(alt) ? alt : null });
  }
  return ann;
}

// 大圆距离(米)
function meters(a, b) {
  const mr = Math.PI / 180, R = 6371000;
  const x = (b.lon - a.lon) * mr * Math.cos((a.lat + b.lat) / 2 * mr);
  const y = (b.lat - a.lat) * mr;
  return Math.hypot(x, y) * R;
}

// 点到线段的垂距(米), 用等距柱面近似 —— 抽稀尺度上足够
function perpMeters(p, a, b) {
  const mr = Math.PI / 180;
  const k = Math.cos((a.lat + p.lat + b.lat) / 3 * mr);
  const ax = a.lon * k, ay = a.lat, bx = b.lon * k, by = b.lat, px = p.lon * k, py = p.lat;
  const dx = bx - ax, dy = by - ay;
  const len2 = dx * dx + dy * dy;
  if (len2 === 0) return Math.hypot(px - ax, py - ay) * 111320 * Math.cos(py * mr);
  const num = Math.abs(dy * px - dx * py + bx * ay - by * ax);
  const d = num / Math.sqrt(len2);
  return d * 111320 * Math.cos(p.lat * mr);
}

// 带钉点的 Douglas–Peucker: 先按钉住的下标把折线切成若干段, 每段各跑一次标准 DP,
// 段端点(=钉点)天然保留。比在递归里塞"跳过已选点"清楚, 也不会漏掉子段。
function dpRange(points, i0, i1, eps) {
  const keep = [i0];
  const stack = [[i0, i1]];
  while (stack.length) {
    const [a, b] = stack.pop();
    if (b - a < 2) continue;
    let maxD = -1, maxI = -1;
    for (let i = a + 1; i < b; i++) {
      const d = perpMeters(points[i], points[a], points[b]);
      if (d > maxD) { maxD = d; maxI = i; }
    }
    if (maxD > eps) {
      keep.push(maxI);
      stack.push([a, maxI], [maxI, b]);
    }
  }
  keep.push(i1);
  return keep;
}

function simplify(points, eps, pinned) {
  const pins = [...new Set(pinned)].sort((a, b) => a - b);
  if (pins.length < 2) return dpRange(points, 0, points.length - 1, eps).sort((a, b) => a - b);
  const keep = new Set();
  for (let k = 0; k + 1 < pins.length; k++) {
    for (const i of dpRange(points, pins[k], pins[k + 1], eps)) keep.add(i);
  }
  return [...keep].sort((a, b) => a - b);
}

function buildRecord(file, text, specKey) {
  const spec = SPEC[specKey];
  if (!spec) throw new Error('没有为这条轨迹核定入库规格: ' + specKey);
  const ed = readExtendedData(text);
  const pts = readTrack(text);
  if (pts.length < 2) throw new Error('轨迹点不足: ' + file);
  const ann = readAnnotations(text);

  const title = strip((text.match(/<Document[^>]*>\s*<name>([\s\S]*?)<\/name>/) || [])[1]);
  const desc = strip((text.match(/<Document[^>]*>[\s\S]*?<description>([\s\S]*?)<\/description>/) || [])[1]);

  const altVals = pts.filter(p => p.alt !== null).map(p => p.alt);
  const maxAlt = altVals.reduce((a, b) => Math.max(a, b), -1e9);
  const minAlt = altVals.reduce((a, b) => Math.min(a, b), 1e9);

  const pinned = new Set([0, pts.length - 1]);
  const hiIdx = pts.findIndex(p => p.alt === maxAlt);
  const loIdx = pts.findIndex(p => p.alt === minAlt);
  if (hiIdx >= 0) pinned.add(hiIdx);
  if (loIdx >= 0) pinned.add(loIdx);
  const snapped = [];
  for (const a of ann) {
    let bi = -1, bd = Infinity;
    pts.forEach((p, i) => { const d = meters(p, a); if (d < bd) { bd = d; bi = i; } });
    if (bi >= 0 && bd <= 60) { pinned.add(bi); snapped.push({ name: a.name, idx: bi, d: bd }); }
  }

  let idx = null, epsUsed = null;
  for (const eps of EPS_LADDER) {
    const keep = simplify(pts, eps, [...pinned]);
    if (keep.length <= MAX_POINTS) { idx = keep; epsUsed = eps; break; }
  }
  if (!idx) {   // 抽到最粗仍超阈值: 均匀降采样, 钉住的点优先保留
    const pins = [...pinned];
    const step = Math.ceil(pts.length / MAX_POINTS);
    const set = new Set(pins);
    for (let i = 0; i < pts.length; i += step) set.add(i);
    set.add(pts.length - 1);
    idx = [...set].sort((a, b) => a - b);
    epsUsed = 'subsample';
  }

  const byIdxName = new Map();
  for (const s of snapped) if (!byIdxName.has(s.idx)) byIdxName.set(s.idx, s.name);

  const waypoints = idx.map((i, seq) => {
    const p = pts[i];
    const named = byIdxName.get(i);
    return {
      name: seq === 0 ? (ed.PosStartName || '起点') : seq === idx.length - 1 ? (ed.PosEndName || '终点') : (named || ''),
      type: seq === 0 ? 'start' : seq === idx.length - 1 ? 'end' : (named ? 'poi' : 'track'),
      lat: +p.lat.toFixed(6),
      lon: +p.lon.toFixed(6),
      elevation: p.alt === null ? 0 : Math.round(p.alt),
      sequence: seq,
      description: named && seq !== 0 && seq !== idx.length - 1 ? '两步路标注点' : '',
    };
  });

  const first = pts[0], last = pts[pts.length - 1];
  const distanceKm = ed.Distance ? +(Math.round(Number(ed.Distance) / 100) / 10).toFixed(1)
                                : +(meters(first, last) / 1000).toFixed(1);
  const hours = ed.TimeUsed ? +(Number(ed.TimeUsed) / 3600000).toFixed(1) : null;
  let recomputed = 0;
  for (let k = 1; k < idx.length; k++) recomputed += meters(pts[idx[k - 1]], pts[idx[k]]);

  return {
    id: spec.id,
    name: spec.name,
    alias: [title],
    province: '山东',
    province_code: 'SD',
    city: spec.city,
    area: spec.area,
    mountain: spec.mountain,
    difficulty: spec.difficulty,
    type: spec.type,
    distance_km: distanceKm,
    duration_hours: hours || 0,
    days_needed: 1,
    elevation_gain_m: ed.ElevationGain ? Math.round(Number(ed.ElevationGain)) : 0,
    elevation_loss_m: ed.ElevationLoss ? Math.round(Number(ed.ElevationLoss)) : 0,
    max_altitude_m: Math.round(maxAlt),
    min_altitude_m: Math.round(minAlt),
    best_season: spec.best_season,
    terrain: spec.terrain,
    highlights: [ed.TrackTags ? `${ed.TrackTags}` : '徒步', title].join(' · '),
    description:
      `${distanceKm} 公里 / 累计上升 ${ed.ElevationGain ? Math.round(Number(ed.ElevationGain)) : '?'} 米, ` +
      `${ed.PosStartName || '起点'} → ${ed.PosEndName || '终点'}。` +
      `坐标与里程来自两步路实测轨迹(${specKey}${ed.TrackId ? ', TrackId ' + ed.TrackId : ''}), ` +
      `折线经 Douglas–Peucker 抽稀至 ${waypoints.length} 点(阈值 ${epsUsed} m)。` +
      `高程为 GPS 读数, 未做大地水准面改正。` +
      (desc ? ` 原作者记: ${desc}` : ''),
    permit_required: false,
    permit_info: spec.permit_info,
    rescue_phone: '0531-122',
    trailhead: { lat: +first.lat.toFixed(6), lon: +first.lon.toFixed(6),
                 name: ed.PosStartName || '起点', address: `山东${spec.city}${spec.area}` },
    trailend: { lat: +last.lat.toFixed(6), lon: +last.lon.toFixed(6),
                name: ed.PosEndName || '终点', address: `山东${spec.city}${spec.area}` },
    tags: spec.tags,
    author: `两步路实测轨迹 ${ed.TrackId ? '#' + ed.TrackId : ''}`.trim(),
    route_nature: spec.route_nature,
    is_wild: spec.is_wild,
    has_permit: spec.has_permit,
    // 不写 score —— 库里的 score 是 11 项分项 (海拔/路况/爬升/水源/蛇虫/危险/长度/
    // 补给/季节/救援/线路调整) 之和, 而 KML 只给得出海拔/爬升/长度/季节; 水源、蛇虫、
    // 救援这些要靠实地或资料核定, 硬凑一个 80 就是假读数 (库内 22 条未评分记录同样
    // 是"整个键不写")。单测 tests/unit/test_route_service.cpp
    // ::test_score_detail_json_roundtrip 会钉住 score 与 scoreDetail 同进同退。
    // 精度标 ±10 m 而不是按小数位算出的 ±1 m: 坐标打印几位小数不代表点位准到几米,
    // 手机 GPS 的水平误差量级就是 3~10 m。
    coord_precision_m: 10,
    coord_source: 'gps_track_2bulu',
    waypoints,
    _audit: {
      file, raw_points: pts.length, kept_points: waypoints.length, eps_m: epsUsed,
      annotations_used: snapped.length,
      distance_liangbulu_m: ed.Distance || null,
      length_polyline_m: Math.round(recomputed),
      endpoint_gap_m: Math.round(meters(first, last)),
      begin_time: ed.BeginTime || null, end_time: ed.EndTime || null,
    },
  };
}

function specKeyOf(fileName) {
  const base = fileName.replace(/\.kml$/i, '').replace(/-\d{13}( \(1\))?$/, '').replace(/\(1\)$/, '').trim();
  if (SPEC[base]) return base;
  const keys = Object.keys(SPEC);
  const hit = keys.find(k => base.startsWith(k) || k.startsWith(base));
  if (hit) return hit;
  throw new Error('没有为文件核定规格: ' + fileName);
}

const records = [];
for (const f of FILES) {
  const text = fs.readFileSync(f, 'utf8');
  records.push(buildRecord(f.split(/[\\/]/).pop(), text, specKeyOf(f.split(/[\\/]/).pop())));
}
fs.writeFileSync(OUT, JSON.stringify(records, null, 2) + '\n');
for (const r of records) {
  console.log(`${r.id}  ${r.name}  ${r.distance_km}km 上升${r.elevation_gain_m}m ` +
              `点${r.waypoints.length} eps=${r._audit.eps_m} 原始${r._audit.raw_points} ` +
              `标注${r._audit.annotations_used} 端点距${r._audit.endpoint_gap_m}m ` +
              `折线重算${r._audit.length_polyline_m}m/两步路${r._audit.distance_liangbulu_m}m`);
}
