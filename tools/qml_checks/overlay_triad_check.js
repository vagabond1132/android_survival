// L8 门禁: 浮层三件套 —— 遮罩 + 标题 + 看得见的关闭途径 (2026-11-03 #37, 真机 pass 2 F6)
// 现场: 图层面板 (MapPage baseMapMenu) 无标题、无遮罩、无退路, 除了选一项只能靠系统返回;
//       省份/月份下拉同样缺遮罩与标题。而 EmergencyContactsPage 与 Main.qml 的搜索 Dialog
//       三样齐全, 且真机实测「点遮罩可关、不漏到底层」(p2h) —— 定律可达, 只是别处没用。
// 判据 (只看块内 depth==1 的声明, 子项自己写的同名属性不算这一层):
//   Dialog / Popup : modal: true (Qt6 默认 false = 能点穿); 标题 = title 非空, 或 contentItem
//                    里自带加粗首行 (EquipmentPage 三个对话框是后者, 不重复要求 title);
//                    关闭途径 = standardButtons 里有任一会关掉它的标准按钮 (Ok/Cancel/Yes/No/
//                    Discard/Apply/Reject/Close)、或 footer、或块内有 accept()/reject()/close()。
//                    `Dialog.NoButton` (自画 footer 的写法) 不算退路。
//   Menu           : dim: true (Qt6 默认 false) + 一句**画得出来**的标题 (首行加粗 MenuItem,
//                    或 depth-1 title) + 块内一个真的 close()。
//                    ⚠️ 2026-11-03 返工: 本判据的第一版把"标题或关闭项(header/footer)"当成 Menu
//                    的合规形状, 于是照它补出来的 `Menu { footer: ItemDelegate {...} }` 让
//                    qml_lint 全树 0 Error、本门禁 rc=0, 而真机是**开局白屏** —— Qt6 的 Menu 是
//                    Popup 派生, 没有 header/footer (那对属性属于 Pane 家族: Dialog / Page /
//                    ScrollView / ApplicationWindow), 写上是加载期硬错
//                    "Cannot assign to non-existent property", 整页编译不过。这条错只有
//                    qml_load_check 抓得到, 所以门禁必须自己不许把浮层往那个形状上引。
//   Drawer         : modal 默认已是 true, 只查标题 —— 它和 Menu 一样是 Popup 派生, 标题只能画在
//                    内容里: 认块内任意一层的 header 且那里真有一句 text: "…" (Main.qml 抽屉那句
//                    挂在 ListView.header), 但 **depth-1 的 header/footer 一律算命中** (见上面那条)。
//   Popup 派生三兄弟 (Menu / Popup / Drawer) 还各禁写 depth-1 的 standardButtons (Dialog 的属性),
//   全树禁 `MenuContent {` —— 6.7.2 的安装树里 grep 不到这个类型 (Controls 与 Templates 的
//   plugins.qmltypes 各 0 次), 裸 qml 二进制实测报 "MenuContent is not a type"。
// 不覆盖 (静态判不出, 靠真机): ComboBox 的 popup 是 Loader.sourceComponent, 不是字面块,
// 所以省份/月份那两个浮层不在面上 —— pass 2 实测它们缺遮罩缺标题, 由 FilterRow 那侧改。
// FileDialog 不查: 遮罩与按钮由系统给, QML 侧写了也不生效。
// 已知盲区 (只影响 Drawer 一侧, 今天没有现场): Drawer 认的"挂在内容里的标题"要求 `header:`
// 与 `text: "…"` 都在行首 (Main.qml 就是这形状); 若有人写成 `ListView { header: Text { text: "…" } }`
// 一行式, 本判据会误报"缺标题"。Menu 那侧已经改成允许 `{`/`;` 后同行 (fixture 逼出来的)。
// exit 0 干净 / 1 命中 / 2 门禁没跑起来。
const fs = require('fs'), path = require('path');
const QML = process.argv[2] || path.resolve(__dirname, '../../qml');
if (!fs.existsSync(QML)) { console.error('找不到 qml 目录: ' + QML); process.exit(2); }

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
function blockRange(raw, braceOpen) {
    let d = 0;
    for (let i = braceOpen; i < raw.length; i++) {
        if (raw[i] === '{') d++;
        else if (raw[i] === '}') { d--; if (d === 0) return [braceOpen, i]; }
    }
    return [braceOpen, raw.length - 1];
}
// 块内 depth==1 的属性表 (只用正则字面量: new RegExp 拼 \s 会被字符串转义吃掉, 见
// state_truth_check.js 里那条坑的记录 —— 静默漏检比不写门禁更危险)
function shallowProps(body) {
    const out = {};
    let depth = 0;
    for (const line of body.split('\n')) {
        const m = line.match(/^[ \t]*([A-Za-z][\w.]*)[ \t]*:[ \t]*(.*)$/);
        if (m && depth === 1 && out[m[1]] === undefined) out[m[1]] = m[2].trim();
        for (const c of line) { if (c === '{') depth++; else if (c === '}') depth--; }
    }
    return out;
}

