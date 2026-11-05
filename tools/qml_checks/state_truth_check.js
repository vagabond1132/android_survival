// L11 门禁: 控件显示的状态必须等于真实状态, 禁用必须给原因 (2026-11-03 #37, 真机 pass 2 F1)
// 四件事:
//   1 筛选控件的显示与列表必须是同一个状态源 (F1): 省份选「北京」页头与下拉都对, 月份选
//      「7 月」列表确实按 7 月过滤了, 下拉自己仍显示「全部」。根因是两条真相来源 ——
//      列表读页面的 currentMonth, 下拉显示读 ComboBox 内部 currentIndex, 页面没把
//      currentMonth 反推回 comboCurrentIndex。所以判据: 有 onComboActivated 的 FilterRow
//      必须同时把 comboCurrentIndex 绑到页面状态 (字面量数字不算绑定)。
//      裸 ComboBox 同理: 写死 `currentIndex: 3` 又在 onActivated 里读 currentIndex 往下游传。
//   2 裸的 enabled: false 必须有解释 —— 物种详情「带我过去」禁用没给原因, 用户只会以为
//      按钮坏了。判据: 同文件必须出现一句用户读得到的原因文案。
//   3 Popup 派生件必须 modal: true —— 图层面板 (F6) 就是能点穿那一类。标题与关闭途径由
//      overlay_triad_check.js 查 (那道要读块内结构, 与这道不是一个形状)。
//   4 「请求值 / 真实值」成对属性 (2026-11-04 #49 加, 真机 0.0.7 装备页): 页面里
//      `property int X` 是用户点的那一枚, `readonly property int XReal` 是这一屏的数
//      到底谁给的 (预报拿不到就落回往年推演)。Tab 条的 color / font.bold 原来读 X,
//      于是框上写着「当前天气预报」、五排 chip 与「数据来源」行却是往年值, 同屏另一行
//      还印着「退回往年推演: …」—— 三处口径两套真相。判据: 有 XReal 的文件里,
//      选中态表达式 (color / border.color / font.bold / checked / opacity / scale)
//      出现 `X === index` 即报; XReal 声明了却一处没人读也报 (真实值变死属性)。
// exit 0 干净 / 1 命中 / 2 门禁没跑起来 (qml 目录找不到)。命中数与文件数一并打印, 绝不静默 0。
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
// 最内层包住 idx 的块 —— 豁免注释 (`L11 免`) 只有写在这个块里才算数。
// 只在整个文件没有原因口径、又要判命中时才调用 (O(块数) 一次, 不在主扫描里跑)。
function innerBlock(text, idx) {
    let best = null;
    for (let i = 0; i < idx; i++) {
        if (text[i] !== '{') continue;
        const [a, b] = blockRange(text, i);
        if (idx <= b && (best === null || b - a < best.b - best.a)) best = { a, b };
    }
    return best;
}

// 块内 depth==1 的属性表。全部用正则字面量写:
//   new RegExp('(^|\n)\s*' + name + '\s*:' 这种拼法在本仓库踩过坑 —— 字符串里的 \s 会被
//   JS 吃掉反斜杠退化成 "s*", 于是 modal 明明写了也判成没写, 门禁安静地漏检。
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

