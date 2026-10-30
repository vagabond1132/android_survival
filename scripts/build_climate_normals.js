// 十年实测气候常态表生成器 (2026-10-28 A42-1 / #147)
//
// 为什么重写这张表: 旧表 (2026-10-22 那版) 自己的 source_note 就写着"月内形状是模型:
// 气温正弦、降水环形高斯", 也就是只有 1/7 月两个锚点是查来的, 其余 10 个月是插出来的。
// 用户要的是「往年 10 年内」的统计, 那就得真的按 10 年逐日数据算, 不能继续交一份正弦曲线。
//
// 数据源: open-meteo 的 ERA5 归档 (archive-api.open-meteo.com/v1/archive), 免 key。
// 本机实测可达 (http=200), 且归档里**没有** uv_index 字段 (2015 年那几天返回全 null),
// 所以 uvIndex 是唯一保留"模型"身份的一项 —— 但云量那一半改用**实测短波辐射**
// (shortwave_radiation_sum) 对天文晴空辐射的透过率, 不再用拍出来的季节因子。
// 哪一项是实测、哪一项是模型, 全部写进产物的 source_note, 不给假出处。
//
// 用法 (Windows 主机没有 node, 用 Qoder 自带的 Electron 当 node; 路径要给 D:/ 形状):
//   export ELECTRON_RUN_AS_NODE=1
//   "$QODER" scripts/build_climate_normals.js fetch  --cache D:/build_work_ai_dir/dev/pass8/climate_raw
//   "$QODER" scripts/build_climate_normals.js build  --cache ... [--write]
// fetch 一支把每个省的原始响应落盘 (34 支请求, 一支十几秒, 可断点续), build 只读缓存,
// 不联网 —— 改聚合口径时重跑 build 就行。--write 才覆盖仓库里的 json, 默认只打到 stdout。
'use strict';
const fs = require('fs'), path = require('path'), https = require('https');

const REPO = path.resolve(__dirname, '..');
const OUT = path.join(REPO, 'assets', 'data', 'climate_normals.json');
const START = '2016-01-01', END = '2025-12-31';   // 10 个完整自然年
const DAILY = 'temperature_2m_mean,temperature_2m_min,temperature_2m_max,'
            + 'precipitation_sum,wind_speed_10m_mean,shortwave_radiation_sum';

// 34 个省级代表站 = 省会/首府城区。旧表只有 lat (且内蒙古 42 / 西藏 31 这类是"省域中心",
// 不是有人住的地方), 现在按"代表站"的字面意思取城区经纬, 海拔改用数据源格点实测值。
const STATIONS = [
    ['北京', 39.90, 116.40], ['天津', 39.10, 117.20], ['河北', 38.04, 114.51],
    ['山西', 37.87, 112.55], ['内蒙古', 40.84, 111.75], ['辽宁', 41.80, 123.43],
    ['吉林', 43.88, 125.32], ['黑龙江', 45.80, 126.53], ['上海', 31.23, 121.47],
    ['江苏', 32.06, 118.80], ['浙江', 30.27, 120.15], ['安徽', 31.82, 117.23],
    ['福建', 26.07, 119.30], ['江西', 28.68, 115.89], ['山东', 36.65, 117.12],
    ['河南', 34.75, 113.62], ['湖北', 30.59, 114.30], ['湖南', 28.23, 112.94],
    ['广东', 23.13, 113.26], ['广西', 22.82, 108.32], ['海南', 20.02, 110.35],
    ['重庆', 29.56, 106.55], ['四川', 30.57, 104.07], ['贵州', 26.65, 106.63],
    ['云南', 25.04, 102.71], ['西藏', 29.65, 91.14], ['陕西', 34.34, 108.94],
    ['甘肃', 36.06, 103.83], ['青海', 36.62, 101.78], ['宁夏', 38.49, 106.29],
    ['新疆', 43.83, 87.62], ['香港', 22.32, 114.17], ['澳门', 22.20, 113.55],
    ['台湾', 25.03, 121.50],
];

function arg(name, dflt) {
    const i = process.argv.indexOf('--' + name);
    return i > 0 && process.argv[i + 1] ? process.argv[i + 1] : dflt;
}
const CACHE = path.resolve(arg('cache', path.join(REPO, '..', 'climate_raw')));

