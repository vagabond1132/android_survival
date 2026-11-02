// 吸底条让位自检 (2026-10-28 A41)
// 判定口径: 从标记所在行往上回到"父块"的 `{`, 标记之前的那段父块内容里 (1) 必须有
//       滚动区 (fillHeight / anchors.fill / ScrollView / ListView / GridView / Flickable),
//       (2) 必须出现 `styles.bottomClearance` —— 也就是滚动视口要给吸底条让出一格.
//       不查"标记的上一个兄弟块": 底栏前面常夹着 EmptyState / 结果 note,
//       第一版这么查把 7 页的 EmptyState 当成了滚动区, 全是假红.
//       只看注释剥掉后的真括号, 不靠缩进往上爬 (碰到兄弟块内部任意一行属性就断在原地).
// 盖不住的: 没有写 `// --- 底栏` 标记的页 (本约定靠人守) —— 这一条从 #157 起只算旧口径,
//       新口径 (结构识别, 见下) 不再依赖注释; ListView.footer 那一类 (KnotPage /
//       FirstAidPage 的让位量在 footer 高度里, 不在兄弟块上) 仍只能靠真机逐张判。
// #157 (2026-10-28): 旧版绿得虚假的两个原因, 本轮都补上:
//   ① 扫描面只到 qml/pages 一层 (readdirSync 不递归) —— MapPageComponents/ 四个工作台
//      Tab 与整个 components/ 根本不在面上. 现改为 pages/ 与 components/ 全树递归,
//      并打印逐目录文件数: 哪天路径又栽在 MSYS 的 `/d/x` 上 (Electron 当 `D:\d\x` 看,
//      existsSync 直接 false), 扫描数当场显形; 一个文件都没扫到就 exit 2, 不给静默绿灯
//      (同款坑 README"怎么跑"里 int_prop_check 栽过, 不能再栽第三次).
//   ② 认条只认 `// --- 底栏` 注释 + `styles.bottomClearance` 字符串这两种硬编码形状,
//      而工作台的吸底条 (SheetActionBand) 一个都不写: 由各 Tab 摆在 ColumnLayout 末尾,
//      钉高写在组件自己的根块里. 现加结构判定 —— ColumnLayout/Drawer 的最后一个可见
//      直接子项, 高度钉在 styles.* 且该 token 实测 >= 44 逻辑 (数值表从 Styles.qml
//      现场解析, 不写死 token 名: 明天新条带组件只要按规矩钉 styles.<token>, 不改
//      门禁也能认) , 或它是"根块自带这种钉高"的组件实例 → 即吸底条.
//      SheetPanelHead 同为钉高行 (btnH=44) 但永远是第一个子项, 靠"最后一个可见子项"
//      排除, 不靠名字排除.
//   ③ 判让位分两类形状:
//      钉高写在本文件子项块上的 (Rectangle/Button 那一类) → 仍按 A41 最严口径, 同层
//        必须给出 bottomClearance 或 bottomMargin —— A41 真机教训 (视口折边压在条的
//        上描边上、末行切一半) 对这种形状依然成立, 不许拿"布局会挤出去"开脱.
//      钉高写在组件根块上的独立组件当布局子项 (SheetActionBand 形状) → 布局会把带的
//        高度从视口里扣掉, 判安全 (#156 设计口径: RecordTab "底部不留边距: 动作带就是
//        这一档的收边"); 一旦它 anchors.bottom 逃出布局浮在视口上而同层没让位 → 报,
//        这正是 #156 之前"抽屉常驻通栏盖住 SearchTab 末行"那一类, 改回去就是回归.
// #158 (2026-11-02): 加第三遍 —— 视口 (ScrollView/ListView/GridView/Flickable) 必须
//   `clip: true`. 0.0.5 模拟器走查看到 MePage 的「显示」段头渲染在 y 2236-2268, 落在
//   底栏带 2142..2274 里 (字叠字). Qt 的视口默认不裁剪, 超出的一截照样画; MePage /
//   HomePage / SOSPage 三个页级 ScrollView 漏了这条 (全树其余 15 处视口都有), 补上后
//   按"零例外"口径钉死.
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');
const GLOB = process.argv[3] || '';           // 可选: 只扫相对路径含这段的文件 (拿 fixture 反证用)
const MARK = /^(\s*)\/\/\s*---\s*[①-⑩]*\s*(?:固定)?\s*底栏/;      // 页内约定: `// --- 底栏 ...`
// #157: 旧锚正则 `①-⑩]*\s*底栏` 连 FieldGuideDetailPage:1521 那行 `// --- ④ 固定底栏`
// 都匹配不到 —— 锚太紧导致标记形同虚设 (A41 到 #157 之间这一处从没被标记口径查过,
// 本轮是结构遍把它捞回来的). 这正是 README 记过的第二类静默绿, 修锚 + 让 GLOB 参数
// 能拿已知命中样例反证.
const TOKEN = 'styles.bottomClearance';
const MIN_BAR_H = 44;                          // 吸底条高度下限 (touchMin 的语义)
const PIN_RE = new RegExp('(?:Layout\\.preferredHeight|implicitHeight|\\bheight)\\s*:\\s*styles\\.([A-Za-z]\\w*)', 'g');
const VIEWPORT = /Layout\.fillHeight: true|anchors\.fill: parent|\b(ScrollView|ListView|GridView|Flickable)\s*\{/;
const VIEW_TYPE = /\b(ScrollView|ListView|GridView|Flickable)\b/;

function strip(t) {
    // 保住换行 (行号不能漂), 只把注释内容掏空
    return t.replace(/\/\*[\s\S]*?\*\//g, m => m.replace(/[^\n]/g, ''))
            .replace(/\/\/[^\n]*/g, m => ' '.repeat(m.length));
}
function neutralize(t) {
    // 把 function 定义体 (事件处理器 `function onX(...) {...}` / 具名函数 / lambda)
    // 掏成不带括号的占位, 保住换行 —— 否则 directChildren 会把函数体/绑定块里的
    // `{` 当成对象子项. 反复替换到不动点 (lambda 可以套 lambda).
    let prev;
    do {
        prev = t;
        const re = /function\s*(?:[A-Za-z_]\w*)?\s*\(/g;   // 具名/匿名都掏
        let m;
        while ((m = re.exec(t)) !== null) {
            const bi = t.indexOf('{', m.index);
            if (bi < 0) break;
            const be = jsBody(t, bi);
            if (be < 0) break;
            const nl = t.slice(m.index, be + 1).replace(/[^\n]/g, '');
            t = t.slice(0, m.index) + 'FN' + nl + t.slice(be + 1);
            re.lastIndex = m.index + 2;
        }
    } while (t !== prev);
    return t;
}
function jsBody(t, i) {
    // t[i] === '{' → 返回配对 '}' 的下标
    let depth = 0;
    for (let j = i; j < t.length; ++j) {
        if (t[j] === '{') depth++;
        else if (t[j] === '}') { if (--depth === 0) return j; }
    }
    return -1;
}
function enclosingBrace(text, pos) {
    // pos 往回找到包住它的那个 `{`
    let depth = 0;
    for (let i = pos; i >= 0; --i) {
        if (text[i] === '}') depth++;
        else if (text[i] === '{') { if (depth === 0) return i; depth--; }
    }
    return -1;
}
function walk(dir, out) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.qml')) out.push(p);
    }
    return out;
}
function collect(root) {
    const st = fs.existsSync(root) ? fs.statSync(root) : null;
    if (st && st.isFile()) return [root];
    const dirs = ['pages', 'components'].map(d => path.join(root, d)).filter(d => fs.existsSync(d));
    if (!dirs.length) {
        console.error('!! 根目录 ' + root + ' 下找不到 pages/ 或 components/, 一个 .qml 都没扫到.');
        console.error('!! Windows 主机要传 `D:/x/y` 形式的路径; 传 `/d/x/y` 会被 Electron 当 `D:\\d\\x\\y` —— 这就是历史上"0 条假绿"的成因 (#157).');
        process.exit(2);
    }
    let files = [];
    for (const d of dirs) files = files.concat(walk(d, []));
    return files;
}
const FILES = collect(ROOT);
if (!FILES.length) {
    console.error('!! 根目录下 0 个 .qml, 不给静默绿灯 (#157).');
    process.exit(2);
}
const texts = FILES.map(f => {
    const raw = fs.readFileSync(f, 'utf8');
    return { f, raw, text: neutralize(strip(raw)) };
});
// GLOB (#157): 只收窄"检查"范围 (拿已知命中样例反证时用), 数据表 (Styles token /
// 组件根钉高) 仍从全量文件建 —— 否则单独扫一个 fixture 会因看不到 SheetActionBand
// 的组件定义而漏判, 又是一个"扫了等于没扫".
const CHECK = texts.filter(({ f }) => !GLOB || path.relative(ROOT, f).replace(/\\/g, '/').includes(GLOB));
if (!CHECK.length) {
    console.error('!! GLOB=' + GLOB + ' 过滤后 0 个文件, 不给静默绿灯 (#157).');
    process.exit(2);
}
function makeToLine(text) {
    const lineOff = [];
    let acc = 0;
    for (const l of text.split('\n')) { lineOff.push(acc); acc += l.length + 1; }
    return off => {
        let lo = 0, hi = lineOff.length - 1;
        while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (lineOff[mid] <= off) lo = mid; else hi = mid - 1; }
        return lo + 1;
    };
}
function typeNameAt(t, braceIdx) {
    // `{` 前紧邻的大写标识符 = 类型名; 若再往前是 `owner:` (小写属性名, 如 delegate:),
    // 记为 assignTo —— 值形态的对象不是父块的布局子项.
    let i = braceIdx - 1;
    while (i >= 0 && /\s/.test(t[i])) --i;
    const end = i + 1;
    while (i >= 0 && /[A-Za-z0-9_]/.test(t[i])) --i;
    const word = t.slice(i + 1, end);
    if (!word || !/^[A-Z]/.test(word)) return null;
    let j = i;
    while (j >= 0 && /\s/.test(t[j])) --j;
    if (t[j] !== ':') return { type: word, assignTo: '' };
    let k = j - 1;
    while (k >= 0 && /\s/.test(t[k])) --k;
    const e2 = k + 1;
    while (k >= 0 && /[A-Za-z0-9_]/.test(t[k])) --k;
    const lhs = t.slice(k + 1, e2);
    if (/^[a-z]/.test(lhs)) return { type: word, assignTo: lhs };
    return { type: word, assignTo: '' };   // `component X: RowLayout` 那种大写左名不算归属
}
function directChildren(t, open, close) {
    // t[open] === '{' 的块的深度 1 子对象 [{s,e,type,owner}] —— 从 open 之后开始数,
    // 容器自己的花括号不算层.
    const kids = [];
    let depth = 0, pend = null;
    for (let i = open + 1; i <= close; ++i) {
        const c = t[i];
        if (c === '{') {
            depth++;
            if (depth === 1) pend = { s: i, tn: typeNameAt(t, i) };
        } else if (c === '}') {
            if (depth === 1) {
                if (pend && pend.tn) kids.push({ s: pend.s, e: i, type: pend.tn.type, owner: pend.tn.assignTo });
                pend = null;
            }
            depth--;
        }
    }
    return kids;
}
function ownProps(own) {
    // 块的"自身属性"文本: 掏掉所有嵌套子对象块, 只留深度 1 的文字. 属性顺序可前可后
    // —— SheetActionBand 先摆 `Styles { id: styles; }` 实例、把 Layout.preferredHeight
    // 写在它后面, 只看"第一个子块之前"会漏钉高 (第一版就是这么数出 0 根条的).
    let out = '';
    for (let i = 1; i < own.length; ) {
        if (own[i] === '{') {
            const be = jsBody(own, i);
            if (be < 0) break;
            i = be + 1;
        } else { out += own[i]; i++; }
    }
    return out;
}

