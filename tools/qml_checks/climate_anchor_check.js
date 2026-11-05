#!/usr/bin/env node
/**
 * climate_anchor_check.js — 气候表锚点与「地点」默认值口径的门禁 (2026-11-03 #45)
 *
 * 为什么需要它: 装备清单的「地点」现在按**当前定位**反查气候表的省级锚点
 * (EquipmentService::nearestClimateProvince)。这条链子上有三个静默失败点, ctest
 * 只在容器里跑、而且只验"函数返回什么", 验不了"表和生成器还对不对得上":
 *   ① 缺 lon —— QJsonObject::operator[] 对不存在的键给 0.0, 于是"最近锚点"一路算到
 *      本初子午线上去, 34 个省全都还在, 一个错都不报。这一列是 2026-11-03 才补的,
 *      补的时候实测有 **18/34 条与生成器不一致** (手填的省会经度 vs 脚本城区经纬),
 *      全靠对账才发现 —— 对账不写成脚本, 下次重跑 build 就又漂了。
 *   ② 生成器与表的省名集合漂移 (加省只改一处) —— C++ 侧整条跳过那条, 边界处常年填错。
 *   ③ 页面把"表里第一个省"当默认值 —— #45 修掉的那个 bug 的形状就是
 *      `climateProvince = provinceChoices[0]` (表排序第一项是北京), 全国用户在济南
 *      也按北京的气候填, 而且是以"自动档"的名义。这条必须有个脚本挡着, 不然下一次
 *      谁嫌"没定位时这一格是空的"就会顺手补回一个默认值。
 *
 * 判据 (四件事, 全是"数据与来源自洽"):
 *   A 表里 34 条: name 非空 + lat/lon 都在中国范围 (17~54 / 73~136) 且是有限数
 *   B 表里每条的 lon **逐值等于** scripts/build_climate_normals.js 的 STATIONS
 *   C 两个文件的省名集合互相覆盖 (少一侧就是"这一省反查不到")
 *   D 五个城市的最近锚点反查结果不变 (济南→山东 / 昆明→云南 / 拉萨→西藏 /
 *     乌鲁木齐→新疆 / 哈尔滨→黑龙江) —— 动一个锚点就可能把一整片填错, 这里先炸
 *   E qml/pages/*.qml 里不出现 `provinceChoices[0]` / `climateProvince = <常量>` 这类
 *     "给地点塞默认值"的写法
 *
 * 用法: node climate_anchor_check.js [仓库根]      (默认 ../..)
 * 退出码: 0 = 干净, 1 = 有命中, 2 = 门禁自己没跑起来 (文件读不到/JSON 解析失败)。
 * 任何"0 条"的结论先用坏 fixture 反证脚本是活的 (本仓约定, 见 README)。
 */
'use strict'
const fs = require('fs')
const path = require('path')

const REPO = process.argv[2] || path.resolve(__dirname, '../..')
const DATA = path.join(REPO, 'assets/data/climate_normals.json')
const GEN = path.join(REPO, 'scripts/build_climate_normals.js')
const QML_PAGES = path.join(REPO, 'qml/pages')

const hits = []
const fail = (id, msg) => hits.push(`${id}: ${msg}`)
const isNum = (v) => typeof v === 'number' && Number.isFinite(v)

// 中国疆域下限 (海南最南 18°N、黑龙江最北 53°N、帕米尔 73°E、黑龙江与乌苏里江汇合处 135°E),
// 各放 1° 余量。锚点是"省域中心/城区"这一级, 落在这个框外面一定是写错了。
const LAT_MIN = 17, LAT_MAX = 54, LON_MIN = 73, LON_MAX = 136

