// L15 门禁: 弹层正文里带 wrapMode 的 Text/Label 必须有宽度约束 (2026-11-05 #58 / 真机 0.0.9)
//
// 为什么查这个: 真机 0.0.9 §四 量到「确认框正文比框还宽」—— 一句 `已选 3 项 (路线/轨迹),
// 全部清空?` 把 Dialog 撑到贴住屏幕两侧、末字被裁。原因不是字号, 是裸 Text 挂在 ColumnLayout
// 里却没写 Layout.fillWidth: ColumnLayout 给子项的宽度是 implicitWidth, 于是 wrapMode 永远
// 不触发 (宽度=整句自然宽), 撑破的是父级。这类写法静态看"代码没毛病", 只有真机才看得见,
// 所以必须有条静态判据替真机守着。
//
// 判的形状 (不是"某一句文案", 文案会变, 形状才是这条律):
//   1. 宿主只认 Dialog / Popup 的 contentItem 子树 —— Button 的 contentItem 由控件自己给宽,
//      按同一条判会把 FilterRow / 底部导航那几格全骂一遍 (假命中)。owner 取 contentItem
//      那一行所嵌套的最内层块类型。
//   2. 子树里 *自己* 带 wrapMode 的 Text/Label 块, 按最近父级类型要求宽度约束:
//      · 父级是 Column/Row/GridLayout → 要 Layout.fillWidth: true 或 Layout.preferredWidth
//      · 父级是 Column/Row/Flickable/ScrollView/Item/Rectangle/... → 要 width: 或
//        anchors.fill 或 anchors.left + anchors.right (左右都钉住才算有宽)
//   3. 反向坑也判: 非 Layout 父级里写 Layout.fillWidth 是死的 —— 附着性属性没有宿主就是零作用,
//      今天看着"设过宽度", 明天父级一改就露。
//
// 命中 exit 1 / 干净 exit 0 / 找不到 qml 目录、没有任何 Dialog contentItem、
// 或没有任何带 wrapMode 的正文块 = 门禁没有对象可判, exit 2。绝不静默 0 条。
const fs = require('fs'), path = require('path');
const ARGS = process.argv.slice(2);
const VERBOSE = ARGS.includes('--verbose');
const ROOT = path.resolve(__dirname, '../..');
const QML = ARGS.find((a) => !a.startsWith('--')) || path.resolve(ROOT, 'qml');

function die2(msg) { console.error('!! ' + msg + ' —— 门禁没有真正运行, 判 exit 2'); process.exit(2); }
if (!fs.existsSync(QML)) die2('找不到 qml 目录 ' + QML);

