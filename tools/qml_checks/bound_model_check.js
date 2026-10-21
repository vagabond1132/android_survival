// Bound 语义自检: 加了 `pragma ComponentBehavior: Bound` 的文件里, delegate 不再能看见
// 视图注入的 model / index / modelData 上下文属性 —— 必须改成 `required property`。
// 这是真机实测出来的: Main.qml 抽屉 13 行全部 "ReferenceError: model is not defined",
// qmllint / qmlcachegen / ctest 全都不报, 只有装上手机才看得见 (行是空白的)。
//
// 判读: 期望 0 条。非 0 = 该 delegate 在真机上会静默画空。
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');

// 上下文属性名: 只有出现在 delegate 对象块里才算引用 (视图注入的那三个)
const CTX = ['model', 'index', 'modelData'];

function walk(d, out) {
    if (!fs.existsSync(d)) return out;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.qml')) out.push(p);
    }
    return out;
}
function strip(t) {
    // 注释换成等量空白, **保留换行** —— 否则行号会整体前移, 报出来的位置对不上文件。
    return t.replace(/\/\*[\s\S]*?\*\//g, m => m.replace(/[^\n]/g, ' '))
            .replace(/\/\/[^\n]*/g, m => ' '.repeat(m.length));
}
// 返回 [start,end) —— text 里 pos 处那个 '{' 配对的块
function blockEnd(text, open) {
    let depth = 0;
    for (let i = open; i < text.length; ++i) {
        if (text[i] === '{') depth++;
        else if (text[i] === '}') { if (--depth === 0) return i; }
    }
    return text.length;
}
// 去掉字符串字面量, 免得 "model" 这种文案被当成引用。同样保持长度不变 (不移动行号)。
function dropStrings(t) {
    return t.replace(/'(\\.|[^'\\])*'|"(\\.|[^"\\])*"/g, m => ' '.repeat(m.length));
}
// 在块内找裸上下文属性引用: 前面不能跟 '.' , 后面跟 '.' (model.x) 或作为独立词 (index)
function ctxRefs(text, from, to) {
    const seg = dropStrings(text.slice(from, to));
    const hits = [];
    for (const c of CTX) {
        const re = new RegExp('(^|[^\\w.$])' + c + '\\b', 'g');
        let m;
        while ((m = re.exec(seg))) {
            // `model:` / `index:` 这种是属性赋值键, 不是引用
            if (/^\s*:/.test(seg.slice(m.index + m[0].length))) continue;
            hits.push(c);
        }
    }
    return [...new Set(hits)];
}

const hits = [];
for (const f of walk(ROOT, [])) {
    const raw = fs.readFileSync(f, 'utf8');
    // 允许行首缩进: pragma 规范上写在文件顶层 (本仓 38 个文件都是 0 缩进),
    // 但门禁要是因为多两个空格就整file跳过, 就成了静默漏检 —— 宁可放宽匹配。
    if (!/^\s*pragma\s+ComponentBehavior\s*:\s*Bound/m.test(raw)) continue;
    const t = strip(raw);
    for (const m of t.matchAll(/\bdelegate\s*:/g)) {
        const open = t.indexOf('{', m.index);
        if (open < 0) continue;
        const end = blockEnd(t, open);
        const inner = t.slice(open, end);
        const declared = new Set();
        for (const d of inner.matchAll(/required\s+property\s+\S+\s+(\w+)/g)) declared.add(d[1]);
        // 注意: 扫的是整个 delegate 块, 嵌套 delegate 会被外层重复算一次 ——
        // 宁可多报让人去核对, 也不漏报 (漏报的代价是真机上一整片空白行)。
        const used = ctxRefs(t, open, end);
        const bad = used.filter(c => !declared.has(c));
        if (bad.length) {
            hits.push([path.relative(ROOT, f), raw.slice(0, m.index).split('\n').length, bad.join(',')]);
        }
    }
}
console.log('=== Bound 文件里 delegate 用了未声明的 model/index/modelData: ' + hits.length + ' 处 ===');
for (const [f, l, b] of hits) console.log(f + ':' + l + '  需要 required property -> ' + b);
process.exit(hits.length ? 1 : 0);
