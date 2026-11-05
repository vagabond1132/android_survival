// L3/L6 门禁: 被父级定高的 ColumnLayout 必须自己说清楚"剩余高度归谁"
// (2026-11-03 #37 → #42, 真机 0.0.6 复量 F5 + L6)
//
// 为什么查这个 (F5 的真实根因, 不是观感问题):
//   EmergencyContactsPage 的名册格写成 `Layout.fillHeight: contactCount > 0`。0 个联系人时
//   整棵页根 ColumnLayout 一个 fillHeight 子项都没有, Qt Quick Layouts 于是把剩余高度摊到
//   子项之间, 54px 标题条被顶下 67 逻辑 px —— 返回方块从 device y=266 跑到 454。
//   真机对照 (0.0.6, 同一台 HONOR, 1224x2688, density 448, 逻辑→设备 ×2.8):
//     绳结 266 / 急救索引 263 / 装备清单 263 / 应急储备清单 266 / 急救详情 275 / 紧急联系人 454
//   全仓只有这一页用条件 fillHeight, 也只有这一页漂了 188 设备像素。
//   同族第二例 RecordTab (地图「记录」sheet) 就是靠这条抓出来的: 它整棵 ColumnLayout 一个
//   fill 子项都没有, 未录制时数据卡不出现, 动作带被摊到 sheet 底边外, 正是 pass 2 记的
//   「黑框下缘被 sheet 裁掉」。
//
// 形状 (判据范围, 不是"页根"而是"任何被外部定高的 ColumnLayout"):
//   只有当父级把高度*外部*塞给 ColumnLayout 时才会出现富余 —— 也就是父级自己也被定高
//   (anchors.fill: parent / Layout.fillHeight: true), 或父级是页根 (没人给它定高, 高度由
//   StackView / 宿主决定)。这类布局必须有至少一个直接子项吃掉富余, 否则 Qt 把剩余高度
//   摊到子项之间, 首行漂走 (F5 就是这条, 漂了 67 逻辑 px)。
//   另一种形状是"卡片包内容": 父级高度 = 本布局的 implicitHeight + pad, 或父级高度是写死的
//   一个 token (rowHTall)。这两种天生没有富余 (富余恒等于 0), 摊不摊是无意义命题 —— 门禁
//   把它们单独计数、不判失败。它们自己的失败模式是"内容长过写死高度被压扁/裁掉",
//   那是另一条定律 (裁切族), 不归这里。
//   ScrollView / Flickable 里靠内容自己长高的 ColumnLayout 没有 anchors.fill, 不在射程内。
//   页根直接挂 ScrollView 的 (Home / Me / SOS) 也没有可查的 ColumnLayout —— 那种页由
//   StackView 定高、由 ScrollView 自己铺满, 没有"被摊开"的那一层。
//   反过来, 定高 ColumnLayout 里的 ScrollView 不算合规: 它的 Layout.fillHeight 默认 false,
//   富余照样摊到子项之间 —— 判据只认字面量 `Layout.fillHeight: true`。
//   条件 fillHeight (`Layout.fillHeight: 某表达式`) 全仓禁止, 不限 ColumnLayout: 它在某个
//   态下会让宿主失去唯一 fill 子项, F5 就是这条的现场。
//   两个 fillHeight 子项只禁"都没有 visible 条件"的那种 (两格同时抢剩余高度)。互斥 visible
//   的一对是合法形状 —— MapBottomSheet 的折叠档 RowLayout 与展开档 StackLayout 就是这样,
//   同一时刻只有一个可见, Layouts 不给 invisible 子项分高; 写死 `visible: false` 的 taker
//   反过来要扣除, 它等于没有 (fixture 里的 BadHidden 就是这一例)。
//
// 顶部净空 (L6): 六个二级页的面包屑墨迹都从 device y=249 起画, 正好顶在 app bar 下缘。
//   修法是 StackView 一处 `anchors.topMargin: winStyles.topClearance`。门禁盯两件事:
//   token 还在, 且确实被 StackView 用着 —— 少一边都会让 23 个页头一起退回零净空。
//
// exit 0 干净 / 1 命中 / 2 门禁没跑起来 (目录或关键文件找不到)。绝不静默 0 条。
const fs = require('fs'), path = require('path');
const ARGS = process.argv.slice(2);
// --verbose 把每一个 anchors.fill: parent 的 ColumnLayout 连同它的父级定高来源打出来:
//   这条门禁会"免查"一批自定高的卡片壳, 免查名单必须可审计, 否则漏检是静默的。
const VERBOSE = ARGS.includes('--verbose');
const QML = ARGS.find((a) => !a.startsWith('--')) || path.resolve(__dirname, '../../qml');
if (!fs.existsSync(QML)) { console.error('找不到 qml 目录: ' + QML + ' (门禁未运行, 判 exit 2)'); process.exit(2); }

