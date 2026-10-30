// delegate 外层 id 引用 / Bound pragma 自检
// 规则: delegate 里读了"在外层声明的 id"(styles / root / 页面 id / list …),
//       在 qmlcachegen 静态编译下必须有 pragma ComponentBehavior: Bound,
//       否则真机静默 ReferenceError (2026-10-19 一批同类 bug).
// 只做启发式定位, 命中的文件人工确认.
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');

function strip(t) {
    return t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}
function walk(d, out) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.qml')) out.push(p);
    }
    return out;
}
// 从 idx 开始找到与之配对的 '{' 并返回其内容结束位置
function blockEnd(text, braceOpen) {
    let depth = 0;
    for (let i = braceOpen; i < text.length; ++i) {
        if (text[i] === '{') depth++;
        else if (text[i] === '}') { depth--; if (depth === 0) return i; }
    }
    return text.length;
}

const hits = [];
for (const f of walk(ROOT, [])) {
    const raw = strip(fs.readFileSync(f, 'utf8'));
    if (/pragma\s+ComponentBehavior\s*:\s*Bound/.test(raw)) continue;
    const outerIds = new Set();
    for (const m of raw.matchAll(/\bid\s*:\s*([A-Za-z_]\w*)/g)) outerIds.add(m[1]);
    if (outerIds.size === 0) continue;
    const bad = new Map();
    for (const m of raw.matchAll(/\bdelegate\s*:/g)) {
        const bo = raw.indexOf('{', m.index);
        if (bo < 0) continue;
        const end = blockEnd(raw, bo);
        const body = raw.slice(bo, end);
        const localIds = new Set();
        for (const x of body.matchAll(/\bid\s*:\s*([A-Za-z_]\w*)/g)) localIds.add(x[1]);
        for (const x of body.matchAll(/([A-Za-z_]\w*)\s*\./g)) {
            const id = x[1];
            if (localIds.has(id)) continue;
            if (outerIds.has(id)) {
                const line = raw.slice(0, bo + x.index).split('\n').length;
                if (!bad.has(id)) bad.set(id, line);
            }
        }
    }
    if (bad.size) hits.push([path.relative(ROOT, f), [...bad.entries()]]);
}
console.log('=== delegate 里引用外层 id 但缺 Bound pragma: ' + hits.length + ' 个 ===');
for (const [f, ids] of hits) console.log(f + '  →  ' + ids.map(([i, l]) => i + '@~' + l).join(', '));
process.exit(hits.length ? 1 : 0);