// ---------- fetch ----------
function urlFor(lat, lon) {
    return 'https://archive-api.open-meteo.com/v1/archive'
        + `?latitude=${lat}&longitude=${lon}&start_date=${START}&end_date=${END}`
        + `&daily=${DAILY}&timezone=Asia%2FShanghai`;
}
function get(url) {
    return new Promise((resolve, reject) => {
        const req = https.get(url, { timeout: 120000 }, res => {
            if (res.statusCode !== 200) {
                res.resume();
                return reject(new Error(`HTTP ${res.statusCode} ${url}`));
            }
            let s = '';
            res.setEncoding('utf8');
            res.on('data', d => s += d);
            res.on('end', () => resolve(s));
        });
        req.on('timeout', () => req.destroy(new Error('超时')));
        req.on('error', reject);
    });
}
const sleep = ms => new Promise(r => setTimeout(r, ms));
// 十年逐日一支请求算"重"调用, 实测连发到第 7 支就 HTTP 429 (open-meteo 免费档的突发限制)。
// 所以每支之间隔 PAUSE_MS, 撞上 429 就退避重等 —— 缓存已在磁盘上, 断了重跑接着往下走。
const PAUSE_MS = Number(arg('pause', 12000));
async function getPolite(url) {
    for (let attempt = 1; ; ++attempt) {
        try {
            return await get(url);
        } catch (e) {
            if (!/HTTP 429|超时/.test(e.message) || attempt >= 6) throw e;
            const wait = 30000 * attempt;
            console.log(`退避 ${wait / 1000}s 后重试 (第 ${attempt} 次: ${e.message.slice(0, 24)})`);
            await sleep(wait);
        }
    }
}
async function fetchAll() {
    fs.mkdirSync(CACHE, { recursive: true });
    let todo = 0;
    for (const [name, lat, lon] of STATIONS) {
        if (!fs.existsSync(path.join(CACHE, `${name}.json`))) todo++;
    }
    console.log(`待拉 ${todo} 支 × ~${PAUSE_MS / 1000}s 间隔`);
    for (const [name, lat, lon] of STATIONS) {
        const f = path.join(CACHE, `${name}.json`);
        if (fs.existsSync(f) && fs.statSync(f).size > 10000) {
            console.log(`跳过 ${name} (缓存已有)`);
            continue;
        }
        process.stdout.write(`拉 ${name} ${lat},${lon} … `);
        const t0 = Date.now();
        const body = await getPolite(urlFor(lat, lon));
        fs.writeFileSync(f, body);
        console.log(`${(body.length / 1024).toFixed(0)}KB ${((Date.now() - t0) / 1000).toFixed(1)}s`);
        await sleep(PAUSE_MS);
    }
}

// ---------- 天文晴空辐射 (MJ/m²/日) ----------
// Ra = (1440/π)·Gsc·dr·(ws·sinφ·sinδ + cosφ·cosδ·sin ws)  —— 教科书式 (Allen 等 FAO-56)
function clearSkyRa(latDeg, doy) {
    const GSC = 0.0820;                                   // MJ/m²/min
    const rad = Math.PI / 180;
    const phi = latDeg * rad;
    const dr = 1 + 0.033 * Math.cos(2 * Math.PI * doy / 365);
    const decl = 0.409 * Math.sin(2 * Math.PI * (284 + doy) / 365);
    let x = -Math.tan(phi) * Math.tan(decl);
    if (x >= 1) return (1440 / Math.PI) * GSC * dr * Math.PI * Math.sin(phi) * Math.sin(decl) > 0
        ? (1440 / Math.PI) * GSC * dr * (Math.PI * Math.sin(phi) * Math.sin(decl)) : 0;   // 极昼
    if (x <= -1) return 0;                                                    // 极夜
    const ws = Math.acos(x);
    return (1440 / Math.PI) * GSC * dr
        * (ws * Math.sin(phi) * Math.sin(decl) + Math.cos(phi) * Math.cos(decl) * Math.sin(ws));
}
// 正午太阳高度 (度)
function noonAlt(latDeg, doy) {
    const decl = 23.45 * Math.sin(2 * Math.PI * (284 + doy) / 365);
    return 90 - Math.abs(latDeg - decl);
}
function doyOf(iso) {
    const [y, m, d] = iso.split('-').map(Number);
    return Math.round((Date.UTC(y, m - 1, d) - Date.UTC(y, 0, 1)) / 86400000) + 1;
}