// === 数据表 1: Styles token 数值 (#157 ②, 不写死名单) ======================
const tokenDefs = {};
for (const { f, text } of texts) {
    if (path.basename(f, '.qml') !== 'Styles') continue;
    const re = /property\s+(?:real|int)\s+(\w+)\s*:\s*([^;\n]+)/g;
    let m;
    while ((m = re.exec(text)) !== null) {
        if (tokenDefs[m[1]] === undefined) tokenDefs[m[1]] = m[2].trim();
    }
}
function evalTok(name, seen) {
    if (seen.has(name)) return NaN;
    const probe = new Set(seen); probe.add(name);
    let e = tokenDefs[name];
    if (e === undefined) return NaN;
    if (/["']/.test(e)) return NaN;            // 字符串/颜色定义不是尺寸
    e = e.replace(/[A-Za-z_]\w*/g, w => {
        if (w === 'Math' || w === 'max' || w === 'min') return w;
        const v = evalTok(w, probe);
        return isFinite(v) ? '(' + v + ')' : '##';
    });
    if (e.includes('##')) return NaN;
    const test = e.replace(/Math\.(?:max|min)\(/g, '');
    if (!/^[-+*/().,\s\dA-Za-z]*$/.test(test) || /[A-Za-z]/.test(test)) return NaN;
    try { return Function('"use strict";return (' + e + ');')(); } catch (err) { return NaN; }
}
function pinOf(head) {
    // 属性头里有没有钉在 >= MIN_BAR_H 的 styles token 上的高度
    let m, hit = null;
    PIN_RE.lastIndex = 0;
    while ((m = PIN_RE.exec(head)) !== null) {
        const v = evalTok(m[1], new Set());
        if (isFinite(v) && v >= MIN_BAR_H) hit = m[1];
    }
    return hit;
}

// === 数据表 2: "根块自带钉高"的组件类型 (#157 ②) ===========================
// SheetActionBand 的实例处 Layout.fillWidth 之外什么都不写, 钉高在组件自己的根块里
// (QML 的 Layout.preferredHeight 附着在对象上, 父布局读得到) —— 实例形状在调用处
// 完全隐形, 只能先把每个组件文件的根块自身属性扫一遍建这张表.
// 键必须是**文件名 (= 组件名)**而不是根类型名: SheetActionBand 的根是个 RowLayout,
// 按 'RowLayout' 登记会把每个普通 RowLayout 都当成钉高条 (第一版就这么冤枉了
// 排序 chips 行和一堆 Rectangle). 同名冲突宁可删除也不猜.
const stickyRoots = {};
const ambiguous = new Set();
for (const { f, text } of texts) {
    const open = text.indexOf('{');
    if (open < 0) continue;
    const tn = typeNameAt(text, open);
    if (!tn || tn.assignTo || /^[a-z]/.test(tn.type)) continue;
    const close = jsBody(text, open);
    if (close < 0) continue;
    const tok = pinOf(ownProps(text.slice(open, close + 1)));
    if (!tok) continue;
    const name = path.basename(f, '.qml');
    if (stickyRoots[name] !== undefined && stickyRoots[name] !== tok) ambiguous.add(name);
    stickyRoots[name] = tok;
}
for (const n of ambiguous) delete stickyRoots[n];

// === 第一遍: 标记口径 (A41 旧逻辑, 判定一字不改) ============================
const hits = [];
let checked = 0;
const markedParents = {};   // file → 已被标记口径覆盖的容器 `{` 位置集 (结构遍不重复报)
for (const { f, raw, text } of CHECK) {
    markedParents[f] = new Set();
    const toLine = makeToLine(text);
    const lineOff = [];
    let acc = 0;
    for (const l of text.split('\n')) { lineOff.push(acc); acc += l.length + 1; }
    const rawLines = raw.split('\n');
    for (let i = 0; i < rawLines.length; ++i) {
        if (!MARK.test(rawLines[i])) continue;
        checked++;
        const pos = lineOff[i];
        const parent = enclosingBrace(text, pos);
        markedParents[f].add(parent);
        const region = parent < 0 ? '' : text.slice(parent + 1, pos);
        if (!region.trim()) {
            hits.push([path.relative(ROOT, f).replace(/\\/g, '/'), i + 1, '定位不到吸底条所在的父块, 无法判定']);
            continue;
        }
        if (!VIEWPORT.test(region)) {
            hits.push([path.relative(ROOT, f).replace(/\\/g, '/'), toLine(parent),
                       '底栏同层里没有滚动区, 让位口径无法核对 (结构变了, 要重看这一页)']);
            continue;
        }
        if (!region.includes(TOKEN)) {
            hits.push([path.relative(ROOT, f).replace(/\\/g, '/'), toLine(parent),
                       '滚动区所在层没有 ' + TOKEN + ' (末行会被吸底条切掉)']);
        }
    }
}

// === 第二遍: 结构口径 (#157 ②③) ============================================
let bars = 0;
for (const { f, text } of CHECK) {
    const toLine = makeToLine(text);
    const rel = path.relative(ROOT, f).replace(/\\/g, '/');
    const re = /\b(ColumnLayout|Drawer)\s*\{/g;
    let m;
    while ((m = re.exec(text)) !== null) {
        const open = text.indexOf('{', m.index);
        if (/component\s+[A-Z]\w*\s*:\s*$/.test(text.slice(Math.max(0, m.index - 60), m.index))) continue;
        const close = jsBody(text, open);
        if (close < 0 || markedParents[f].has(open)) continue;   // 标记口径已判过这个容器
        const kids = directChildren(text, open, close).filter(k => !k.owner);
        if (!kids.length) continue;
        const infos = kids.map(k => {
            const own = text.slice(k.s, k.e + 1);
            const head = ownProps(own);
            return {
                k, head,
                tok: pinOf(head),
                rootTok: stickyRoots[k.type] || null,
                viewport: VIEW_TYPE.test(k.type) || /Layout\.fillHeight\s*:\s*true/.test(head) || /anchors\.fill\s*:\s*parent/.test(head),
                escaped: /anchors\.\w+\s*:/.test(head),          // anchors 钉在容器上 = 逃出布局流
                hidden: /\bvisible\s*:\s*false/.test(head)
            };
        });
        // 吸底条候选 = 最后一个"可见"且钉高的直接子项 (#157 ②)
        let bar = null;
        for (let i = infos.length - 1; i >= 0; --i) {
            if (infos[i].hidden) continue;
            if (infos[i].tok || infos[i].rootTok) bar = infos[i];
            break;   // 只看最后一个可见子项 —— SheetPanelHead 那类"首子项钉高"到此为止
        }
        if (!bar) continue;
        const views = infos.slice(0, infos.indexOf(bar)).filter(x => x.viewport);
        if (!views.length) continue;    // 同层没有可被盖住的滚动区 (RecordTab 无列表, 安全)
        bars++;
        const region = text.slice(open + 1, bar.k.s);
        if (region.includes(TOKEN)) continue;                                   // 旧让位写法
        if (views.some(x => /(?:Layout|anchors)\.bottomMargin\s*:/.test(x.head))) continue;  // 显式底边距
        if (bar.rootTok && !bar.escaped) continue;   // #156 工作端口径: 组件根钉高的带子作为布局子项, 分配即让位
        hits.push([rel, toLine(bar.k.s),
                   '结构吸底条 (' + bar.k.type + ', 钉高 styles.' + (bar.rootTok || bar.tok) + ')'
                   + (bar.escaped ? ' 还浮在布局外 (anchors)' : '')
                   + ': 同层滚动区没给 ' + TOKEN + ', 末行会被盖住 (#157 新口径)']);
    }
}

// === 第三遍: 视口必须裁剪 (#158) ============================================
// Qt 的 ScrollView/ListView/Flickable 视口默认不裁剪: 内容超出视口的那一段照样画出来,
// 直接压在底部导航条 (NavBands) 那一格上. 0.0.5 模拟器实测 MePage 的「显示」段头落在
// y 2236-2268, 而带区是 2142-2274 —— 字叠字. 让位 (bottomClearance) 管的是"末行被条
// 盖住", 裁剪管的是"内容跑到条下面还接着画", 两回事, 都得守.
// 全树 15 处视口现在都带 clip: true, 所以这条按最严口径 (一个例外都不留) 定下来.
const CLIP_RE = /\b(ScrollView|ListView|GridView|Flickable)\s*\{/g;
let viewports = 0;
for (const { f, text } of CHECK) {
    const toLine = makeToLine(text);
    const rel = path.relative(ROOT, f).replace(/\\/g, '/');
    let m;
    CLIP_RE.lastIndex = 0;
    while ((m = CLIP_RE.exec(text)) !== null) {
        const open = text.indexOf('{', m.index);
        const close = jsBody(text, open);
        if (close < 0) continue;
        viewports++;
        if (!/\bclip\s*:\s*true/.test(ownProps(text.slice(open, close + 1)))) {
            hits.push([rel, toLine(m.index),
                       m[1] + ' 视口没有 clip: true, 超出视口的内容会画进底部导航条 (#158)']);
        }
        CLIP_RE.lastIndex = close;   // 只看这一层, 嵌套的视口由外层扫描自己那一段时命中
    }
}

// === 第四遍: 页根不许用 Math.max 兜高度 (#158b) =============================
// `height: Math.max(parent ? parent.height : 800, 800)` 的初衷是防"parent 还没给高度"
// 的塌陷 (layout_collapse_check 那一类), 但兜底值 800 逻辑比**视口本身还高**:
// 1080x2340@440dpi 上 StackView 只给到 779 逻辑, 于是 Page 比视口高 21 逻辑,
// 视口裁剪救不了它 (裁剪的边界就是那个太高的视口), 多出来的一截正好压在底部导航条上。
// 0.0.5 模拟器实测「显示」段头 y 2236-2268 / 带区 2142-2274, 加了 clip 也照叠 ——
// 真凶是这三行 (HomePage / MePage / SOSPage), 已改成"只在 parent 没高度时兜底"。
const FLOOR_RE = /^\s*height:\s*Math\.max\(\s*parent\b/;
for (const { f, raw } of CHECK) {
    if (!/\/pages\//.test('/' + path.relative(ROOT, f).replace(/\\/g, '/'))) continue;
    const lines = raw.split('\n');
    for (let i = 0; i < lines.length; ++i) {
        if (FLOOR_RE.test(lines[i])) {
            hits.push([path.relative(ROOT, f).replace(/\\/g, '/'), i + 1,
                       '页根用 Math.max(parent.height, N) 兜高度: 视口不足 N 逻辑时整页比视口高, '
                       + '多出来的一截画进底部导航条, clip 也救不了 (#158b)']);
        }
    }
}

// === 打印: 逐目录扫描数 (#157 ①, 反"静默 0 条") =============================
const byDir = {};
for (const { f } of CHECK) {
    const rel = path.relative(ROOT, f).replace(/\\/g, '/');
    const d = rel.includes('/') ? rel.slice(0, rel.lastIndexOf('/')) : '.';
    byDir[d] = (byDir[d] || 0) + 1;
}
console.log('=== 吸底条让位: 底栏标记 ' + checked + ' 处 + 结构吸底条 ' + bars +
            ' 处, 视口 ' + viewports + ' 个, 未让位/未裁剪 ' + hits.length + ' 处 ===');
console.log('扫描 .qml ' + texts.length + ' 个 (检查面 ' + CHECK.length + ' 个), 逐目录:');
for (const d of Object.keys(byDir).sort()) console.log('  ' + d + ': ' + byDir[d] + ' 个');
for (const [f, l, why] of hits) console.log(f + ':' + l + '  ' + why);
process.exit(hits.length ? 1 : 0);