// ── 读两份文件 ────────────────────────────────────────────────────────────
for (const [label, p] of [['climate_normals.json', DATA], ['build_climate_normals.js', GEN]]) {
    if (!fs.existsSync(p)) {
        console.error(`读不到 ${label}: ${p}  (要仓库根, 别给别处的副本)`)
        process.exit(2)
    }
}
let table
try {
    table = JSON.parse(fs.readFileSync(DATA, 'utf8'))
} catch (e) {
    console.error(`climate_normals.json 解析失败: ${e.message}`)
    process.exit(2)
}
const provinces = Array.isArray(table.provinces) ? table.provinces : null
if (!provinces) {
    console.error('climate_normals.json 没有 provinces 数组 —— 表整个换了形状, 门禁要跟着改')
    process.exit(2)
}

// 生成器里的 STATIONS = 锚点的唯一来源 (表是它生成的, 手改数据不算改来源)
const genSrc = fs.readFileSync(GEN, 'utf8')
const start = genSrc.indexOf('const STATIONS = [')
const end = start < 0 ? -1 : genSrc.indexOf('];', start)
if (start < 0 || end < 0) {
    console.error('build_climate_normals.js 里找不到 `const STATIONS = [` —— 生成脚本改名或重构了, 门禁要跟着改')
    process.exit(2)
}
const stations = new Map()
{
    const re = /\['([^']+)',\s*(-?[\d.]+),\s*(-?[\d.]+)\]/g
    let m
    while ((m = re.exec(genSrc.slice(start, end)))) {
        if (stations.has(m[1])) {
            console.error(`STATIONS 里「${m[1]}」出现两次 —— 反查会取到后写的那条`)
            process.exit(2)
        }
        stations.set(m[1], { lat: Number(m[2]), lon: Number(m[3]) })
    }
}
if (stations.size === 0) {
    console.error('STATIONS 一条也没解析出来 —— 正则与生成脚本的写法不符, 门禁没跑')
    process.exit(2)
}

// ── A/B/C: 表 ↔ 生成器 对账 ───────────────────────────────────────────────
if (provinces.length !== stations.size)
    fail('COUNT', `表里 ${provinces.length} 个省, 生成器 ${stations.size} 个站 —— 两边必须同时加/删`)

const tableNames = new Set()
for (const p of provinces) {
    const id = '省 ' + (p.name || '(无名)')
    if (typeof p.name !== 'string' || !p.name.trim()) { fail(id, 'name 缺失或空白'); continue }
    if (tableNames.has(p.name)) fail(id, '表里这一省出现两次 —— QHash 只留一条, 另一条静默失效')
    tableNames.add(p.name)

    if (!isNum(p.lat)) fail(id, `lat 不是有限数 (${JSON.stringify(p.lat)})`)
    else if (p.lat < LAT_MIN || p.lat > LAT_MAX) fail(id, `lat=${p.lat} 不在中国范围 ${LAT_MIN}~${LAT_MAX}`)

    // 这一条是本门禁存在的理由: 缺 lon 时 C++ 拿 0.0 而不是报错, 所以必须在这里拦
    if (!isNum(p.lon)) {
        fail(id, `lon 缺失或非数 (${JSON.stringify(p.lon)}) —— nearestClimateProvince 会整条跳过这一省`)
        continue
    }
    if (p.lon < LON_MIN || p.lon > LON_MAX) fail(id, `lon=${p.lon} 不在中国范围 ${LON_MIN}~${LON_MAX}`)

    const st = stations.get(p.name)
    if (!st) fail(id, `生成器 STATIONS 里没有这一省 —— 重跑 build 就会把它删掉/留旧值`)
    else if (p.lon !== st.lon)
        fail(id, `lon=${p.lon} 与生成器 STATIONS 的 ${st.lon} 不一致 —— 锚点只有一个来源, 手改数据会漂`)
}
for (const name of stations.keys())
    if (!tableNames.has(name)) fail('省 ' + name, '生成器有这一站, 表里没有 —— 反查不到这一省')

