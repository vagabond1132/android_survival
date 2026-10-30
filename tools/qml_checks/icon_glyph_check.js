/**
 * icon_glyph_check.js — 引用了字体里没有的 Material 图标名 = 空白格 + 运行期 console.warn
 *
 * 为什么要这一道: IconLabel 的 _iconMap 是唯一码位来源, 名字写错或写了字体里没的
 * 图标, 桌面上一切正常 (只是那颗格子空着), 真机上就是动作带/筛选行里缺图.
 * 2026-10-28 #156 一次新增两枚 (layers_clear / restart_alt) 全中, 说明这事靠肉眼不可持续.
 *
 * 认三种图标槽位:
 *   IconLabel { name: "xxx" }  —— 直接写死的那些 (只在 IconLabel 块内查, 避开
 *                                地图图层列表里 `{ name: "osm" }` 这种同名不同义)
 *   iconName: "xxx"            —— Section / SheetPanelHead 等组件透传
 *   icon: "xxx"                —— 动作带/筛选行数据里的 { icon: "xxx" }
 * 变量表达式 (icon: modelData.icon) 静态验不了, 由数据源文件里的字面量兜住:
 * 只要那份字面量写在 .qml 里, 同一条规则就会抓到.
 *
 * 用法: <node> icon_glyph_check.js <项目根=app 目录>
 * 退出码: 0 干净 / 1 有未映射图标 / 2 门禁自己没跑成 (防静默绿)
 */
'use strict';
const fs = require('fs');
const path = require('path');

// 默认根目录 = 仓库里的 app 目录 (与本目录其它检查器同一口径: 不传参也能跑)
const root = process.argv[2] || path.join(__dirname, '..', '..');
const iconLabelPath = path.join(root, 'qml', 'components', 'base', 'IconLabel.qml');
if (!fs.existsSync(iconLabelPath)) {
    console.error('找不到 ' + iconLabelPath + ' —— 门禁没跑, 不是"没问题"');
    process.exit(2);
}

// 1) _iconMap 的键 = 字体真有的码位
const ilSrc = fs.readFileSync(iconLabelPath, 'utf8');
const glyphs = new Set();
for (const m of ilSrc.matchAll(/"([a-z0-9_]+)":\s*"[^"]*"/g)) glyphs.add(m[1]);
if (glyphs.size < 50) {
    console.error('_iconMap 只解析出 ' + glyphs.size + ' 个键, 解析式失效, 拒绝出结论');
    process.exit(2);
}

function walk(dir, out) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.qml')) out.push(p);
    }
    return out;
}
const files = walk(path.join(root, 'qml'), []).filter(f => f !== iconLabelPath);

// 2) IconLabel { ... } 的块范围 (花括号配平), 块内才认 name:
function iconLabelRanges(src) {
    const ranges = [];
    for (const m of src.matchAll(/IconLabel\s*\{/g)) {
        let depth = 0, i = m.index + m[0].length - 1;
        for (; i < src.length; i++) {
            const c = src[i];
            if (c === '{') depth++;
            else if (c === '}') { depth--; if (depth === 0) break; }
        }
        ranges.push([m.index, i]);
    }
    return ranges;
}

const hits = [];
let checked = 0;
for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    const ranges = iconLabelRanges(src);
    const inIconLabel = idx => ranges.some(([a, b]) => idx >= a && idx <= b);
    const rel = path.relative(root, f).split(path.sep).join('/');
    // 属性槽: 前面不能是 "." (排除 obj.name: "x" 这类三元/取属性)
    const slotRe = /(^|[^.\w])(iconName|icon|name)\s*:\s*"([a-z0-9_]+)"/g;
    for (const m of src.matchAll(slotRe)) {
        const prop = m[2], name = m[3];
        if (prop === 'name' && !inIconLabel(m.index)) continue;
        checked++;
        if (glyphs.has(name)) continue;
        const lineNo = src.slice(0, m.index).split('\n').length;
        hits.push(rel + ':' + lineNo + '  ' + src.split('\n')[lineNo - 1].trim()
                  + '   → "' + name + '" 不在 _iconMap');
    }
}

console.log('码位表 ' + glyphs.size + ' 项; 扫描 ' + files.length + ' 个 .qml, 图标槽 ' + checked + ' 处');
if (hits.length) {
    console.log('未映射图标 ' + hits.length + ' 处:');
    for (const h of hits) console.log('  · ' + h);
    process.exit(1);
}
console.log('未映射图标 0 处');
