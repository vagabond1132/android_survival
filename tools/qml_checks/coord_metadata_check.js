#!/usr/bin/env node
/**
 * coord_metadata_check.js — 端点精度元数据与轨迹结构的门禁 (2026-10-27 #131c)
 *
 * 为什么需要它: #131 给 753 条路线 + 101 条自驾补了 coord_precision_m / coord_source,
 * 并删掉了 9 个不可信的终点坐标。这些键是 MapPage / RouteDetailPage / TravelDetailPage
 * 上那句「±5.6 公里 · 城区中心点」的唯一数据来源, 而它们一旦与坐标本身脱节
 * (改了坐标没重跑 annotate_endpoint_data.js, 或给某个端点写了 91.0 这种哨兵值),
 * UI 就会**如实报出一个假读数** —— 这类问题单测只能发现"键没读到", 发现不了
 * "键读到了但和数字对不上"。所以这里按 annotate_endpoint_data.js 同一套机械规则
 * 从坐标字面量**重算**一遍, 再和库里的标记对账。
 *
 * 键名两个库不同 (routes 蛇形 / travel 驼峰, 见 #44 C2), 本脚本按各自主程序实际
 * 读的键写死: src/routes/RouteService.cpp 读 coord_precision_m/coord_source,
 * src/travel/TravelService.cpp 读 coordPrecisionM/coordSource。改键名要同时改这三处,
 * 漏哪处都会在这里炸。
 *
 * 查的六件事 (全部是"标记与数据自洽", 不判地理真伪):
 *   精度标记不低于坐标字面量的量化下限 · coord_source 在认可集合内并与 waypoints 互证
 *   · 端点缺坐标必须带 coord_unavailable/endCoordUnavailable 标记且保住地名
 *   · E1/E2 两条可证伪规则没有复发 · waypoints 结构 (类型/顺序/坐标/海拔/命名)
 *   · travel.json 不出现蛇形键 (解析端读不到 = 全站精度读数静默消失)
 *
 * 用法: ELECTRON_RUN_AS_NODE=1 <Qoder.exe> coord_metadata_check.js [data目录]
 * 退出码: 0 = 干净, 1 = 有命中 (任何"0 条"结论先用坏 fixture 反证脚本是活的)。
 */
'use strict'
const fs = require('fs')
const path = require('path')

const ROOT = process.argv[2] || path.resolve(__dirname, '../../assets/data')
const ROUTES = path.join(ROOT, 'routes.json')
const TRAVEL = path.join(ROOT, 'travel.json')

const M_PER_DEG_LAT = 110948
const M_PER_DEG_EQ = 111320
// annotate_endpoint_data.js 认可的来源集合。新增来源要连同 C++ 侧
// CommonOptions::coordSourceLabel 的文案一起加, 否则读数条会只报精度不报来源。
const ROUTE_SOURCES = new Set(['editorial_estimate', 'gps_track_2bulu'])
const TRAVEL_SOURCES = new Set(['editorial_estimate', 'city_center'])
const WP_TYPES = new Set(['start', 'track', 'poi', 'end'])

const hits = []
const fail = (id, msg) => hits.push(`${id}: ${msg}`)