// ── D: 五个城市的反查结果不许变 ────────────────────────────────────────────
// 与 tests/unit/test_equipment_service.cpp 的 test_nearest_climate_province_by_location
// 同一份清单。这里用平面近似算最近 (与 C++ 的 haversine 在同一批锚点上排序一致:
// 这些点对最近的两个锚点差 >40 km, 两种式子的相对误差在这个量级上不改名次)。
// 判据换的是**锚点**, 不是省名 —— 有人挪动锚点就该在这里响。
const KM_PER_DEG = 111.195   // 6371000 * π / 180 / 1000
function nearestOf(lat, lon) {
    let best = null, bd = Infinity
    for (const p of provinces) {
        if (!isNum(p.lat) || !isNum(p.lon)) continue
        // 等距圆柱近似 (与 C++ 的 haversine 只差二阶项; 下面五个点最近的两个锚点差
        // >40 km, 名次不会因这点差别翻) —— 门禁要的是"锚点没被挪走", 不是里程精确值
        const mid = (p.lat + lat) / 2 * Math.PI / 180
        const x = (p.lon - lon) * Math.cos(mid)
        const y = p.lat - lat
        const d = Math.hypot(x, y) * KM_PER_DEG
        if (d < bd) { bd = d; best = p }
    }
    return { name: best ? best.name : '', km: bd }
}
for (const [city, lat, lon, want] of [
    ['济南', 36.65, 117.00, '山东'],       // 真机验收那一条
    ['昆明', 24.88, 102.83, '云南'],
    ['拉萨', 29.65, 91.14, '西藏'],
    ['乌鲁木齐', 43.83, 87.62, '新疆'],
    ['哈尔滨', 45.80, 126.53, '黑龙江'],
]) {
    const got = nearestOf(lat, lon)
    if (got.name !== want)
        fail(`反查 ${city}`, `→ ${got.name || '(没有可用锚点)'} (${got.km.toFixed(0)} km), 期望 ${want} —— 锚点动了, 一整片的地点会跟着填错`)
}

// ── E: 页面不许给地点塞默认值 ──────────────────────────────────────────────
// 「自动档不许有假默认值」这条口径的形状: 拿表里第一项 / 写死一个省名当兜底。
// 没定位时的正确做法是把"没定位"说出来 (EquipmentPage.applyPlaceFromLocation 里那条
// placeLine), 让这一格空着并给原因 —— 不是猜一个省。
const BAD_PATTERNS = [
    [/provinceChoices\s*\[\s*0\s*\]/, '拿表里第一个省当默认值 (#45 修掉的那个形状)'],
    [/climateProvince\s*=\s*["'][^"']+["']/, '把地点写成固定省名'],
]
let qmlFiles = []
if (!fs.existsSync(QML_PAGES)) {
    console.error(`读不到 qml/pages: ${QML_PAGES}`)
    process.exit(2)
}
qmlFiles = fs.readdirSync(QML_PAGES).filter((f) => f.endsWith('.qml'))
for (const f of qmlFiles) {
    const raw = fs.readFileSync(path.join(QML_PAGES, f), 'utf8').split('\n')
        .map((l) => l.replace(/\/\/.*$/, ''))
    raw.forEach((line, i) => {
        for (const [re, why] of BAD_PATTERNS)
            if (re.test(line)) fail(`${f}:${i + 1}`, why)
    })
}

console.log(`climate_anchor_check: ${REPO}`)
console.log(`表 ${provinces.length} 省 · 生成器 ${stations.size} 站 · qml/pages ${qmlFiles.length} 个文件`)
if (hits.length) {
    for (const h of hits.slice(0, 40)) console.log('  ✗ ' + h)
    if (hits.length > 40) console.log(`  … 还有 ${hits.length - 40} 条`)
}
console.log(hits.length ? `✗ 命中 ${hits.length} 处` : '✓ 锚点与生成器逐值一致 · 五城反查不变 · 页面无默认省 (0 处)')
process.exit(hits.length ? 1 : 0)
