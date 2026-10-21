// 临时核对: 把 RouteListPage 的 rebuild() 逻辑照搬到 JS, 对 routes.json 真实数据跑一遍,
// 确认分组数/条数/月份匹配/难度上限语义与预期一致. 不属于构建产物.
const fs = require('fs')
const d = JSON.parse(fs.readFileSync(require('path').resolve(__dirname, '../../assets/data/routes.json'), 'utf8'))
const rs = d.routes

// 复刻 C++ isRecommended
const isRec = r => !(r.not_recommended || r.notRecommended) &&
  (!((r.max_altitude_m || 0) >= 6000) || r.type === '休闲徒步' || r.type === '休闲登山')

// 复刻 getAdvanced 无过滤的返回键
const library = rs.filter(isRec).map(r => ({
  id: r.id, name: r.name, province: r.province, difficulty: r.difficulty,
  distanceKm: r.distance_km, daysNeeded: r.days_needed, bestSeason: r.best_season,
  routeNature: r.routeNature || r.route_nature, isWild: r.isWild !== undefined ? r.isWild : r.is_wild,
  maxAltitudeM: r.max_altitude_m
}))

function plateCode(prefix, id) {
  const n = /^-?\d+$/.test(id) ? String(Number(id)) : String(fnv(id) % 1000)
  return prefix + '-' + (n.length < 3 ? n.padStart(3, '0') : n)
}
function fnv(s) { let h = 2166136261; for (const ch of s) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619) >>> 0 } return h }

const hasMonth = (seasons, m) => Array.isArray(seasons) && seasons.indexOf(m + '月') >= 0
const formatKm = km => (km <= 0 ? '0' : (km === Math.round(km) ? String(Math.round(km)) : km.toFixed(1)))

function rebuild(maxDifficulty, province, month) {
  const bucket = {}, order = []
  let shown = 0
  for (const r of library) {
    const d2 = Number(r.difficulty) || 1
    if (maxDifficulty > 0 && d2 > maxDifficulty) continue
    const p = String(r.province || '未标注')
    if (province !== '' && p !== province) continue
    if (month > 0 && !hasMonth(r.bestSeason, month)) continue
    if (!bucket[p]) { bucket[p] = []; order.push(p) }
    bucket[p].push({ ...r, plate: plateCode('RT', String(r.id)) })
    shown++
  }
  order.sort((a, b) => a < b ? -1 : a > b ? 1 : 0)
  const out = []
  for (const key of order) {
    const members = bucket[key].sort((a, b) => a.plate < b.plate ? -1 : a.plate > b.plate ? 1 : 0)
    out.push({ kind: 'head', label: key, count: members.length })
    members.forEach(m => out.push({ kind: 'item', ...m }))
  }
  return { out, shown }
}

const all = rebuild(0, '', 0)
const provs = [...new Set(library.map(r => r.province))].sort((a, b) => a < b ? -1 : 1)
console.log('library', library.length, 'heads', all.out.filter(x => x.kind === 'head').length,
  'provinceTotal(去重)', provs.length, 'items', all.shown,
  'hidden', rs.length - library.length)
console.log('前 3 组:', all.out.filter(x => x.kind === 'head').slice(0, 3).map(h => h.label + ' ' + h.count).join(' | '))
const s = rebuild(3, '四川', 7)
console.log('筛 3星及以下 + 四川 + 7月 ->', s.shown, '条 /', s.out.filter(x => x.kind === 'head').length, '组')
console.log('样例行:', all.out.filter(x => x.kind === 'item').slice(0, 2).map(x =>
  `${x.plate} ${x.name} | ${formatKm(x.distanceKm)} km · ${x.daysNeeded} 天 · ${x.routeNature}${x.isWild === true ? ' · 野线' : ''}`).join('  ||  '))
const first = all.out.filter(x => x.kind === 'item')[0]
console.log('首行原样:', JSON.stringify({ plate: first.plate, name: first.name, km: formatKm(first.distanceKm), days: first.daysNeeded, nature: first.routeNature, wild: first.isWild === true }))
// 月份覆盖: 每月能筛出多少条 (确认没有空月份导致"筛不出"的误解)
const byMonth = []
for (let m = 1; m <= 12; m++) byMonth.push(m + '月:' + rebuild(0, '', m).shown)
console.log('按月:', byMonth.join(' '))
// 最长名称 (评估 elide)
const longest = library.reduce((a, b) => (b.name || '').length > (a.name || '').length ? b : a)
console.log('最长名称', longest.name.length, longest.name)