function decimals(v) {
  const s = String(v)
  if (s.indexOf('e') >= 0 || s.indexOf('E') >= 0) return 6
  const dot = s.indexOf('.')
  return dot < 0 ? 0 : s.length - dot - 1
}
function halfQuantumM(v, isLat) {
  const deg = Math.pow(10, -decimals(v))
  const perDeg = isLat ? M_PER_DEG_LAT : M_PER_DEG_EQ * Math.abs(Math.cos(v * Math.PI / 180))
  return 0.5 * deg * perDeg
}
function pointPrecisionM(lat, lon) {
  return Math.max(halfQuantumM(lat, true), halfQuantumM(lon, false))
}
function round2sig(x) {
  if (!(x > 0)) return 0
  const mag = Math.pow(10, Math.floor(Math.log10(x)))
  return Math.max(1, Math.round(Math.ceil(x / mag * 10) / 10 * mag))
}
function gapM(a, b) {
  const mr = Math.PI / 180, R = 6371000
  const x = (b.lon - a.lon) * mr * Math.cos((a.lat + b.lat) / 2 * mr)
  const y = (b.lat - a.lat) * mr
  return Math.hypot(x, y) * R
}
const isNum = v => typeof v === 'number' && Number.isFinite(v)
// 全工程"没有坐标"的约定是 (0,0) 这一对; QGeoCoordinate 未设置时返回 91.0/181.0,
// 那种值写进库里会一路漏到 QML (_validCoord 只挡 0,0) 并画出一个境外点。
const usable = (lat, lon) => isNum(lat) && isNum(lon) && !(lat === 0 && lon === 0)
                            && Math.abs(lat) <= 90 && Math.abs(lon) <= 180
// 坐标字面量能撑起的最好精度 (半格量化误差)。这是**下限**而不是标称值: 小数位多
// 不代表点得准 —— 两步路 KML 打印 5 位小数 (±1 m), 但手机 GPS 的水平误差是 3~10 m,
// 所以 kml_to_routes.js 给实测轨迹标的是 ±10 m。门禁因此只拦"标得比坐标撑得起的
// 还准"(虚报), 允许往保守方向偏; 反过来说, 改粗坐标却没跟着改标记, 这里不会响,
// 那种偏离靠 test_route_service.cpp 的分布断言兜。
function recompute(lat, lon, alt, alon) {
  const pts = []
  if (usable(lat, lon)) pts.push(pointPrecisionM(lat, lon))
  if (usable(alt, alon)) pts.push(pointPrecisionM(alt, alon))
  return pts.length ? round2sig(Math.max(...pts)) : 0
}

if (!fs.existsSync(ROUTES) || !fs.existsSync(TRAVEL)) {
  console.error(`读不到数据目录: ${ROOT}  (需 Windows 可懂的路径, 别给 /d/... 或 /tmp/...)`)
  process.exit(2)
}

