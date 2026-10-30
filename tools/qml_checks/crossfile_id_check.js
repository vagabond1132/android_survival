// 跨文件 id 引用自检 (2026-10-20 加局部作用域识别)
// QML 的 id 只在本文件 (组件) 内可见. 在 A.qml 里写 bPage.foo —— 而 bPage 是 B.qml 的 id
// —— 恒为 undefined, 绑定一求值就 ReferenceError, 而且是静默的 (release 包 logcat 全空).
// 2026-10-16 已经用这个模式修过 mapPage.currentLat; 这里全站再扫一遍.
//
// 上一版只会认 `id:`, 于是把 property / var / 函数形参 全当成"别人的 id",
// 35 条里约 30 条是 it / s / items / src 这类局部名 —— 噪音大到能埋掉真问题.
// 这一版先把本文件里所有能起名的位置收齐, 再判定"这个名字本文件到底有没有".
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');
const GLOBAL = new Set(['Qt', 'CommonOptions', 'App', 'ImageColorExtractor', 'Math', 'JSON',
    'Date', 'console', 'ApplicationWindow', 'matrix4x4', 'quaternion4x4',
    'vector2d', 'vector3d', 'vector4d', 'color', 'real', 'int', 'string', 'var', 'url']);

// 注释与字符串里的 id 是噪音; 但换行要原样留着, 否则报出来的行号会整体上跳.
function strip(t) {
    const blank = m => m.replace(/[^\n]/g, ' ')
    return t.replace(/\/\*[\s\S]*?\*\//g, blank)
            .replace(/\/\/[^\n]*/g, '')
            .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
            .replace(/'(?:[^'\\\n]|\\.)*'/g, "''")
}
function walk(d, out) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.qml')) out.push(p);
    }
    return out;
}

// 本文件里所有"自己起的名": QML id / property / var / 函数与信号与 lambda 的形参
function localNames(t) {
    const s = new Set();
    for (const m of t.matchAll(/\bid\s*:\s*([A-Za-z_]\w*)/g)) s.add(m[1]);
    for (const m of t.matchAll(/\bproperty\s+(?:readonly\s+)?[A-Za-z_][\w<>?.]*\s+([A-Za-z_]\w*)/g)) s.add(m[1]);
    for (const m of t.matchAll(/\bproperty\s+([A-Za-z_]\w*)\s*:/g)) s.add(m[1]);
    for (const m of t.matchAll(/\bvar\s+([A-Za-z_]\w*)/g)) s.add(m[1]);
    // function name(a, b) / function (a, b) / signal foo(int a, string b)
    for (const m of t.matchAll(/(?:function|signal)\s*(?:[A-Za-z_]\w*)?\s*\(([^)]*)\)/g)) {
        for (const p of m[1].split(',')) {
            const bits = p.trim().split(/\s+/)
            const name = bits.length ? bits[bits.length - 1] : ''
            if (/^[A-Za-z_]\w*$/.test(name)) s.add(name)
        }
    }
    return s;
}

const files = walk(ROOT, []);
const texts = new Map();
const idOwner = new Map();      // id -> 声明它的文件 (可能多个同名 id, 记成集合)
for (const f of files) {
    const t = strip(fs.readFileSync(f, 'utf8'));
    texts.set(f, t);
    for (const m of t.matchAll(/\bid\s*:\s*([A-Za-z_]\w*)/g)) {
        if (!idOwner.has(m[1])) idOwner.set(m[1], new Set());
        idOwner.get(m[1]).add(f);
    }
}
const own = new Map();
for (const [f, t] of texts) own.set(f, localNames(t));

let n = 0;
for (const [f, t] of texts) {
    const locals = own.get(f);
    const seen = new Map();
    for (const m of t.matchAll(/(^|[^\w.])([a-z]\w*)\s*\.\s*([A-Za-z_]\w*)/g)) {
        const id = m[2];
        if (locals.has(id) || GLOBAL.has(id)) continue;
        if (!idOwner.has(id)) continue;
        if (!seen.has(id)) seen.set(id, t.slice(0, m.index).split('\n').length + '|' + m[0]);
    }
    for (const [id, line] of seen) {
        console.log(path.relative(ROOT, f) + ':' + line + '  使用了他人的 id "' + id + '" (声明于 '
            + [...idOwner.get(id)].map(p => path.basename(p)).join(',') + ')');
        n++;
    }
}
console.log('=== 跨文件 id 引用 ' + n + ' 处 ===');
process.exit(n ? 1 : 0);