// 注释先换成等量空白: 行号不变, 讲解这条坑的注释本身不会被当成代码命中。
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
// 列出块内 depth==1 的直接子对象块: [{type, start, end}]。
// 只认 "Type {" 形状 (属性行、注释、内联一行 Item 都不算子块)。
function childBlocks(raw, a, b) {
    const out = [];
    let depth = 0;
    for (let i = a; i <= b; i++) {
        const c = raw[i];
        if (c === '{') {
            if (depth === 1) {
                // 回溯这段 "{" 之前的标识符
                let j = i - 1;
                while (j > a && /[ \t]/.test(raw[j])) j--;
                let k = j;
                while (k > a && /[A-Za-z0-9_.]/.test(raw[k - 1])) k--;
                const name = raw.slice(k, j + 1);
                if (/^[A-Z][A-Za-z0-9_]*$/.test(name)) out.push({ type: name, start: i });
            }
            depth++;
        } else if (c === '}') {
            depth--;
            if (depth === 1 && out.length && out[out.length - 1].end === undefined)
                out[out.length - 1].end = i;
            if (depth === 0) return out;
        }
    }
    return out;
}
// 块内属性值 (第一处命中), a 必须是这个块的 "{" 下标。
// 按"相对块的括号深度"判定, 不按行首判定 —— 2026-11-03 fixture 抓到两个漏检都是行锚点造成的:
//   `Item { Layout.fillHeight: true }` 这种一行式子项的属性被整块跳过 (行首是 "Item {"),
//   `anchors { fill: parent; margins: 16 }` 的分组写法同样读不到。
// 深度约定: 块自身的属性 = 1; 直接子块的属性 = 2, 所以子项的 fillHeight 不会被误认成块的。
// anchors 分组写法 (= 深度 2, 且包住它的那个块的名字正好是属性前缀) 也算。
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function relDepth(block, idx) {
    let d = 0;
    for (let i = 0; i < idx; i++) {
        const c = block[i];
        if (c === '{') d++;
        else if (c === '}') d--;
    }
    return d;
}
function enclosingWord(block, idx) {
    let bal = 0;
    for (let i = idx - 1; i >= 0; i--) {
        if (block[i] === '}') bal++;
        else if (block[i] === '{') {
            if (bal === 0) {
                let j = i - 1;
                while (j >= 0 && /[ \t\r\n]/.test(block[j])) j--;
                let k = j;
                while (k > 0 && /[A-Za-z0-9_.]/.test(block[k - 1])) k--;
                return block.slice(k, j + 1);
            }
            bal--;
        }
    }
    return null;
}
// 一行式块的末尾 `}` 会被当成值的一部分 (`Layout.fillHeight: true }`), 去掉它。
const cleanVal = (v) => v.replace(/[ \t]*\}[ \t]*$/, '').trim();
function shallowProp(raw, a, b, name) {
    const block = raw.slice(a, b + 1);
    const parts = name.split('.');
    const direct = new RegExp('(^|[^A-Za-z0-9_])' + parts.map(esc).join('[ \\t]*\\.[ \\t]*') + '[ \\t]*:[ \\t]*([^;\\n]*)', 'g');
    for (let m; (m = direct.exec(block));)
        if (relDepth(block, m.index + m[1].length) === 1) return cleanVal(m[2]);
    if (parts.length < 2) return undefined;
    const last = new RegExp('(^|[^A-Za-z0-9_.])' + esc(parts.slice(-1)[0]) + '[ \\t]*:[ \\t]*([^;\\n]*)', 'g');
    for (let m; (m = last.exec(block));)
        if (relDepth(block, m.index + m[1].length) === 2 && enclosingWord(block, m.index + m[1].length) === parts[0])
            return cleanVal(m[2]);
    return undefined;
}

