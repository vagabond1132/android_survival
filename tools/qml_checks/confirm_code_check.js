// L16 门禁: 确认框的档位与「不可撤」附注必须互相咬合 (2026-11-05 #58 / 真机 0.0.9 #43 轮)
//
// 为什么查这个: DialogFooter 的 confirmCode 默认值是 `kind === "danger" ? "不可撤" : ""`,
// 也就是说"这颗键是不是不可撤"本来只有一个来源 (kind)。真机 0.0.9 走查抓到两处把它写反:
// 擦屏上画线的「清空」(重新点一行就回来) 标了「不可撤」, 而真删存储的那颗反而没标 ——
// 用户按屏幕上那句话决定要不要点, 写反一次就是"骗人按删除"。同一族的错还会这样进来:
// 某处不写 kind 吃默认 danger (于是所有普通确认都长了红口), 或 kind 拼成一个不存在的档位
// (三档以外的值在这套色口图例里落到 plain 分支, 危险动作显示成普通动作)。
//
// 判据 (四条, 全在 footer: DialogFooter { } 这一族上):
//   C1 每处必须显式写 kind —— 默认值兜住的档位在源码里看不见, 改默认就会悄悄失守。
//   C2 kind 的值必须是 danger / primary / plain 三个字面量之一 (不接受变量或三元: 档位是写死的口径)。
//   C3 非 danger 档不许写非空 confirmCode —— 屏上出现「不可撤」就等于宣布删存储。
//   C4 danger 档不许把 confirmCode 写成空串 —— 真删存储却不标, 是 C3 的镜像。
//   confirmCode 只接受字面量; 写成表达式 (含三元) 判不出来, 一律命中。
//
// 单点判据: DialogFooter.qml 的默认 kind 必须仍是 "danger"。默认翻了意味着现存每一处显式
//   kind 的语义对照都换了 (C1 的理由来自这个默认), 本门禁必须停下来让人重新对齐口径, 判 exit 2。
//
// exit 0 干净 / 1 命中 / 2 门禁没跑起来 (qml 目录、DialogFooter.qml 或 0 个使用点)。绝不静默 0 条。
const fs = require('fs'), path = require('path');
const ARGS = process.argv.slice(2);
const VERBOSE = ARGS.includes('--verbose');
const ROOT = path.resolve(__dirname, '../..');
const QML = ARGS.find((a) => !a.startsWith('--')) || path.resolve(ROOT, 'qml');
const FOOTER = path.join(QML, 'components', 'base', 'DialogFooter.qml');

function die2(msg) { console.error('!! ' + msg + ' —— 门禁没有真正运行, 判 exit 2'); process.exit(2); }
if (!fs.existsSync(QML)) die2('找不到 qml 目录 ' + QML);
if (!fs.existsSync(FOOTER)) die2('找不到 DialogFooter.qml —— 档位的单点定义没了, 本门禁无从判起');

function stripComments(t) {
    return t.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
            .replace(/\/\/[^\n]*/g, (m) => ' '.repeat(m.length));
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
const lineOf = (s, i) => s.slice(0, i).split('\n').length;
function blockRange(raw, open) {
    let depth = 0;
    for (let i = open; i < raw.length; i++) {
        if (raw[i] === '{') depth++;
        else if (raw[i] === '}') { depth--; if (depth === 0) return [open, i]; }
    }
    return [open, raw.length - 1];
}
const relDepth = (block, idx) => {
    let d = 0;
    for (let i = 0; i < idx; i++) { const c = block[i]; if (c === '{') d++; else if (c === '}') d--; }
    return d;
};
// 块"自己"的属性值 (深度 1, 第一个) —— 深度 1 是关键: DialogFooter 里嵌的按钮子块也能写
//   confirmCode, 那不是这一处使用点的档位。
function ownPropVal(block, name) {
    const re = new RegExp('(^|[^A-Za-z0-9_.])' + name.replace(/\./g, '[ \\t]*\\.[ \\t]*')
        + '[ \\t]*:[ \\t]*([^;\\n]*)', 'g');
    for (let m; (m = re.exec(block));) if (relDepth(block, m.index + m[1].length) === 1) return m[2].replace(/[ \t]+$/, '');
    return null;
}
// 只认双引号字面量, 返回 null 表示"不是字面量"
function literal(s) {
    if (s === null) return null;
    const m = /^"([^"]*)"$/.exec(s.trim());
    return m ? m[1] : null;
}