// ── routes.json ────────────────────────────────────────────────────────
const routes = JSON.parse(fs.readFileSync(ROUTES, 'utf8')).routes
let withTrack = 0
for (const r of routes) {
  const id = 'RT ' + r.id
  const th = r.trailhead || {}, te = r.trailend || {}

  // 1) 精度标记不许比坐标字面量撑得起的还准 (虚报), 允许保守
  const expect = recompute(th.lat, th.lon, te.lat, te.lon)
  if (!isNum(r.coord_precision_m)) fail(id, `coord_precision_m 缺失或不是数字 (${r.coord_precision_m})`)
  else if (expect === 0 && r.coord_precision_m !== 0)
    fail(id, `两端都没有坐标却标了精度 ${r.coord_precision_m} —— 没有位置可言`)
  else if (expect > 0 && r.coord_precision_m < expect)
    fail(id, `coord_precision_m=${r.coord_precision_m} 比坐标量化下限 ${expect} 还准 —— 虚报精度`)

  // 2) 来源标记
  if (!ROUTE_SOURCES.has(r.coord_source)) fail(id, `coord_source=${JSON.stringify(r.coord_source)} 不在认可集合里`)

  // 3) 端点状态与标记互证
  for (const [key, ep] of [['trailhead', th], ['trailend', te]]) {
    const off = ep.coord_unavailable === true
    if (off && usable(ep.lat, ep.lon)) fail(id, `${key} 标了 coord_unavailable 却还留着坐标`)
    if (!off && !isNum(ep.lat) && !isNum(ep.lon)) {
      // 没有坐标就必须说明"为什么不知道", 否则 UI 只能整行不说, 看着像数据丢了
      fail(id, `${key} 既无坐标也无 coord_unavailable 标记`)
    } else if (!off && !usable(ep.lat, ep.lon)) {
      fail(id, `${key} 坐标越界或为 (0,0) 但没标 coord_unavailable: ${ep.lat},${ep.lon}`)
    }
    if (off && !ep.name) fail(id, `${key} 坐标删了但名字也没了 —— 不知道在哪 ≠ 不知道是什么地方`)
  }

  // 4) 可证伪规则不许复发 (annotate_endpoint_data.js 的 E1/E2)
  const nature = r.route_nature || r.routeNature || '穿越'
  if (usable(th.lat, th.lon) && usable(te.lat, te.lon)) {
    if (th.lat === te.lat && th.lon === te.lon && (nature === '穿越' || nature === '单程'))
      fail(id, `E1 复发: 性质「${nature}」却起止同点`)
    if (isNum(r.distance_km) && r.distance_km > 0) {
      const km = gapM(th, te) / 1000
      const tol = 2 * (pointPrecisionM(th.lat, th.lon) + pointPrecisionM(te.lat, te.lon)) / 1000
      if (km > r.distance_km + tol)
        fail(id, `E2 复发: 里程 ${r.distance_km}km < 端点直线 ${km.toFixed(1)}km (容差 ${tol.toFixed(1)}km)`)
    }
  }

  // 5) 轨迹结构: 标成 GPS 实测就必须真有轨迹
  const wps = r.waypoints
  if (wps !== undefined) {
    if (!Array.isArray(wps) || wps.length < 2) fail(id, `waypoints 不是长度 ≥2 的数组`)
    else {
      withTrack++
      if (r.coord_source !== 'gps_track_2bulu')
        fail(id, `有 waypoints 却标 coord_source=${r.coord_source} —— 图上按实测连线, 来源要说清`)
      let starts = 0, ends = 0
      wps.forEach((w, i) => {
        if (!WP_TYPES.has(w.type)) fail(id, `waypoints[${i}] type=${JSON.stringify(w.type)} 未知`)
        if (w.type === 'start') starts++
        if (w.type === 'end') ends++
        if (i === 0 && w.type !== 'start') fail(id, `waypoints[0] 不是 start`)
        if (i === wps.length - 1 && w.type !== 'end') fail(id, `最后一个 waypoints 不是 end`)
        if (i > 0 && i < wps.length - 1 && w.type !== 'track' && w.type !== 'poi')
          fail(id, `waypoints[${i}] 中间位置出现 ${w.type}`)
        if (!usable(w.lat, w.lon)) fail(id, `waypoints[${i}] 坐标不可用: ${w.lat},${w.lon}`)
        if (w.sequence !== i) fail(id, `waypoints[${i}] sequence=${w.sequence} 与下标不符`)
        if (w.elevation !== undefined && (!isNum(w.elevation) || w.elevation <= 0))
          fail(id, `waypoints[${i}] elevation=${w.elevation} 不是正数`)
        // track 是折线的拐点, 不是地名 (两步路 KML 里 120~157 个拐点全无名字);
        // start/poi/end 会渲染成地图标记, 没有名字就只剩一个经纬度。
        if (w.type !== 'track' && !w.name) fail(id, `waypoints[${i}] (${w.type}) 没有名字`)
      })
      if (starts !== 1 || ends !== 1) fail(id, `start/end 各应 1 个, 实际 ${starts}/${ends}`)
    }
  } else if (r.coord_source === 'gps_track_2bulu') {
    fail(id, 'coord_source 是 GPS 实测轨迹但没有 waypoints —— 图上那条线其实是起终点直线')
  }
}