// ---------- build ----------
const r1 = v => Math.round(v * 10) / 10;
function build() {
    const provinces = {};
    const report = [];
    for (const [name, lat, lon] of STATIONS) {
        const f = path.join(CACHE, `${name}.json`);
        if (!fs.existsSync(f)) throw new Error(`缺缓存 ${f} —— 先跑 fetch`);
        const j = JSON.parse(fs.readFileSync(f, 'utf8'));
        const d = j.daily;
        if (!d || !d.time) throw new Error(`${name}: 响应里没有 daily.time`);
        const n = d.time.length;
        const acc = Array.from({ length: 12 }, () => ({
            n: 0, tmean: 0, tmin: 0, tmax: 0, precip: 0, wind: 0, sr: 0, ra: 0, rain: 0,
        }));
        for (let i = 0; i < n; ++i) {
            const m = Number(d.time[i].slice(5, 7)) - 1;
            const a = acc[m];
            const tm = d.temperature_2m_mean[i], tn = d.temperature_2m_min[i],
                  tx = d.temperature_2m_max[i], pp = d.precipitation_sum[i],
                  ww = d.wind_speed_10m_mean[i], sr = d.shortwave_radiation_sum[i];
            if (tm === null || tm === undefined) continue;      // 缺一天就少一天, 不补假值
            a.n++; a.tmean += tm; a.tmin += tn; a.tmax += tx;
            a.precip += pp; a.wind += ww;
            a.rain += (pp >= 1 ? 1 : 0);
            const doy = doyOf(d.time[i]);
            a.sr += (sr === null ? 0 : sr);
            a.ra += clearSkyRa(lat, doy);
        }
        const years = new Set(d.time.map(s => s.slice(0, 4))).size;
        const col = k => acc.map(a => a.n ? a[k] / a.n : NaN);
        const tempAvg = col('tmean').map(r1);
        const tempMin = col('tmin').map(r1);
        const diurnalRange = acc.map(a => a.n ? r1((a.tmax - a.tmin) / a.n) : NaN);
        const precipMm = acc.map(a => a.n ? r1(a.precip / years) : NaN);
        const windMs = col('wind').map(v => r1(v / 3.6));
        const rainDays = acc.map(a => a.n ? r1(a.rain / years) : NaN);
        // UV: 实测辐射透过率^0.8 × 正午太阳高度^2.2 × 16 上限。
        // 指数 2.2 / 16 是旧表就有的经验形状 (保留是为了不推翻装备引擎的 uvLevel 分档),
        // 换掉的是"云量"这一半: 旧版是季节因子, 现在是 ERA5 实测短波辐射 / 晴空辐射。
        const uvIndex = acc.map((a, mi) => {
            if (!a.n) return NaN;
            const t = a.ra > 0 ? Math.min(1, (a.sr / a.n) / (a.ra / a.n)) : 0;
            const alt = noonAlt(lat, 15 + mi * 30);
            return r1(Math.min(16, 16 * Math.pow(t, 0.8) * Math.pow(Math.max(0, Math.sin(alt * Math.PI / 180)), 2.2)));
        });
        const annualPrecipMm = Math.round(precipMm.reduce((s, v) => s + v, 0));
        const annualPeakMonth = precipMm.indexOf(Math.max(...precipMm)) + 1;
        provinces[name] = {
            name, lat, lon, refAltitudeM: Math.round(j.elevation),
            annualPrecipMm, annualPeakMonth, tempAvg, tempMin, precipMm,
            uvIndex, windMs, diurnalRange, rainDays,
        };
        report.push(`${name.padEnd(4)} 站 ${j.elevation.toFixed(0)}m  年均 ${annualPrecipMm}mm 峰${annualPeakMonth}月  `
            + `1月 ${tempAvg[0]}/${tempMin[0]}℃  7月 ${tempAvg[6]}/${tempMin[6]}℃  `
            + `UV ${uvIndex[6]}  雨日 ${rainDays[6]}d`);
    }
    return { provinces, report };
}

