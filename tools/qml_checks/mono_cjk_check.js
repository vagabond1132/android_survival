// monoFont 混汉字自检 (styles.monoFont 只装拉丁/数字, 汉字走它会字形回退失败出方框)
// 规则: 找到把 font.family 绑成 monoFont 的那个对象块, 只看该块的"浅层"属性
//       (depth==1), 因为深层是子对象, 子对象自己没绑 monoFont 就没问题.
// 命中 = 同一对象里既有 monoFont 又给了带汉字的 text. 人工确认后再改.
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');
const HAN = /[㐀-䶿一-鿿豈-﫿　-〿＀-￯]/;   // 汉字 + CJK 标点 + 全角

function strip(t) {
    return t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}
function walk(d, out) {
    if (!fs.existsSync(d)) return out;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.qml')) out.push(p);
    }
    return out;
}
// 从 pos 往回找到与之配对的 '{' (即 pos 所在的最近一层对象块的起点)
function enclosingBrace(text, pos) {
    let depth = 0;
    for (let i = pos; i >= 0; --i) {
        if (text[i] === '}') depth++;
        else if (text[i] === '{') { if (depth === 0) return i; depth--; }
    }
    return -1;
}
// 列出对象块内 depth==1 的 `text:` 赋值 (值取到本行尾或下一个换行)
function shallowTexts(text, braceOpen) {
    const out = [];
    let depth = 0;
    for (let i = braceOpen; i < text.length; ++i) {
        const c = text[i];
        if (c === '{') { depth++; continue; }
        if (c === '}') { depth--; if (depth === 0) break; continue; }
        if (depth !== 1) continue;
        if (c === 't' && /^text\s*:/.test(text.slice(i, i + 200))) {
            const nl = text.indexOf('\n', i);
            out.push(text.slice(i, nl < 0 ? text.length : nl));
        }
    }
    return out;
}

const hits = [];
for (const f of walk(ROOT, [])) {
    const raw = strip(fs.readFileSync(f, 'utf8'));
    for (const m of raw.matchAll(/font\.family\s*:\s*([^\n]*)/g)) {
        const fam = m[1];
        if (!/monoFont|"monospace"/.test(fam)) continue;
        const brace = enclosingBrace(raw, m.index);
        if (brace < 0) continue;
        for (const t of shallowTexts(raw, brace)) {
            if (!HAN.test(t)) continue;
            hits.push([path.relative(ROOT, f),
                       raw.slice(0, brace).split('\n').length,
                       t.trim().slice(0, 90)]);
        }
    }
}
console.log('=== monoFont 对象里 text 含汉字: ' + hits.length + ' 处 ===');
for (const [f, l, t] of hits) console.log(f + ':' + l + '  ' + t);
process.exit(hits.length ? 1 : 0);