// ── travel.json ────────────────────────────────────────────────────────
const travels = JSON.parse(fs.readFileSync(TRAVEL, 'utf8')).routes
for (const t of travels) {
  const id = 'TR ' + t.id
  if (!isNum(t.coordPrecisionM)) fail(id, `coordPrecisionM 缺失或不是数字 (${t.coordPrecisionM})`)
  else {
    const expect = recompute(t.startLat, t.startLon, t.endLat, t.endLon)
    if (expect === 0 && t.coordPrecisionM !== 0)
      fail(id, `两端都没有坐标却标了精度 ${t.coordPrecisionM}`)
    else if (expect > 0 && t.coordPrecisionM < expect)
      fail(id, `coordPrecisionM=${t.coordPrecisionM} 比坐标量化下限 ${expect} 还准 —— 虚报精度`)
  }
  if (!TRAVEL_SOURCES.has(t.coordSource)) fail(id, `coordSource=${JSON.stringify(t.coordSource)} 不在认可集合里`)

  const sameCity = usable(t.startLat, t.startLon) && t.startLat === t.endLat && t.startLon === t.endLon
  if (t.coordSource === 'city_center' && !sameCity)
    fail(id, '标了 city_center 但两端不是同一个点 —— 这个标记的含义就是"两端取了同一个城区中心"')
  if (sameCity && t.coordSource !== 'city_center')
    fail(id, '两端逐位相同却标 ' + t.coordSource + ' —— UI 会把它当成实测环线画')

  const off = t.endCoordUnavailable === true
  if (off && !(t.endLat === 0 && t.endLon === 0))
    fail(id, `endCoordUnavailable 为真但终点还有坐标 ${t.endLat},${t.endLon}`)
  if (!off && !usable(t.endLat, t.endLon))
    fail(id, `终点不可用 (${t.endLat},${t.endLon}) 却没标 endCoordUnavailable`)
  for (const [k, v] of [['startLat', t.startLat], ['startLon', t.startLon], ['endLat', t.endLat], ['endLon', t.endLon]]) {
    if (Math.abs(v) > 90 && k.endsWith('Lat')) fail(id, `${k}=${v} 越界 (91 是 QGeoCoordinate 未设置的哨兵值)`)
    if (Math.abs(v) > 180 && k.endsWith('Lon')) fail(id, `${k}=${v} 越界 (181 是哨兵值)`)
  }

  // 自驾同样有 E1/E2: 两端同点但路线明显不是环线, 或里程短于端点直线
  if (usable(t.startLat, t.startLon) && usable(t.endLat, t.endLon) && !sameCity && isNum(t.distanceKm) && t.distanceKm > 0) {
    const km = gapM({ lat: t.startLat, lon: t.startLon }, { lat: t.endLat, lon: t.endLon }) / 1000
    const tol = 2 * (pointPrecisionM(t.startLat, t.startLon) + pointPrecisionM(t.endLat, t.endLon)) / 1000
    if (km > t.distanceKm + tol)
      fail(id, `E2 复发: 里程 ${t.distanceKm}km < 端点直线 ${km.toFixed(1)}km (容差 ${tol.toFixed(1)}km)`)
  }

  // 这个文件的键是驼峰; 混进蛇形说明有人按 routes.json 的样子抄了, 解析端读不到 →
  // 全站精度读数静默消失 (#44 C2 的键名混用问题在本字段上的具体表现)。
  for (const bad of ['coord_precision_m', 'coord_source', 'end_coord_unavailable']) {
    if (Object.prototype.hasOwnProperty.call(t, bad))
      fail(id, `travel.json 里出现了蛇形键 ${bad} —— TravelService 读的是驼峰, 这个值没人会读`)
  }
}

console.log(`coord_metadata_check: ${ROOT}`)
console.log(`routes.json ${routes.length} 条 (带实测轨迹 ${withTrack} 条), travel.json ${travels.length} 条`)
if (hits.length) {
  for (const h of hits.slice(0, 40)) console.log('  ✗ ' + h)
  if (hits.length > 40) console.log(`  … 还有 ${hits.length - 40} 条`)
}
console.log(hits.length ? `✗ 命中 ${hits.length} 处` : '✓ 精度元数据/来源/端点状态/轨迹结构 全部自洽 (0 处)')
process.exit(hits.length ? 1 : 0)
