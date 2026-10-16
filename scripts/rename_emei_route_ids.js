// 修复路线 id 前缀错误 (2026-10-08)
// 100 条路线误用 route_emei_* 前缀 (峨眉山), 实际分布全国.
// 改为 route_<province_code 小写>_<原后缀>. 已验证 0 冲突 / 0 内部重复.
// 幂等: 已改过的 id 不再匹配 /^route_emei_/.  DRY=1 只打印不写盘.
const fs = require('fs');
const DRY = process.env.DRY === '1';
const path = 'assets/data/routes.json';
const d = JSON.parse(fs.readFileSync(path, 'utf-8'));

const existing = new Set(d.routes.map(r => r.id));
const bad = d.routes.filter(r => /^route_emei_/.test(r.id));

const map = {};
const newSet = new Set();
let collision = 0, dup = 0;
for (const r of bad) {
  const pc = (r.province_code || '').toLowerCase();
  if (!pc) { console.error('缺 province_code:', r.id); process.exit(1); }
  const suf = r.id.replace(/^route_emei_/, '');
  // 后缀已含省份码时 (route_emei_sx2/SX) → route_sx2, 避免 route_sx_sx2 冗余
  const nid = suf.toLowerCase().startsWith(pc) ? 'route_' + suf : 'route_' + pc + '_' + suf;
  if (existing.has(nid)) { console.error('与现有 id 冲突:', r.id, '->', nid); collision++; }
  if (newSet.has(nid)) { console.error('新集内重复:', nid); dup++; }
  newSet.add(nid);
  map[r.id] = nid;
}
if (collision || dup) { console.error('校验失败, 中止'); process.exit(1); }

for (const r of bad) {
  console.log(`${r.id}  ->  ${map[r.id]}   [${r.name}]`);
}

if (!DRY) {
  for (const r of d.routes) if (map[r.id]) r.id = map[r.id];
  fs.writeFileSync(path, JSON.stringify(d, null, 2));
  console.log('\n已写盘. 重命名', Object.keys(map).length, '条.');
} else {
  console.log('\nDRY 模式, 未写盘. 将重命名', Object.keys(map).length, '条.');
}