function assertSane(provinces) {
    const bad = [];
    for (const [name, p] of Object.entries(provinces)) {
        for (const k of ['tempAvg', 'tempMin', 'precipMm', 'uvIndex', 'windMs', 'diurnalRange', 'rainDays']) {
            if (p[k].length !== 12) bad.push(`${name}.${k} 长度 ${p[k].length}`);
            p[k].forEach((v, i) => {
                if (!Number.isFinite(v)) bad.push(`${name}.${k}[${i + 1}] 非数`);
            });
        }
        p.tempAvg.forEach((v, i) => { if (v < -30 || v > 40) bad.push(`${name}.tempAvg[${i + 1}]=${v} 越界`); });
        p.precipMm.forEach((v, i) => { if (v < 0 || v > 700) bad.push(`${name}.precipMm[${i + 1}]=${v} 越界`); });
        p.uvIndex.forEach((v, i) => { if (v < 0 || v > 16) bad.push(`${name}.uvIndex[${i + 1}]=${v} 越界`); });
        p.tempMin.forEach((v, i) => { if (v > p.tempAvg[i]) bad.push(`${name} ${i + 1}月 tempMin>tempAvg`); });
    }
    if (bad.length) throw new Error('自检失败:\n  ' + bad.join('\n  '));
}

function write(provinces) {
    const out = {
        version: '0.2.0',
        updated_at: new Date().toISOString().slice(0, 10),
        description: '省级 × 月 气候常态表 —— 装备清单按"路线地点 + 出行月份"自动填天气用',
        source_note:
            `tempAvg/tempMin/precipMm/windMs/diurnalRange/rainDays 是 ${START}~${END} 十个完整自然年`
            + `的 ERA5 逐日实测聚合 (open-meteo archive-api, 免 key), 代表站取省会城区经纬度,`
            + `refAltitudeM 是数据源格点实测海拔。年降水/峰值月由这十年月均值算出。`
            + `只有 uvIndex 仍是模型: ERA5 归档不提供紫外线 (实测过, 字段返回 null),`
            + `所以按"实测短波辐射 ÷ 天文晴空辐射"的透过率 (0.8 次) 乘正午太阳高度 (2.2 次) 再乘 16 上限,`
            + `云量这一半是实测的, 几何与系数是模型的。`
            + `用途仍是"该不该带雨具/羽绒"这一级判断, 不是气象预报精度, 不要当天气预报读。`,
        normals_window: { start: START, end: END, years: 10, basis: 'ERA5 逐日实测 (open-meteo archive-api)' },
        lapse_rate_c_per_1000m: -6.5,
        uv_per_1000m: 0.12,
        altitude_note:
            '表里的温度与紫外线是"代表站海拔 refAltitudeM"处的值。查询时按路线海拔现算: '
            + 'temp += -6.5 * (routeAlt - refAlt) / 1000, uv *= 1 + 0.12 * (routeAlt - refAlt) / 1000。'
            + '不把海拔烘进表是因为同一条路线的海拔才是决定因素 —— 四川的锚点是成都平原, 路线在 4000m。',
        band_note:
            'precipitation 存的是"这个月大概多湿"的档位 (none/light/moderate/heavy/storm), '
            + '对应装备引擎的降雨强度条件; 月降水量 <5/30/90/180 mm 为界。'
            + 'rainDays 是该月日均降水≥1mm 的天数十年平均, 只给来源行与自检用, 引擎不读。',
        months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        provinces,
    };
    const json = JSON.stringify(out, null, 1);
    if (process.argv.includes('--write')) {
        fs.writeFileSync(OUT, json, { encoding: 'utf8' });
        console.log(`已写 ${OUT} (${(json.length / 1024).toFixed(0)}KB, ${Object.keys(provinces).length} 省)`);
    } else {
        console.log('(没加 --write, 只打印前 200 字节)\n' + json.slice(0, 200));
    }
}

const mode = process.argv[2];
if (mode === 'fetch') {
    fetchAll().catch(e => { console.error('fetch 失败: ' + e.message); process.exit(1); });
} else if (mode === 'build') {
    const { provinces, report } = build();
    console.log(report.join('\n'));
    assertSane(provinces);
    console.log(`自检通过: ${Object.keys(provinces).length} 省 × 12 月, 数组完整 / 无 NaN / 区间合理`);
    write(provinces);
} else {
    console.log('用法: build_climate_normals.js fetch|build --cache <dir> [--write]');
    process.exit(2);
}