// 注释换成等量空白: 行号不变, 讲解这条坑的注释 (本轮 MapPage 就有一条) 不会被当成代码命中。
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
// 块"自己"的属性 (深度 1) —— 没有这条就会把整棵 Dialog 当成正文块: 外层当然什么都包含。
function ownProp(block, name) {
    const re = new RegExp('(^|[^A-Za-z0-9_.])' + name.replace(/\./g, '[ \\t]*\\.[ \\t]*')
        + '[ \\t]*:[ \\t]*([^;\\n]*)', 'g');
    for (let m; (m = re.exec(block));) if (relDepth(block, m.index + m[1].length) === 1) return m[2];
    return null;
}
// 块的直接子块 (深度 1)。类型取左括号前最后一个大写标识 —— 不能要求"行首就是 Type {",
// 因为 `delegate: ColumnLayout {` 也开块; 只认行首会把整棵 delegate 漏掉, 里面的正文判不着。
function childBlocks(raw, a, b) {
    const out = [];
    let depth = 0;
    for (let i = a; i <= b; i++) {
        const c = raw[i];
        if (c === '{') {
            if (depth === 1) {
                const head = raw.lastIndexOf('\n', i) + 1;
                const t = /([A-Z][A-Za-z0-9_.]*)[ \t]*\{$/.exec(raw.slice(head, i + 1));
                if (t) { const [oa, ob] = blockRange(raw, i); out.push({ type: t[1], a: oa, b: ob }); }
            }
            depth++;
        } else if (c === '}') depth--;
    }
    return out;
}

const LAYOUT = /^(Column|Row|Grid)Layout$/;
const WRAP_HOST = /^(Text|Label)$/;          // 只有这两种块吃 wrapMode
const POPUP_OWNER = /(?:Dialog|Popup)$/;      // 有 contentItem 且宽度是自己算的宿主

const hits = [];
let dialogs = 0, wrapTexts = 0, scanned = 0;

for (const f of walk(QML, []).sort()) {
    let raw;
    try { raw = stripComments(fs.readFileSync(f, 'utf8')); }
    catch (e) { die2('读不了 ' + f + ': ' + e.message); }
    scanned++;

    // 只认 "contentItem: Type {" 这一族 (全树唯一实际写法); 宿主 = 这一行所嵌套的最内层块类型。
    const found = [];
    for (const m of raw.matchAll(/(^|[^A-Za-z0-9_.])contentItem[ \t]*:[ \t]*([A-Z][A-Za-z0-9_.]*)[ \t]*\{/g)) {
        const at = m.index + m[1].length;
        found.push({ owner: ownerStackAt(raw, at), at, open: m.index + m[0].length - 1, type: m[2] });
    }
    for (const site of found) {
        if (!site.owner || !POPUP_OWNER.test(site.owner)) continue;
        const [a, b] = blockRange(raw, site.open);
        dialogs++;
        visit(raw, { f, owner: site.owner, rootType: site.type, a, b });
    }
}

// 反查某个偏移处的嵌套栈顶 (整文件一遍, 只在需要时调用)
function ownerStackAt(raw, idx) {
    const stack = [];
    for (let i = 0; i < idx; i++) {
        const c = raw[i];
        if (c === '{') {
            const head = raw.lastIndexOf('\n', i) + 1;
            const t = /([A-Z][A-Za-z0-9_.]*)[ \t]*\{$/.exec(raw.slice(head, i + 1));
            stack.push(t ? t[1] : null);
        } else if (c === '}') stack.pop();
    }
    for (let k = stack.length - 1; k >= 0; k--) if (stack[k]) return stack[k];
    return null;
}

function visit(raw, node) {
    // 深度 1: 子节点的本级类型 = 该子块自己的第一个子块
    for (const ch of childBlocks(raw, node.a, node.b)) {
        const block = raw.slice(ch.a, ch.b + 1);
        if (WRAP_HOST.test(ch.type)) {
            const wrap = ownProp(block, 'wrapMode');
            if (wrap !== null) {
                wrapTexts++;
                checkWrapHost(raw, node, ch, block, wrap);
            }
        }
        visit(raw, { ...node, owner: node.owner, rootType: ch.type, a: ch.a, b: ch.b });
    }
}

function checkWrapHost(raw, node, ch, block, wrap) {
    const where = { f: node.f, line: lineOf(raw, ch.a) };
    const push = (why) => hits.push(Object.assign({ why }, where));
    const parent = node.rootType;              // 正文块的最近父级
    const fillW = ownProp(block, 'Layout.fillWidth');
    const prefW = ownProp(block, 'Layout.preferredWidth');
    const width = ownProp(block, 'width');
    const aFill = ownProp(block, 'anchors.fill');
    const aLeft = ownProp(block, 'anchors.left');
    const aRight = ownProp(block, 'anchors.right');
    const hasWrapReal = wrap !== 'Text.NoWrap';

    if (LAYOUT.test(parent)) {
        if (hasWrapReal && fillW === null && prefW === null) {
            push('Dialog 正文 (' + ch.type + ', 父级 ' + parent + ') 写了 wrapMode 但没有 '
                + 'Layout.fillWidth / Layout.preferredWidth —— ColumnLayout 按自然宽给尺寸, '
                + 'wrap 永远不触发, 整句会把弹层撑破');
        }
        if (fillW !== null && !/^\s*true\b/.test(fillW)) {
            push('Dialog 正文的 Layout.fillWidth 写的是 `' + fillW.trim() + '` —— 不是 true 就等于没约束');
        }
    } else {
        const anchored = aFill !== null || (aLeft !== null && aRight !== null);
        if (hasWrapReal && width === null && !anchored) {
            push('Dialog 正文 (' + ch.type + ', 父级 ' + parent + ' 不是 Layout) 有 wrapMode 却没宽度: '
                + '要么写 width, 要么 anchors 左右都钉住 (父级是 ' + parent + ' 时 Layout.* 一律无效)');
        }
        if (fillW !== null || prefW !== null) {
            push('Dialog 正文在非 Layout 父级 (' + parent + ') 里写了 Layout.fillWidth / '
                + 'preferredWidth —— 附着性属性没有宿主就是死的, 看着设过其实零作用');
        }
    }
}

if (dialogs === 0) die2('全树 ' + scanned + ' 个文件里 0 个 Dialog/Popup 的 contentItem —— 本门禁无从判合规');
if (wrapTexts === 0) die2('Dialog 正文子树里 0 个带 wrapMode 的 Text/Label —— 本门禁无从判合规');
console.log('扫描 ' + scanned + ' 个 qml 文件; Dialog/Popup 正文 ' + dialogs + ' 处, '
    + '其中带 wrapMode 的 Text/Label ' + wrapTexts + ' 处');
for (const h of hits) console.log('HIT ' + path.relative(ROOT, h.f) + ':' + h.line + ' — ' + h.why);
console.log('=== L15 弹层正文宽度约束: 命中 ' + hits.length + ' 处 ===');
process.exit(hits.length ? 1 : 0);