// 包住这段 "{" 的父块 "{" (栈顶)。返回 undefined = 这段就是文件根 (父级由宿主定高)。
function parentBraceOf(raw, brace) {
    const stack = [];
    for (let i = 0; i < brace; i++) {
        const c = raw[i];
        if (c === '{') stack.push(i);
        else if (c === '}') stack.pop();
    }
    return stack.length ? stack[stack.length - 1] : undefined;
}
const typeBefore = (raw, brace) => {
    let j = brace - 1;
    while (j >= 0 && /[ \t\r\n]/.test(raw[j])) j--;
    let k = j;
    while (k > 0 && /[A-Za-z0-9_.]/.test(raw[k - 1])) k--;
    return raw.slice(k, j + 1);
};
// 父级的高度从哪来: 'external' = 别人塞给它 (要查), 'self' = 它跟着本布局的
// implicitHeight 长 (富余恒为 0), 'fixed' = 写死一个数 / token (同上)。
const HEIGHT_PROPS = ['height', 'implicitHeight', 'Layout.preferredHeight', 'Layout.minimumHeight', 'Layout.maximumHeight'];
function parentSizing(raw, pa, pb) {
    if (shallowProp(raw, pa, pb, 'anchors.fill') === 'parent') return 'external';
    if (shallowProp(raw, pa, pb, 'Layout.fillHeight') === 'true') return 'external';
    const vals = HEIGHT_PROPS.map((p) => shallowProp(raw, pa, pb, p)).filter((v) => v !== undefined);
    for (const v of vals) {
        if (/\bparent\b[ \t]*\.[ \t]*(height|availableHeight)/.test(v)) return 'external';
        if (/\bimplicitHeight\b/.test(v)) return 'self';
    }
    for (const v of vals)
        if (/^[0-9+\-*/()., \t]+$/.test(v) || /^[A-Za-z_][A-Za-z0-9_.]*$/.test(v)) return 'fixed';
    return 'external';
}

const qmlFiles = walk(QML, []).sort();
// 能吃掉剩余高度的子项只有 `Layout.fillHeight: true` 一种。
// 滚动容器不算: ScrollView / ListView / Flickable 的 Layout.fillHeight 默认就是 false,
// 在定高 ColumnLayout 里它照样只拿 implicitHeight, 富余仍然被摊开 —— 把"它是滚动容器"
// 当免检牌会漏掉真缺陷, 所以这里刻意不留这个口子。
const noFill = [], condFill = [], multiFill = [], unreadable = [], siteLog = [];
let filledCount = 0, checkedCount = 0, selfCount = 0, fixedCount = 0;

