// 修正 route_sd_sx (济南千佛山) name/description 矛盾 (2026-10-08)
//   问题: name 含"泰山", description 称"泰山/2 日", 但数据为 8km / 1 天 / 济南市内
//         (mountain=千佛山, max_altitude=280m, highlights 仅市区三景). 泰山不在此线.
//   修正: 标题/描述去掉泰山, 改为纯济南市区泉城环线; 天数改 1 日, 与实际一致.
// 幂等: 修正后标题不再含 "泰山", 重复跑不产生变化.  DRY=1 只打印不写盘.
const fs = require('fs');
const DRY = process.env.DRY === '1';
const path = 'assets/data/routes.json';
const d = JSON.parse(fs.readFileSync(path, 'utf-8'));
const r = d.routes.find(x => x.id === 'route_sd_sx');
if (!r) { console.error('未找到 route_sd_sx'); process.exit(1); }

const before = { name: r.name, description: r.description };
r.name = '济南-千佛山-大明湖-趵突泉';
r.description = '济南泉城经典市区环线:千佛山登顶俯瞰泉城,串联大明湖、趵突泉三大名胜,全程 8 公里 1 日可毕。';

console.log('name:', before.name, ' -> ', r.name);
console.log('description:', before.description, ' -> ', r.description);

if (!DRY) {
  fs.writeFileSync(path, JSON.stringify(d, null, 2));
  console.log('已写盘.');
} else {
  console.log('DRY 模式, 未写盘.');
}
