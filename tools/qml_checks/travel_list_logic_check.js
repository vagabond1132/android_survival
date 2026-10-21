// TravelListPage 目录逻辑核对 —— 拿真数据跑一遍 rebuild(), 不看渲染只看数
// 用法: ELECTRON_RUN_AS_NODE=1 Qoder.exe travel_list_logic_check.js
const fs = require('fs');
const ROOT = process.argv[2] || require('path').resolve(__dirname, '../..');
const raw = JSON.parse(fs.readFileSync(ROOT + '/assets/data/travel.json', 'utf8'));
const library = raw.routes;

// 与 QML 同步的 FNV-1a plateCode (CommonOptions::plateCode)
function plateCode(prefix, id, width = 3) {
    let h = 2166136261;
    for (let i = 0; i < id.length; ++i) { h ^= id.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
    return prefix + '-' + String(h % 1000).padStart(width, '0');
}
const dayRanges = [[0, 0], [1, 2], [3, 5], [6, 10], [11, 0]];
const kmRanges = [[0, 0], [0, 500], [500, 1000], [1000, 2000], [2000, 0]];
const inDays = (d, b) => b === 0 ? true : (d <= 0 ? false : (d >= dayRanges[b][0] && (dayRanges[b][1] <= 0 || d <= dayRanges[b][1])));
const inKm = (k, b) => b === 0 ? true : (k <= 0 ? false : (k >= kmRanges[b][0] && (kmRanges[b][1] <= 0 || k < kmRanges[b][1])));
const hasMonth = (seasons, m) => Array.isArray(seasons) && seasons.indexOf(m + '月') >= 0;

// 省份候选 (码位序) + 里程跨度, 对应 loadLibrary()
const seen = new Set();
let lo = 0, hi = 0, noKm = 0, noDays = 0, noAlt = 0, noRoad = 0;
for (const t of library) {
    if (t.province) seen.add(String(t.province));
    const km = Math.round(Number(t.distanceKm) || 0);
    if (km <= 0) { noKm++; } else { if (lo === 0 || km < lo) lo = km; if (km > hi) hi = km; }
    if (!(Number(t.days) > 0)) noDays++;
    if (!(Number(t.maxAltitude) > 0)) noAlt++;
    if (!t.roadType) noRoad++;
}
const keys = [...seen].sort();
console.log('库', library.length, '条 · 分组', keys.length, '· 里程', lo + '~' + hi,
            '· 缺里程', noKm, '缺天数', noDays, '缺海拔', noAlt, '缺路面', noRoad);

function rebuild(state) {
    const bucket = new Map(); const order = []; let shown = 0;
    for (const t of library) {
        const p = String(t.province || '未标注');
        if (state.province !== '' && p !== state.province) continue;
        if (state.month > 0 && !hasMonth(t.bestSeason, state.month)) continue;
        const days = Number(t.days) || 0;
        if (!inDays(days, state.daysBucket)) continue;
        const km = Number(t.distanceKm) || 0;
        if (!inKm(km, state.kmBucket)) continue;
        const s = String(t.startName || t.startCity || ''), e = String(t.endName || t.endCity || '');
        if (!bucket.has(p)) { bucket.set(p, []); order.push(p); }
        bucket.get(p).push({ id: t.id, name: t.name, plate: plateCode('TV', String(t.id)),
                             loop: (s !== '' && s === e), fromTo: s + ' → ' + e, km, days,
                             alt: Number(t.maxAltitude) || 0, road: String(t.roadType || '') });
        shown++;
    }
    order.sort();
    const out = [];
    let longest = 0, noEndpoint = 0;
    for (const key of order) {
        const members = bucket.get(key).sort((a, b) => a.plate < b.plate ? -1 : a.plate > b.plate ? 1 : 0);
        out.push({ kind: 'head', label: key, count: members.length });
        for (const m of members) {
            out.push({ kind: 'item', ...m });
            const sub = (m.loop ? '环线 · ' : '') + m.fromTo + ' · ' + m.km + ' km · ' + m.road;
            longest = Math.max(longest, sub.length);
            if (m.fromTo === ' → ') noEndpoint++;
        }
    }
    return { rows: out, shown, longest, noEndpoint };
}

const all = rebuild({ daysBucket: 0, kmBucket: 0, province: '', month: 0 });
console.log('全筛:', all.rows.length, '节点 (head+item) · item', all.shown, '· 最长副行', all.longest, '字 · 空起终点', all.noEndpoint);
for (let b = 1; b <= 4; ++b) {
    console.log('  天数档', b, dayRanges[b].join('~'), '→', rebuild({ daysBucket: b, kmBucket: 0, province: '', month: 0 }).shown, '条');
    console.log('  里程档', b, kmRanges[b].join('~'), '→', rebuild({ daysBucket: 0, kmBucket: b, province: '', month: 0 }).shown, '条');
}
console.log('  月份 5 →', rebuild({ daysBucket: 0, kmBucket: 0, province: '', month: 5 }).shown,
            '· 月份 12 →', rebuild({ daysBucket: 0, kmBucket: 0, province: '', month: 12 }).shown);
const one = rebuild({ daysBucket: 0, kmBucket: 0, province: '四川/西藏', month: 0 });
console.log('  跨省组「四川/西藏」→', one.shown, '条 · 组数', new Set(one.rows.filter(r => r.kind === 'head').map(r => r.label)).size);
const combo = rebuild({ daysBucket: 2, kmBucket: 3, province: keys[3], month: 6 });
console.log('  组合(3-5天+1000-2000km+' + keys[3] + '+6月) →', combo.shown, '条');
const s0 = all.rows.find(r => r.kind === 'item');
console.log('  首行:', s0.plate, s0.name, '|', (s0.loop ? '环线 · ' : '') + s0.fromTo, '|', s0.km, 'km', s0.days, '天', s0.alt, 'm', s0.road);
// 编号唯一性: 同组内 plate 不能撞 (plateW=46 只放得下 TV-123)
const plates = all.rows.filter(r => r.kind === 'item').map(r => r.plate);
const dup = plates.length - new Set(plates).size;
console.log('  编号撞车', dup, '对 (全局唯一性只是好看, 组内不重复才影响读)');