for (const f of qmlFiles) {
    const rel = path.relative(QML, f);
    let src;
    try { src = fs.readFileSync(f, 'utf8'); }
    catch (e) { unreadable.push([rel, 1, '读不出: ' + e.message]); continue; }
    const raw = stripComments(src);

    // 条件 fillHeight: 全仓任何位置都禁 (值不是字面量 true)。一行式子项也要抓到,
    // 所以不按行首锚点, 值截到 ';' 为止。
    for (const m of raw.matchAll(/(^|[^A-Za-z0-9_.])Layout\.fillHeight[ \t]*:[ \t]*([^;\n]*)/g)) {
        const v = cleanVal(m[2]);
        // 字面 false 只是"我不是吃满那一格", 有兄弟吃满就合规; 表达式才是 F5 那个态相关陷阱。
        if (v !== 'true' && v !== 'false') condFill.push([rel, lineOf(raw, m.index + m[1].length), '条件 fillHeight: ' + v.slice(0, 60)]);
    }

    // 被外部定高的 ColumnLayout
    for (const m of raw.matchAll(/(^|[^A-Za-z0-9_])ColumnLayout[ \t]*\{/g)) {
        const brace = raw.indexOf('{', m.index + m[0].length - 1);
        const [a, b] = blockRange(raw, brace);
        if (shallowProp(raw, a, b, 'anchors.fill') !== 'parent') continue;
        filledCount++;
        const pb = parentBraceOf(raw, a);
        let exempt = '';
        if (pb === undefined) { checkedCount++; }
        else {
            const [pa, pEnd] = blockRange(raw, pb);
            const kind = parentSizing(raw, pa, pEnd);
            if (kind === 'self') { selfCount++; exempt = 'self(' + (shallowProp(raw, pa, pEnd, 'height') || shallowProp(raw, pa, pEnd, 'Layout.preferredHeight') || shallowProp(raw, pa, pEnd, 'implicitHeight')) + ')'; }
            else if (kind === 'fixed') { fixedCount++; exempt = 'fixed(' + (shallowProp(raw, pa, pEnd, 'height') || shallowProp(raw, pa, pEnd, 'Layout.preferredHeight')) + ')'; }
            else checkedCount++;
        }
        siteLog.push('  [site] ' + rel + ':' + lineOf(raw, a) + '  父=' + (pb === undefined ? '(文件根)' : typeBefore(raw, pb)) + '  ' + (exempt ? '免查 ' + exempt : '查'));
        if (exempt) continue;
        const kids = childBlocks(raw, a, b).filter((c) => c.end !== undefined);
        if (!kids.length) { unreadable.push([rel, lineOf(raw, a), '外部定高的 ColumnLayout 没有可解析的直接子项']); continue; }
        const takers = [], alwaysTakers = [];
        for (const k of kids) {
            if (shallowProp(raw, k.start, k.end, 'Layout.fillHeight') !== 'true') continue;
            const vis = shallowProp(raw, k.start, k.end, 'visible');
            // 写死 visible: false 的 taker 等于没有 (那个态下这一格根本不存在)
            if (vis === 'false') continue;
            takers.push(k);
            // visible 是表达式的 taker 只在某个态下吃满 —— MapBottomSheet 折叠档 / 展开档
            // 互斥的两格就是这个形状, 合法; 没有任何 visible 的才是"永远抢剩余高度"。
            if (vis === undefined) alwaysTakers.push(k);
        }
        if (takers.length === 0)
            noFill.push([rel, lineOf(raw, a), '外部定高的 ColumnLayout 的 ' + kids.length + ' 个直接子项没有一个可用的 Layout.fillHeight: true —— 剩余高度被摊到子项之间, 首行漂走 (父级 ' + (pb === undefined ? '文件根' : typeBefore(raw, pb)) + ')']);
        if (alwaysTakers.length > 1)
            multiFill.push([rel, lineOf(raw, alwaysTakers[1].start), '外部定高的 ColumnLayout 有 ' + alwaysTakers.length + ' 个无 visible 条件的 fillHeight 子项 —— 两格同时抢剩余高度, 谁大不确定']);
    }
}

// L6 顶部净空的单一来源
const clearBad = [];
const stylesF = path.join(QML, 'components', 'base', 'Styles.qml');
const mainF = path.join(QML, 'Main.qml');
for (const [p, why] of [[stylesF, 'Styles.qml'], [mainF, 'Main.qml']]) {
    if (!fs.existsSync(p)) { clearBad.push(['(缺文件) ' + why, 1, '门禁读不到 ' + why]); }
}
if (!clearBad.length) {
    const st = stripComments(fs.readFileSync(stylesF, 'utf8'));
    if (!/^[ \t]*readonly property int topClearance[ \t]*:/m.test(st))
        clearBad.push(['components/base/Styles.qml', 1, 'topClearance token 没了 —— 页首净空退回逐页硬写']);
    const mn = stripComments(fs.readFileSync(mainF, 'utf8'));
    const sv = mn.match(/StackView[ \t]*\{/);
    if (!sv) clearBad.push(['Main.qml', 1, 'StackView 块没找到']);
    else {
        const [a, b] = blockRange(mn, mn.indexOf('{', sv.index));
        const tm = shallowProp(mn, a, b, 'anchors.topMargin');
        if (tm === undefined) clearBad.push(['Main.qml', lineOf(mn, a), 'StackView 没有 anchors.topMargin —— 面包屑重新顶进 app bar']);
        else if (!/topClearance/.test(tm)) clearBad.push(['Main.qml', lineOf(mn, a), 'StackView topMargin 没绑 topClearance: ' + tm.slice(0, 50)]);
    }
}

const buckets = [['外部定高 ColumnLayout 没有一个 Layout.fillHeight: true 子项 (F5 那一类)', noFill],
                 ['条件 fillHeight (F5 的原形)', condFill],
                 ['外部定高 ColumnLayout 多个 fillHeight', multiFill],
                 ['形状读不出 (不当它干净)', unreadable],
                 ['L6 顶部净空失守', clearBad]];
let total = 0;
console.log('=== L3/L6 定高 ColumnLayout 与顶部净空: ' + qmlFiles.length + ' 个 qml ===');
console.log('  anchors.fill: parent 的 ColumnLayout: ' + filledCount +
            ' —— 外部定高要查 ' + checkedCount + ' / 包内容 self ' + selfCount +
            ' + 写死 fixed ' + fixedCount + ' (富余恒为 0, 不判)');
if (VERBOSE) for (const s of siteLog) console.log(s);
if (filledCount === 0) console.error('  一个 anchors.fill 的 ColumnLayout 都没解析出来 —— 门禁没跑起来, 判 exit 2');
for (const [name, arr] of buckets) {
    console.log('  ' + name + ': ' + arr.length);
    for (const [f, l, why] of arr) console.log('    ' + f + ':' + l + '  ' + why);
    total += arr.length;
}
if (filledCount === 0) process.exit(2);
process.exit(total ? 1 : 0);
