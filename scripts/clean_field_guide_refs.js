// 清理四图鉴遗留数据质量问题 (2026-10-08)
//  A. malformed route_association: {"rid","ms"} -> {"route_id","months"}
//  B. 无效 route_id: 按语义映射到 routes.json 真实存在的 id
//  C. 悬空 look_alike id: 按 common_name 归一匹配修正; 匹配不到的删除该项 id 字段 (保留 name/distinction/fatality)
// 幂等: 可重复跑. DRY=1 只打印不写盘.
const fs = require('fs');
const DRY = process.env.DRY === '1';
const ROOT = 'assets/data/';
const files = {
  plants: 'field_guide_plants.json',
  animals: 'field_guide_animals.json',
  insects: 'field_guide_insects.json',
  mushrooms: 'field_guide_mushrooms.json'
};

// routes.json 全部真实 id
const routes = JSON.parse(fs.readFileSync(ROOT + 'routes.json', 'utf-8')).routes;
const validRouteIds = new Set(routes.map(r => r.id));

// 语义映射 (旧无效 id -> 真实 id). route_hengshan_north 本已真实, 不在此表.
const routeMap = {
  'laoshan_5t4p': 'route_classic_laoshan_5t4p',   // 崂山五顶四瀑经典大穿越
  'taishan_xx': 'route_sd_taishan_xx',            // 泰山桃花源-后石坞-天烛峰野线
  'hengshan_xx': 'route_sx_hengshan_yw_xx',       // 恒山-悬空寺北岳天峰岭野线
  'taihang_south': 'route_xx_final_20',           // 南太行双岭...野线大环
  'songshan_xx': 'route_feng_mt_zh',              // 郑州-嵩山-中岳庙-卢崖瀑布徒步
};

// 校验映射目标真实存在
for (const [k, v] of Object.entries(routeMap)) {
  if (!validRouteIds.has(v)) { console.error('映射目标不存在:', k, '->', v); process.exit(1); }
}

// 全量条目 id + common_name 归一化索引
const data = {};
const allIds = new Set();
const byNormName = new Map();
const norm = s => (s || '').replace(/[（(][^）)]*[）)]/g, '').replace(/\s/g, '').trim();
for (const [k, f] of Object.entries(files)) data[k] = JSON.parse(fs.readFileSync(ROOT + f, 'utf-8'))[k];
for (const arr of Object.values(data)) for (const e of arr) allIds.add(e.id);
for (const arr of Object.values(data)) for (const e of arr) {
  const n = norm(e.common_name);
  if (n && !byNormName.has(n)) byNormName.set(n, e.id);
}

const stat = { malformed: 0, remapped: 0, laFixed: 0, laDropped: 0 };
const log = [];

for (const [k, arr] of Object.entries(data)) {
  for (const e of arr) {
    // A + B: route_associations
    for (const ra of (e.route_associations || [])) {
      if (ra.rid !== undefined) {                    // A
        ra.route_id = ra.rid; delete ra.rid;
        ra.months = ra.ms; delete ra.ms;
        stat.malformed++;
        log.push(`[A] ${k}/${e.id} rid->route_id, ms->months`);
      }
      if (ra.route_id && !validRouteIds.has(ra.route_id)) {  // B
        const target = routeMap[ra.route_id];
        if (target) {
          log.push(`[B] ${k}/${e.id} ${ra.route_id} -> ${target}`);
          ra.route_id = target;
          stat.remapped++;
        } else {
          log.push(`[B] ${k}/${e.id} ${ra.route_id} -> (无映射, 删该项)`);
          ra._drop = true;
          stat.remapped++;
        }
      }
    }
    if (e.route_associations) e.route_associations = e.route_associations.filter(x => !x._drop);

    // C: look_alike
    for (const la of (e.look_alike || [])) {
      if (la.id && !allIds.has(la.id)) {
        const n = norm(la.name);
        if (n && byNormName.has(n)) {
          log.push(`[C-fix] ${k}/${e.id} ${la.id} -> ${byNormName.get(n)}  [${la.name}]`);
          la.id = byNormName.get(n);
          stat.laFixed++;
        } else {
          log.push(`[C-del] ${k}/${e.id} 删 id 保留文案 [${la.name || '?'}]`);
          delete la.id;
          stat.laDropped++;
        }
      }
    }
  }
}

console.log(log.join('\n'));
console.log('\n统计:', JSON.stringify(stat));

if (!DRY) {
  for (const [k, f] of Object.entries(files)) fs.writeFileSync(ROOT + f, JSON.stringify({ ...JSON.parse(fs.readFileSync(ROOT + f, 'utf-8')), [k]: data[k] }, null, 2));
  console.log('已写盘.');
} else {
  console.log('DRY 模式, 未写盘.');
}