// ===== 单点: DialogFooter 的默认档位仍是 danger =====
const footRaw = stripComments(fs.readFileSync(FOOTER, 'utf8'));
const defKind = literal(ownPropVal(footRaw, 'kind'));
if (defKind === null) die2('读不到 DialogFooter.qml 的默认 kind (改成表达式了? 档位的单点定义变了, 需人工重对齐)');
if (defKind !== 'danger') die2('DialogFooter 默认 kind 现在是 "' + defKind + '" —— C1「不许吃默认值」的理由建立在这个默认是 danger 上, 默认翻了要人重新对齐全树');

const KINDS = { danger: 1, primary: 1, plain: 1 };
const hits = [];
let sites = 0, scanned = 0;

for (const f of walk(QML, []).sort()) {
    if (path.resolve(f) === path.resolve(FOOTER)) continue;
    let raw;
    try { raw = stripComments(fs.readFileSync(f, 'utf8')); }
    catch (e) { die2('读不了 ' + f + ': ' + e.message); }
    scanned++;
    for (const m of raw.matchAll(/(^|[^A-Za-z0-9_.])footer[ \t]*:[ \t]*DialogFooter[ \t]*\{/g)) {
        const open = m.index + m[0].length - 1;
        const [a, b] = blockRange(raw, open);
        const block = raw.slice(a, b + 1);
        sites++;
        const where = { f, line: lineOf(raw, open) };
        const push = (why) => hits.push(Object.assign({ why }, where));

        const kindStr = ownPropVal(block, 'kind');
        const kind = literal(kindStr);
        if (kindStr === null) {
            push('没写 kind —— 吃了 DialogFooter 的默认 danger; 档位在源码里看不见, 改默认就全体失守');
        } else if (kind === null || !KINDS[kind]) {
            push('kind 写的不是三档字面量之一 (`' + kindStr.trim() + '`) —— 三档以外的值会落进 plain 分支, 危险动作显示成普通动作');
        }
        const codeStr = ownPropVal(block, 'confirmCode');
        if (codeStr !== null) {
            const code = literal(codeStr);
            if (code === null) {
                push('confirmCode 是表达式 (`' + codeStr.trim() + '`) —— 附注必须由 kind 单点决定, 这里写三元就等于绕过档位');
            } else if (kind === 'danger' && code === '') {
                push('危险档把 confirmCode 写成空串 —— 真删存储却不标「不可撤」, 与 C3 是同一枚硬币的反面');
            } else if (kind !== null && kind !== 'danger' && code !== '') {
                push('非危险档 (`' + kind + '`) 却写了确认附注 `' + code + '` —— 屏上这句话是在宣布删存储, 与档位对不上');
            }
        }
        if (VERBOSE) console.log('  site @ ' + path.relative(ROOT, f) + ':' + where.line
            + ' kind=' + (kind || '?') + ' code=' + JSON.stringify(literal(codeStr)));
    }
}

if (sites === 0) die2('全树 ' + scanned + ' 个文件里 0 处 footer: DialogFooter —— 使用点被拆了, 本门禁无从判合规');
console.log('扫描 ' + scanned + ' 个 qml 文件; DialogFooter 使用点 ' + sites + ' 处');
for (const h of hits) console.log('HIT ' + path.relative(ROOT, h.f) + ':' + h.line + ' — ' + h.why);
console.log('=== L16 确认框档位与「不可撤」附注咬合: 命中 ' + hits.length + ' 处 ===');
process.exit(hits.length ? 1 : 0);
