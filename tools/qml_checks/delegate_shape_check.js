// head/item 混合列表的行字段自检 (2026-10-22 巡检 H1)
// 背景: 这类页的 delegate 是一个 Item 里两个 RowLayout, 靠
//       `visible: modelData.kind === "head"` 分支. 但 visible=false 不阻止绑定求值,
//       所以只要 head 行缺 item 行的字段 (或反过来), 真机就一路刷
//       "Unable to assign [undefined] to QString/QColor/int" —— 三个页一次就是 206 条.
// 判据: 只查 delegate 里真的读了 `modelData.X` 的键; 两边字段必须都有.
// 用法: node tools/qml_checks/delegate_shape_check.js [qml目录]
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');

function walk(d, out) {
    if (!fs.existsSync(d)) return out;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.qml')) out.push(p);
    }
    return out;
}
// 从 pos 往回找与之配对的 '{'
function objStart(text, pos) {
    let depth = 0;
    for (let i = pos; i >= 0; --i) {
        const c = text[i];
        if (c === '}') depth++;
        else if (c === '{') { if (depth === 0) return i; depth--; }
    }
    return -1;
}
function objEnd(text, open) {
    let depth = 0;
    for (let i = open; i < text.length; ++i) {
        const c = text[i];
        if (c === '{') depth++;
        else if (c === '}') { depth--; if (depth === 0) return i; }
    }
    return -1;
}
// 对象字面量 depth==1 的键
function keysOf(text, open, close) {
    const out = [];
    let depth = 0;
    for (let i = open; i <= close; ++i) {
        const c = text[i];
        if (c === '{' || c === '[' || c === '(') { depth++; continue; }
        if (c === '}' || c === ']' || c === ')') { depth--; continue; }
        if (depth !== 1) continue;
        if (/[A-Za-z_]/.test(c) && /^\s*[A-Za-z_][A-Za-z0-9_]*\s*:/.test(text.slice(i, i + 80)))
            out.push(/([A-Za-z_][A-Za-z0-9_]*)/.exec(text.slice(i, i + 80))[1]);
    }
    return out;
}
function strip(t) {   // 去注释, 免得注释里的 kind:"head" / modelData.x 被算进去
    return t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}
// 只看混合行那个 delegate: 一页往往还有别的 Repeater (读数格之类),
// 它们的 modelData.X 与本缺陷无关.
function branchBlocks(text) {
    const out = [];
    for (const m of text.matchAll(/modelData\.kind\s*===\s*"[a-z]+"/g)) {
        const open = objStart(text, m.index);
        if (open < 0) continue;
        const close = objEnd(text, open);
        out.push(text.slice(open, close < 0 ? text.length : close + 1));
    }
    return out;
}

const hits = [];
for (const f of walk(ROOT, [])) {
    const raw = strip(fs.readFileSync(f, 'utf8'));
    if (!/kind:\s*"head"/.test(raw)) continue;
    // 另一支的名字各页不同: item / entry / knot —— 除 "head" 之外的都算条目行.
    const side = { head: new Set(), item: new Set() };
    for (const m of raw.matchAll(/kind:\s*"([a-z]+)"/g)) {
        const open = objStart(raw, m.index);
        if (open < 0) continue;
        const bucket = side[m[1] === 'head' ? 'head' : 'item'];
        for (const k of keysOf(raw, open, objEnd(raw, open))) bucket.add(k);
    }
    const read = new Set();
    for (const block of branchBlocks(raw))
        for (const m of block.matchAll(/modelData\.([A-Za-z_][A-Za-z0-9_]*)/g)) read.add(m[1]);
    const miss = { head: [], item: [] };
    for (const k of read) {
        if (!side.head.has(k) && side.item.size) miss.head.push(k);
        if (!side.item.has(k) && side.head.size) miss.item.push(k);
    }
    if (miss.head.length || miss.item.length) {
        hits.push([path.relative(ROOT, f), miss]);
    }
}
console.log('=== head/item 行字段不齐 (delegate 读了却缺一边): ' + hits.length + ' 个文件 ===');
for (const [f, m] of hits) {
    console.log(f);
    if (m.head.length) console.log('    head 行缺: ' + m.head.join(', '));
    if (m.item.length) console.log('    item 行缺: ' + m.item.join(', '));
}
process.exit(hits.length ? 1 : 0);
