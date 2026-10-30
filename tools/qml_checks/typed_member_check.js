/**
 * typed_member_check.js — 在"能被 qmllint 解析出类型的 Qt 类型"上读写它没有的成员
 *
 * 为什么要这一道 (2026-10-28 #156 复盘):
 *   这三类写法**都不报错**: 绑定求成 undefined, 分支永远走 else, 功能静默失效 ——
 *   抽屉高度、悬停高亮、弹层位置就是这么"看起来实现了、其实一条没生效"的.
 *   qmllint 抓得到 (missing-property), 但 2000 行告警里没人逐条看, 所以要一道只为此存在的门禁.
 *
 * 覆盖三类:
 *   1) HoverHandler 上没有 containsMouse (那是 MouseArea 的) → 悬停要用 hovered
 *   2) Qt 6.7 StackLayout 上没有 currentItem (那是 StackView 的) → 按 currentIndex 自己取
 *      (两种都在容器内 offscreen 实测过: `"currentItem" in StackLayout` = false)
 *   3) Popup / Drawer / Menu / Dialog **自身**写了 y:/x:/position: 声明式绑定
 *      → 绑定优先级压过开合动画, open()/close() 只改数值、卡片纹丝不动
 *      只查块内深度 1 (对象级属性), 子项自己的 y: 不算.
 *
 * 用法: <node> typed_member_check.js [<项目根=app 目录>]
 * 退出码: 0 干净 / 1 有命中 / 2 门禁自己没跑成 (防静默绿)
 */
'use strict';
const fs = require('fs');
const path = require('path');

const root = process.argv[2] || path.join(__dirname, '..', '..');
const qmlDir = path.join(root, 'qml');
if (!fs.existsSync(qmlDir)) {
    console.error('找不到 ' + qmlDir + ' —— 门禁没跑, 不是"没问题"');
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
const files = walk(qmlDir, []);
if (files.length < 40) {
    console.error('只扫到 ' + files.length + ' 个 .qml, 根目录给错了, 拒绝出结论');
    process.exit(2);
}

/** 返回 [{start, end, bodyStart}] —— end 是闭合 "}" 的下标; 找不到闭合就截到文件尾 */
function blockRanges(src, typeRe) {
    const out = [];
    for (const m of src.matchAll(typeRe)) {
        let i = m.index + m[0].length - 1;   // 指向开 "{"
        let depth = 0;
        for (; i < src.length; i++) {
            const c = src[i];
            if (c === '{') depth++;
            else if (c === '}') { depth--; if (depth === 0) break; }
        }
        out.push({ start: m.index, end: Math.min(i, src.length - 1), bodyStart: m.index + m[0].length });
    }
    return out;
}

/** 块内深度 1 的属性行 (逐行累加花括号净增减, 起始深度 0 = 块本身) */
function depthOneLines(src, range) {
    const lines = [];
    let depth = 0;
    for (const raw of src.slice(range.bodyStart, range.end).split('\n')) {
        const line = raw.trim();
        if (depth === 0 && line) lines.push(line);
        for (const c of raw) { if (c === '{') depth++; else if (c === '}') depth--; }
        if (depth < 0) depth = 0;
    }
    return lines;
}

/** 块内深度 1 的 id: 值 */
function blockIds(src, range) {
    return depthOneLines(src, range)
        .filter(l => /^id\s*:/.test(l))
        .map(l => l.replace(/^id\s*:\s*/, '').replace(/[^A-Za-z0-9_]/g, ''));
}

const MEMBER_RULES = [
    { type: 'HoverHandler', member: 'containsMouse',
      fix: 'HoverHandler 没有 containsMouse (那是 MouseArea 的) → 用 hovered' },
    { type: 'StackLayout', member: 'currentItem',
      fix: 'Qt 6.7 StackLayout 没有 currentItem (那是 StackView 的) → 按 currentIndex 从 id 表取' },
];
const POPUP_TYPES = /(?:^|[^.\w])(Popup|Drawer|Menu|Dialog)\s*\{/g;
const POPUP_BANNED = /^y\s*:|^x\s*:|^position\s*:/;

const hits = [];
let idsSeen = 0;
for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    const rel = path.relative(root, f).split(path.sep).join('/');
    const lineOf = idx => src.slice(0, idx).split('\n').length;
    const lineText = n => src.split('\n')[n - 1].trim();

    // 1+2) 具名 Qt 类型上的不存在的成员
    for (const rule of MEMBER_RULES) {
        for (const range of blockRanges(src, new RegExp('(?:^|[^.\\w])' + rule.type + '\\s*\\{', 'g'))) {
            for (const id of blockIds(src, range)) {
                idsSeen++;
                const re = new RegExp('(?:^|[^.\\w])' + id + '\\.\\s*' + rule.member + '\\b', 'g');
                for (const m of src.matchAll(re)) {
                    const n = lineOf(m.index);
                    hits.push(rel + ':' + n + '  ' + lineText(n) + '   → ' + rule.fix);
                }
            }
        }
    }

    // 3) 弹层自身的位置绑定
    for (const range of blockRanges(src, POPUP_TYPES)) {
        for (const line of depthOneLines(src, range)) {
            if (POPUP_BANNED.test(line)) hits.push(rel + '  [' + line + ']   → 弹层自身不许写位置绑定 (压过开合动画), 默认展开用 Component.onCompleted 调 open()');
        }
    }
}

console.log('扫描 ' + files.length + ' 个 .qml; 具名块 ' + idsSeen + ' 个; 命中 ' + hits.length + ' 处');
if (hits.length) {
    for (const h of hits) console.log('  · ' + h);
    process.exit(1);
}