const p1 = [], p2 = [], p3 = [], p4 = [];
const files = walk(QML, []);
for (const f of files) {
    const rel = path.relative(QML, f);
    const src = fs.readFileSync(f, 'utf8');
    const raw = stripComments(src);

    // --- 1a FilterRow: 显示与筛选同一个状态源 ---
    for (const m of raw.matchAll(/\bFilterRow\s*\{/g)) {
        const [a, b] = blockRange(raw, raw.indexOf('{', m.index));
        const props = shallowProps(raw.slice(a, b + 1));
        if (props.onComboActivated === undefined) continue;
        const idx = props.comboCurrentIndex, disp = props.comboDisplayText;
        if (idx === undefined && disp === undefined)
            p1.push([rel, lineOf(raw, m.index), 'FilterRow 有 onComboActivated 却没绑 comboCurrentIndex → 列表按页面状态过滤, 下拉按内部索引显示 (F1)']);
        else if (idx !== undefined && /^[-\d.]+$/.test(idx))
            p1.push([rel, lineOf(raw, m.index), 'comboCurrentIndex 写成字面量 ' + idx + ' → 选了别的也不会跟着变']);
    }
    // --- 1b 裸 ComboBox: 写死 currentIndex 又在 onActivated 里读它 ---
    for (const m of raw.matchAll(/\bComboBox\s*\{/g)) {
        const [a, b] = blockRange(raw, raw.indexOf('{', m.index));
        const body = raw.slice(a, b + 1);
        const props = shallowProps(body);
        const idx = props.currentIndex;
        if (idx !== undefined && /^[-\d.]+$/.test(idx)) {
            const act = body.indexOf('onActivated');
            if (act >= 0 && /currentIndex/.test(body.slice(act)))
                p1.push([rel, lineOf(raw, m.index), 'ComboBox currentIndex 写死 ' + idx + ' 且 onActivated 读内部 currentIndex → 显示与下游各一套']);
        }
    }

    // --- 2 禁用必须给原因 ---
    const reason = /disabledReason|不可用原因|点不动|现在不能|还没|先添加|先选|为什么不能|不能点/.test(raw);
    for (const m of raw.matchAll(/(^|\n)[ \t]*enabled[ \t]*:[ \t]*false\b/g)) {
        if (reason) break;
        // 块内写了 `L11 免` 的按豁免放行 (与上面按钮那条同一口径)。MapPage 的
        //   `MenuItem { enabled: false }` 走的就是这条: 那一行是浮层的标题条, 不是被禁掉的
        //   动作, 没有"为什么点不动"可回答 —— 让它免, 但必须留字说明, 不然规则本身会失效。
        const blk = innerBlock(src, m.index);
        if (blk && /L11[ \t]*免/.test(src.slice(blk.a, blk.b + 1))) continue;
        p2.push([rel, lineOf(raw, m.index), 'enabled: false 且本文件没有原因文案']);
    }

    // --- 2b 按钮族的"条件禁用"必须三选一交代清楚 ---
    //   (a) 块上带 `property string disabledHint: "为什么"` (页面把它画成按钮下面一行);
    //   (b) 标签自己会说明状态 (`text: 某状态 ? "搜索中" : "搜索本机"`);
    //   (c) 注释里写明 `L11 免` + 理由 (守卫实际到不了的禁用态)。
    //   手机端没有 hover, ToolTip 永远出不来 —— 所以没有"弹个提示"这条路。
    for (const m of raw.matchAll(/\b(PrimaryButton|OutlineButton|ToolButton|IconButton|Button)\s*\{/g)) {
        const [a, b] = blockRange(raw, raw.indexOf('{', m.index));
        const body = raw.slice(a, b + 1);
        const props = shallowProps(body);
        const en = props.enabled;
        if (en === undefined || en === 'true' || en === 'false') continue;
        const hasHint = /property\s+string\s+disabledHint\s*:/.test(body);
        const selfText = /(^|\n)[ \t]*text[ \t]*:[ \t]*[A-Za-z_$][^\n]*\?/.test(body);
        const waived = /L11[ \t]*免/.test(src.slice(a, b + 1));
        if (!hasHint && !selfText && !waived)
            p2.push([rel, lineOf(raw, m.index),
                     m[1] + ' 条件禁用 (enabled: ' + en.slice(0, 34) + ') 没给原因 → disabledHint / 换标签 / L11 免']);
    }

    // --- 3 Popup 派生件必须 modal ---
    for (const m of raw.matchAll(/\b(Dialog|Popup|Drawer)\s*\{/g)) {
        if (/(File)\s*$/.test(raw.slice(Math.max(0, m.index - 12), m.index))) continue; // FileDialog 由系统给遮罩
        const [a, b] = blockRange(raw, raw.indexOf('{', m.index));
        const modal = shallowProps(raw.slice(a, b + 1)).modal;
        if (modal !== 'true' && m[1] !== 'Drawer')
            p3.push([rel, lineOf(raw, m.index), m[1] + ' 没有 modal: true (Qt6 默认 false = 能点穿)']);
    }

    // --- 4 「请求值 / 真实值」成对属性: 选中态必须读真实值 (2026-11-04 #49) ---
    //   形状: 页面有可写的 `property int X` (用户点的那一枚) 与只读的
    //         `readonly property int XReal` (这一屏的数到底是谁给的)，
    //         且 XReal 的定义依赖 X (降级/回退那一族)。
    //   现场: 装备页选「当前天气预报」→ 拿不到数 → 读数落回往年推演，
    //         而 Tab 条的 color/font.bold 仍写 `weatherSource === index` →
    //         框说"预报"、数说"推演"，同屏另一行还印着「退回往年推演: …」。
    //   判据: ① 选中态表达式 (color / border.color / font.bold / checked / opacity / scale)
    //            里出现 `X === index` 而本页已经有 XReal → 报 (高亮读的是请求值);
    //         ② XReal 声明了却一处没人读 → 报 (真实值成了死属性，等于没有)。
    for (const m of raw.matchAll(/readonly\s+property\s+int\s+(\w+Real)\s*:/g)) {
        const realName = m[1], base = realName.slice(0, -'Real'.length);
        if (!new RegExp('(^|\\n)[ \\t]*property[ \\t]+int[ \\t]+' + base + '\\s*:').test(raw)) continue;
        // ① 选中态表达式读了请求值
        //   前缀只排除「单词字符」，**必须允许点号** —— 真实写法一律是
        //   `equipmentPage.weatherSource === index`，把 `.` 也排掉的话整条判据永远不命中
        //   (改前这里写的是 [^\w.]，拿真文件反证才发现是道静默门禁)。
        //   `weatherSourceReal === index` 不会被 base=weatherSource 误命中：后面紧跟 Real 就不是 `===`。
        const lines = raw.split('\n');
        const selValRe = new RegExp('(^|[^\\w])' + base + '\\s*===\\s*index');
        // 三元的续行很常见 (`border.color: a === index` 换行 `&& b !== index` 换行 `? x : y`)，
        // 只看物理行会把合规的配对形状读成"整行只问请求值"→ 真树第一条就是假阳性
        // (fixture 的 good/ 那一棵逼出来的)。这里把逻辑行拼回来：上一行以运算符收尾，
        // 或下一行以 `&& || ? : . ,` 起手，就继续并。
        const endsOp = (s) => /(&&|\|\||[?:,.]|[+\-*/])[ \t]*$/.test(s);
        const startsOp = (s) => /^[ \t]*(&&|\|\||[?:.])/.test(s);
        const logicalAt = (i) => {
            let t = lines[i], j = i;
            while (j + 1 < lines.length && j - i < 4 && (endsOp(t) || startsOp(lines[j + 1]))) {
                t += '\n' + lines[++j];
            }
            return t;
        };
        lines.forEach((line, i) => {
            if (!/(^|[;{}\s])((border\.|font\.)?color|font\.bold|checked|opacity|scale)\s*:/.test(line)) return;
            const text = logicalAt(i);
            if (!selValRe.test(text)) return;
            // 同一逻辑行还读了真实值 = 合规的「请求了但没供数」标记形状 (#49 的 blaze 描边就是这形状)，
            // 只有"整行拿请求值当选中态的唯一判据"才是两套真相。
            if (text.indexOf(realName) >= 0) return;
            p4.push([rel, i + 1,
                     '选中态读请求值 ' + base + ' (本文件已有真实值 ' + realName + ') → 显示与供数两套真相 (#49)']);
        });
        // ② 真实值声明了却一处没人读 (同样允许 `page.XReal` 这种带点的读法)
        const readRe = new RegExp('[^\\w]' + realName + '\\b', 'g');
        const reads = (raw.slice(raw.indexOf('\n', m.index)).match(readRe) || []).length;
        if (reads === 0)
            p4.push([rel, lineOf(raw, m.index), realName + ' 声明了却没人读 → 真实值成了死属性']);
    }
}
const say = (t, arr) => {
    console.log('--- ' + t + ': ' + arr.length + ' 处');
    for (const h of arr) console.log('  ' + h[0] + ':' + h[1] + '  ' + String(h[2]).slice(0, 92));
};
console.log('=== L11 状态真实 (扫 ' + files.length + ' 个 .qml) ===');
say('筛选控件显示与状态两条来源', p1);
say('禁用没给原因', p2);
say('Popup 派生件缺 modal: true', p3);
say('选中态读请求值而不是真实值', p4);
const n = p1.length + p2.length + p3.length + p4.length;
console.log('合计 ' + n + ' 处');
process.exit(n ? 1 : 0);