const hits = [];
const files = walk(QML, []);
let overlays = 0;
for (const f of files) {
    const rel = path.relative(QML, f);
    const raw = stripComments(fs.readFileSync(f, 'utf8'));
    // 全树禁 MenuContent: 6.7.2 这套安装里没有这个类型 (Controls 与 Templates 的
    //   plugins.qmltypes 各 grep 到 0 次), 裸 qml 实测报 "MenuContent is not a type",
    //   和 header/footer 一样是整页编译不过。菜单要补标题/出口就走首尾两行 MenuItem。
    for (const mc of raw.matchAll(/\bMenuContent[ \t]*\{/g)) {
        hits.push([rel, lineOf(raw, mc.index), 'MenuContent',
                   'MenuContent 不是这套 Qt 里的类型 (加载期硬错) —— 标题与出口做成首尾两行 MenuItem']);
    }
    for (const m of raw.matchAll(/\b(Dialog|Popup|Menu|Drawer)\s*\{/g)) {
        if (/(File)\s*$/.test(raw.slice(Math.max(0, m.index - 12), m.index))) continue;
        const [a, b] = blockRange(raw, raw.indexOf('{', m.index));
        const body = raw.slice(a, b + 1);
        const props = shallowProps(body);
        overlays++;
        const miss = [];
        if (m[1] === 'Dialog') {
            if (props.modal !== 'true') miss.push('遮罩(modal: true)');
            const t = props.title;
            const selfDrawn = /font\.bold[ \t]*:[ \t]*true/.test(body);
            if ((t === undefined || /^(""|'')$/.test(t)) && !selfDrawn) miss.push('标题(title, 或 contentItem 自带加粗首行)');
            const sb = props.standardButtons || props.buttons || '';
            // Ok|Cancel / Yes|No / Close 也算退路 —— 只认 Reject 会把合规的 Dialog.Ok|Dialog.Cancel
            //   报成缺陷 (假阳性也是漏检的一种)。`\b` 是这里的关键: "Dialog.NoButton" (自画
            //   footer 的那种写法) 不能被读成 "No", 否则一枚没有任何按钮的浮层会假过。
            const hasClose = /\.\w*(Ok|Cancel|Discard|Apply|Yes|No|Reject|Close)\b/.test(sb)
                             || props.footer !== undefined
                             || /accept\s*\(\s*\)|reject\s*\(\s*\)|close\s*\(\s*\)/.test(body);
            if (!hasClose) miss.push('关闭途径(standardButtons 含 Reject / footer / accept·reject·close())');
        } else if (m[1] === 'Popup') {
            // Popup 本身就是那一族 (Menu / Drawer 都从它派生): header/footer/standardButtons
            //   一个都没有, 标题与按钮只能画进内容里。全树今天 0 个裸 Popup 块, 这条是给将来定的。
            const chrome = ['header', 'footer', 'standardButtons'].filter((k) => props[k] !== undefined);
            if (chrome.length) miss.push('Popup 没有 ' + chrome.join('/')
                + ' (写上是加载期硬错) —— 标题与按钮画进内容里');
            if (props.modal !== 'true') miss.push('遮罩(modal: true)');
            if (!/font\.bold[ \t]*:[ \t]*true/.test(body)) miss.push('标题(contentItem 自带加粗首行)');
            if (!/\bclose\s*\(\s*\)/.test(body)) miss.push('关闭途径(块内一句 close())');
        } else if (m[1] === 'Menu') {
            // Popup 派生: header/footer/standardButtons 写了不是警告, 是加载期硬错 (见文件头)。
            const chrome = [];
            if (props.header !== undefined) chrome.push('header');
            if (props.footer !== undefined) chrome.push('footer');
            if (props.standardButtons !== undefined) chrome.push('standardButtons');
            if (chrome.length) {
                miss.push('Menu 没有 ' + chrome.join('/') + ' (Popup 派生, 写上是加载期硬错 → 整页编译不过, '
                    + '真机白屏) —— 标题与出口要做成首尾两行 MenuItem');
            } else {
                if (props.dim !== 'true') miss.push('遮罩(dim: true)');
                // 标题得是**画得出来**的一句: Material 的非原生菜单不画 Menu.title,
                // 所以认 depth-1 加粗文案行 (baseMapMenu 的第一行 MenuItem contentItem Text)。
                const drawnTitle = /font\.bold[ \t]*:[ \t]*true/.test(body)
                                   && /(?:^|[{;])[ \t\n]*text[ \t]*:[ \t]*"[^"]+"/.test(body);
                if (!drawnTitle) miss.push('标题(一句加粗的 text, Material 不画 Menu.title)');
                if (!/\bclose\s*\(\s*\)/.test(body)) miss.push('关闭途径(块内一句 close())');
            }
        } else if (m[1] === 'Drawer') {
            if (props.header !== undefined || props.footer !== undefined
                || props.standardButtons !== undefined) {
                miss.push('Drawer 没有 header/footer/standardButtons (Popup 派生, 写上是加载期硬错) '
                    + '—— 标题挂在内容里的 ListView.header 上');
            } else {
                // Qt 6.7 的 Drawer 没有 title / header 属性 (那是 Dialog 的), 标题只能画在内容里:
                //   认块内任意一层的 `header:` (Main.qml 抽屉那句挂在 ListView.header 上),
                //   但那里必须真有一句画得出来的文字, 光有 header 块不算。
                const nested = /(^|\n)[ \t]*header[ \t]*:/.test(body)
                               && /(^|\n)[ \t]*text[ \t]*:[ \t]*"[^"]+"/.test(body);
                if (props.header === undefined && !(props.title && !/^(""|'')$/.test(props.title)) && !nested)
                    miss.push('标题(title/header)');
            }
        }
        if (miss.length) hits.push([rel, lineOf(raw, m.index), m[1], miss.join(' + ')]);
    }
}
console.log('=== L8 浮层三件套: 扫 ' + files.length + ' 个 .qml, 浮层 ' + overlays + ' 个, 缺件 ' + hits.length + ' 处 ===');
for (const [f, l, kind, miss] of hits) console.log('  ' + f + ':' + l + '  ' + kind + '  缺 → ' + miss);
process.exit(hits.length ? 1 : 0);
