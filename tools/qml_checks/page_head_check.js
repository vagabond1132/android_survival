// L3 + L6-1 门禁: 页首标题条只许有一处几何, 且那处几何不许裁掉内容
//   (二级页统一用 PageHeadBand; 2026-11-03 #42 收抄本, 2026-11-04 #42 补高度判据)
//
// 为什么查这个:
//   真机 pass 2 量到"同类控件不是一套几何" (定律 L13), 页头家族是最实的一例:
//   13 个页各写了一份逐字节相同的标题条, 高度 12 份写 54、①营地写 52 —— 52/54 这两格
//   差本身就是复制体漂移。右缘让位更离谱: 40 / 56 / 64 三个数各页不同, 全是"照着当时
//   那一屏数出来的"(40 = 返回方块 26 + 14; 56/64 = 角标宽 + 空隙), 没有一处是算出来的。
//   同一族控件的第三种抄法在 MePage: 边距不写在 Layout 上而写进 Column 的 anchors 里,
//   微标签字距 1.6 而不是 1.8。下一次改页头字号必然有人漏一页, 漏掉那页在真机上就
//   是"这页排版不对"。
//
// 形状判据 (不是"数字 54", 数字会漂, 形状才是这一族):
//   一个块 *自己* 带 `Layout.preferredHeight:` (深度 1 的属性), 且它的一个直接子块里同时
//   有 `anchors.bottom: parent.bottom` (贴底) 与 `font.pixelSize: styles.fs2xl` (页名)
//   —— 就是页头条。只许出现在 qml/components/base/PageHeadBand.qml 里; 页文件一律实例化组件。
//   "自己带定高"这一层限死是必要的: 第一版只查"子树里同时有三个记号", 结果 12 个页的
//   `Page {` 根块全被当成复制体 (整页当然什么都在里面), 真正的页头反而被外层吃掉 ——
//   fixture 里的 BadPageRoot 专门钉这个坑。
//   详情页 hero 家族 (150px 高、带面包屑和右上角方块) 不是这个形状 (不靠 Layout.preferredHeight
//   定高), 判据 1 抓不到 —— 那一家归下面的判据 6。
//
// 右上角方块判据 6 (2026-11-05 #43 / 定律 L13):
//   见下面代码段的说明: 边长/热区/上边线/右让位四个属性必须走同一组 token, 全树 12 处方块同一条线。
//
// 组件用起来判据:
//   全树必须有 PageHeadBand 实例 (0 个 = 组件被架空, 本门禁无从判合规 → exit 2);
//   一个页文件里出现 2 个实例 = 命中 (一页只该有一条标题条)。
//
// 几何单点判据 (组件自己也要守规矩, 否则只是把 13 份抄本合成了 1 份抄本):
//   Styles.qml 必须声明 pageHeadH / pageHeadBox / pageHeadTapPad 三个 readonly int;
//   PageHeadBand.qml 必须把它们分别用在 Layout.preferredHeight、方块 width+height、
//   热区 anchors.margins 上, 且这三处不许再写字面 54 / 26 / 9。
//
// 让位判据:
//   `anchors.rightMargin: <字面数字>` 全树禁止 (0 除外)。这一族的让位量必须由组件按右上
//   角控件实际宽现算; 手抄的数字换字即挤 (角标从 "G-4" 变 "10:42" 就撞在一起)。
//
// 高度判据 (2026-11-04 #42 / 定律 L6-1, 真机 0.0.7 走查 A 组 FAIL):
//   组件的定高必须是 `Math.max(styles.pageHeadH, headCol.implicitHeight)`, 且 headCol 真
//   有声明。写死一个"今天够用的数"等于把这条律绑在当前字号上 —— 改字号又会裁顶。
//   判据 2 只查"这一行引没引 token", max() 形式里也引了 token, 所以查不出高度不够;
//   要单独钉住, 见下面判据 5 那段。
//
// exit 0 干净 / 1 命中 / 2 门禁没跑起来 (目录、组件或页头实例找不到)。绝不静默 0 条。
const fs = require('fs'), path = require('path');
const ARGS = process.argv.slice(2);
const VERBOSE = ARGS.includes('--verbose');
const ROOT = path.resolve(__dirname, '../..');
const QML = ARGS.find((a) => !a.startsWith('--')) || path.resolve(ROOT, 'qml');
const BAND = path.join(QML, 'components', 'base', 'PageHeadBand.qml');
const STYLES = path.join(QML, 'components', 'base', 'Styles.qml');

function die2(msg) { console.error('!! ' + msg + ' —— 门禁没有真正运行, 判 exit 2'); process.exit(2); }
if (!fs.existsSync(QML)) die2('找不到 qml 目录 ' + QML);
if (!fs.existsSync(BAND)) die2('找不到 PageHeadBand.qml (组件被删了? 那 L3 就没有单点几何可言)');
if (!fs.existsSync(STYLES)) die2('找不到 Styles.qml (页头 token 的宿主)');

// 注释换成等量空白: 行号不变, 讲解这条坑的注释不会被当成代码命中。
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
    let d = 0;
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
// 块"自己"的属性 (深度 1) —— 没有这条就会把整棵 Page 当成页头条:
//   Page 块的子树里当然同时有定高、贴底容器和 fs2xl 页名, 那是包含关系不是形状。
function ownProp(block, name) {
    const re = new RegExp('(^|[^A-Za-z0-9_.])' + name.replace(/\./g, '[ \\t]*\\.[ \\t]*')
        + '[ \\t]*:[ \\t]*([^;\\n]*)', 'g');
    for (let m; (m = re.exec(block));) if (relDepth(block, m.index + m[1].length) === 1) return true;
    return false;
}
// 块"自己"的某个属性写了什么值 (深度 1, 取第一个) —— 判据 6 要按值比 token, 不能只比有没有。
function ownPropVal(block, name) {
    const re = new RegExp('(^|[^A-Za-z0-9_.])' + name.replace(/\./g, '[ \\t]*\\.[ \\t]*')
        + '[ \\t]*:[ \\t]*([^;\\n]*)', 'g');
    for (let m; (m = re.exec(block));) if (relDepth(block, m.index + m[1].length) === 1) return m[2].replace(/[ \t]+$/, '');
    return null;
}

// 块的直接子块 (深度 1 的 "Type {")
function childBlocks(raw, a, b) {
    const out = [];
    let depth = 0;
    for (let i = a; i <= b; i++) {
        const c = raw[i];
        if (c === '{') {
            if (depth === 1) {
                const head = raw.lastIndexOf('\n', i) + 1;
                const t = /^[ \t]*([A-Z][A-Za-z0-9_]*)[ \t]*\{/.exec(raw.slice(head, i + 1));
                if (t) { const [oa, ob] = blockRange(raw, i); out.push({ type: t[1], a: oa, b: ob }); }
            }
            depth++;
        } else if (c === '}') depth--;
    }
    return out;
}

const hits = [];
const files = walk(QML, []).sort();
let bandFiles = 0, bandUses = 0, scanned = 0, shapeBlocks = 0, pageShape = 0, heroBoxes = 0;
const boxSites = [];

// Styles 的数值先读出来: 判据 6 要按 pageHeadTapPad 的实际值算最小间距。
const stylesSrc = stripComments(fs.readFileSync(STYLES, 'utf8'));
const PAD = Number((/readonly[ \t]+property[ \t]+int[ \t]+pageHeadTapPad[ \t]*:[ \t]*(\d+)/.exec(stylesSrc) || [])[1] || 0);
if (!PAD) die2('Styles 里读不到 pageHeadTapPad 的数值 —— 判据 6 没法算并排方块的最小间距');

for (const f of files) {
    let raw;
    try { raw = stripComments(fs.readFileSync(f, 'utf8')); }
    catch (e) { die2('读不了 ' + f + ': ' + e.message); }
    scanned++;
    const isBand = path.resolve(f) === path.resolve(BAND);

    // --- 实例化点计数 (判据 4: 组件真的被用起来, 而不是又退回抄本) ---
    const useRe = /(^|[^A-Za-z0-9_.])PageHeadBand[ \t]*\{/g;
    const uses = raw.match(useRe) || [];
    if (uses.length) {
        bandUses += uses.length;
        if (!isBand) bandFiles++;
        if (uses.length > 1) {
            // 行号取"第一个实例"自己的位置: 之前写成 raw.indexOf('{') 会把全树第一个花括号
            // (Page { 那一行)报成命中位置, 照着 HIT 的行号跳过去会跳到错的块。
            useRe.lastIndex = 0;
            const first = useRe.exec(raw);
            hits.push({ f, line: lineOf(raw, first.index + first[1].length),
                why: '一个文件里 ' + uses.length + ' 个 PageHeadBand —— 一页只该有一条页首标题条' });
        }
    }

    // --- 判据 1: 页头条形状只许在组件内 ---
    // 形状 = 块自己有 Layout.preferredHeight + 直接子块里有"贴底容器 + fs2xl 页名"。
    const opens = [];
    for (let i = 0; i < raw.length; i++) if (raw[i] === '{') opens.push(i);
    for (const i of opens) {
        const head = raw.lastIndexOf('\n', i) + 1;
        const type = /^[ \t]*([A-Z][A-Za-z0-9_]*)[ \t]*\{/.exec(raw.slice(head, i + 1));
        if (!type) continue;
        const [a, b] = blockRange(raw, i);
        const body = raw.slice(a, b + 1);
        if (!ownProp(body, 'Layout.preferredHeight')) continue;
        // 页头条是透明壳: 有 `color:` 的是"画了底色的 hero" (10 个详情页头, 150 高,
        //   四角各一块: 下缘描边 / 居中大字读数 / 左上 chip / 右上返回 / 贴底的编号+名称+状态).
        //   hero 的贴底那一组三段 (微标签 / 名 / 状态) 与本族逐字同形, 所以纯文字记号分不开,
        //   只能按"壳有没有底色"切。这一刀是有代价的: 将来若有人把页头条写进有底色的盒子里,
        //   本判据会漏 —— 详情页 hero 自己那一套几何归 #43, 那里另立判据。
        if (ownProp(body, 'color')) continue;
        const kids = childBlocks(raw, a, b);
        const hasBandColumn = kids.some((k) => {
            const sub = raw.slice(k.a, k.b + 1);
            return /(^|[^A-Za-z0-9_.])anchors\.bottom[ \t]*:[ \t]*parent\.bottom/.test(sub)
                && /(^|[^A-Za-z0-9_.])font\.pixelSize[ \t]*:[ \t]*styles\.fs2xl/.test(sub);
        });
        if (!hasBandColumn) continue;
        shapeBlocks++;
        if (!isBand) {
            pageShape++;
            hits.push({ f, line: lineOf(raw, head), why: '手写页头条复制体 (' + type[1]
                + ' 块: 自带 Layout.preferredHeight + 贴底的 fs2xl 页名列) —— 改成 PageHeadBand 实例' });
        } else if (VERBOSE) {
            console.log('  band-shape @ ' + f + ':' + lineOf(raw, head));
        }
    }

    // --- 判据 3: 让位量不许手抄 ---
    const rm = /(^|[^A-Za-z0-9_.])anchors\.rightMargin[ \t]*:[ \t]*([^\n;]*)/g;
    for (let m; (m = rm.exec(raw));) {
        const v = m[2].replace(/[ \t]+\}/, '').trim();
        if (/^\d+$/.test(v) && v !== '0') {
            hits.push({ f, line: lineOf(raw, m.index + m[1].length), why: 'anchors.rightMargin: ' + v
                + ' 是照着一屏数出来的死数 —— 右上角让位必须由组件按控件实际宽现算' });
        }
    }
    // --- 判据 6 (2026-11-05 #43 / 定律 L13): 右上角那一方块全树一套几何 ---
    //   真机 0.0.9 量到 hero 家族把返回方块画成 30 见方 (页头带是 26), 热区只外扩 6 而不是 9,
    //   盒子上边线 hero 305 vs 页头带 294 —— 同一族控件三种抄法。判据 1 按"壳有没有底色"
    //   把 hero 整族切了出去, 所以这一家一直是本页面的盲区, 这里补上。
    //   形状 (--verbose 会把 12 块的 文件:行号 全打出来; 实测全树 11 组贴角方块、共 12 块
    //   对得上 —— 9 页 hero 各 1 块 + 图鉴 1 组 2 块 + 页头带 1 块, 不会误伤别的贴角元素):
    //     块自己有 anchors.right: parent.right 且 anchors.top: parent.top (贴右上角), 然后
    //       ① 它自己同时有 width + height + border.color → 单块组 (9 页 hero + 页头带);
    //       ② 它的直接子 Rectangle 同时有这三个属性 → 多块组 (图鉴收藏+返回并排那一处)。
    //   判据: 边长 = styles.pageHeadBox; 上边线 = styles.spXs (294 那条线就是这么对齐的:
    //   内容顶 249 + (topClearance 12 + spXs 4) × 2.8 = 293.8 设备 px); 写了 rightMargin 就
    //   必须是 styles.pageMargin; 块内 MouseArea 的热区外扩 = -styles.pageHeadTapPad。
    //   多块组另加一条: spacing 解析得出来时必须 >= 2×pageHeadTapPad —— 两格各扩 9, 间距不够
    //   就是后画的返回压掉前一格右边缘, 戴手套按收藏会按成返回。解析不出来的式子放过 (不误判)。
    const groups = [];
    for (let i = 0; i < raw.length; i++) {
        if (raw[i] !== '{') continue;
        const head = raw.lastIndexOf('\n', i) + 1;
        const t = /^[ \t]*([A-Z][A-Za-z0-9_]*)[ \t]*\{/.exec(raw.slice(head, i + 1));
        if (!t) continue;
        const [ga, gb] = blockRange(raw, i);
        const gbody = raw.slice(ga, gb + 1);
        if (ownPropVal(gbody, 'anchors.right') !== 'parent.right') continue;
        if (ownPropVal(gbody, 'anchors.top') !== 'parent.top') continue;
        const isBox = (b) => ownPropVal(b, 'width') !== null && ownPropVal(b, 'height') !== null
            && /(^|[^A-Za-z0-9_.])IconLabel[ \t]*\{/.test(b);
        if (isBox(gbody)) { groups.push({ body: gbody, line: lineOf(raw, head), multi: false }); continue; }
        const kids = childBlocks(raw, ga, gb).filter((k) => k.type === 'Rectangle' && isBox(raw.slice(k.a, k.b + 1)));
        if (kids.length) groups.push({ body: gbody, line: lineOf(raw, head), multi: true,
            boxes: kids.map((k) => ({ body: raw.slice(k.a, k.b + 1), line: lineOf(raw, k.a) })) });
    }
    for (const g of groups) {
        for (const box of g.multi ? g.boxes : [{ body: g.body, line: g.line }]) {
            heroBoxes++;
            boxSites.push(path.relative(ROOT, f) + ':' + box.line);
            const mark = (v, prop, want, why) => {
                if (v === want) return;
                hits.push({ f, line: box.line, why: prop + ': ' + v + ' —— ' + why + ' (写 ' + want + ')' });
            };
            mark(ownPropVal(box.body, 'width'), 'width', 'styles.pageHeadBox', '右上角方块边长是 L13 那一条, hero 与页头带共用');
            mark(ownPropVal(box.body, 'height'), 'height', 'styles.pageHeadBox', 'height 必须与 width 同一个 token');
            const tm = ownPropVal(g.body, 'anchors.topMargin');
            if (tm !== 'styles.spXs') {
                hits.push({ f, line: g.line, why: '右上角那组方块的 anchors.topMargin: ' + tm
                    + ' —— 上边线必须是 styles.spXs, 否则与页头带差出一截 (真机 hero 305 vs 页头带 294)' });
            }
            const rmv = ownPropVal(g.body, 'anchors.rightMargin');
            if (rmv !== null && rmv !== 'styles.pageMargin') {
                hits.push({ f, line: g.line, why: '右上角那组方块的 anchors.rightMargin: ' + rmv
                    + ' —— 右让位统一 styles.pageMargin (hero 曾用 cardPad, 与页边距差 4)' });
            }
            const pad = /(^|[^A-Za-z0-9_.])anchors\.margins[ \t]*:[ \t]*([^;\n]*)/.exec(box.body);
            if (!pad) {
                hits.push({ f, line: box.line, why: '方块里的热区没写 anchors.margins —— 描边盒只有 26, 戴手套按不到 44' });
            } else if (pad[2].replace(/[ \t]+$/, '') !== '-styles.pageHeadTapPad') {
                hits.push({ f, line: box.line, why: '热区 anchors.margins: ' + pad[2].replace(/[ \t]+$/, '')
                    + ' —— 外扩必须走 -styles.pageHeadTapPad (写死 6 的那批比 44 少 8)' });
            }
        }
        if (g.multi) {
            // spacing 只要能算出数就判, 算不出 (引用运行期属性之类) 就放过 —— 宁可放过一条式子,
            // 也不把判据绑死在"必须写成 pageHeadTapPad * 2"这一种排版上。
            // 式子先被 term 限成 数字 / styles.<字母数字下划线> / 两者相乘, 再拿这个名字去 Styles
            // 查 readonly int —— 名字里进不去反斜杠与量词, 拼正则才安全。
            const sp = ownPropVal(g.body, 'spacing');
            const term = /^[ \t]*(?:(\d+)[ \t]*\*[ \t]*styles\.([A-Za-z0-9_]+)|styles\.([A-Za-z0-9_]+)[ \t]*\*[ \t]*(\d+)|styles\.([A-Za-z0-9_]+))[ \t]*$/;
            const styleInt = (tok) => Number((new RegExp('readonly[ \\t]+property[ \\t]+int[ \\t]+'
                + tok + '[ \\t]*:[ \\t]*(\\d+)').exec(stylesSrc) || [])[1] || 0);
            let val = null;
            if (/^\d+$/.test(sp || '')) val = Number(sp);
            else {
                const m = term.exec(sp || '');
                if (m) {
                    const num = m[1] !== undefined ? Number(m[1]) : m[4] !== undefined ? Number(m[4]) : 1;
                    const v = styleInt(m[2] || m[3] || m[5]);
                    if (v) val = num * v;
                }
            }
            if (val !== null && val < 2 * PAD) {
                hits.push({ f, line: g.line, why: '并排的右上角方块 spacing: ' + sp + ' ≈ ' + val
                    + ' —— 两格热区各扩 ' + PAD + ', 间距不足时后画的会压掉前一格边缘' });
            }
        }
    }
}

// --- 判据 2: 组件几何确实引 token, 不写抄本数字 ---
const bandSrc = stripComments(fs.readFileSync(BAND, 'utf8'));
const TOKENS = [
    ['pageHeadH', /(^|[^A-Za-z0-9_.])Layout\.preferredHeight[^\n]*styles\.pageHeadH\b/],
    ['pageHeadBox', /(^|[^A-Za-z0-9_.])width[ \t]*:[ \t]*styles\.pageHeadBox\b/]
];
for (const [tok, use] of TOKENS) {
    if (!new RegExp('readonly[ \t]+property[ \t]+int[ \t]+' + tok + '\\b').test(stylesSrc)) {
        hits.push({ f: STYLES, line: 0, why: 'Styles 里缺 readonly property int ' + tok + ' —— 页头几何的唯一定义点' });
    }
    if (!use.test(bandSrc)) {
        hits.push({ f: BAND, line: 0, why: 'PageHeadBand 没有把 ' + tok + ' 用在 ' + use.source
            + ' 上 —— 组件内部写死数字等于把 13 份抄本合成 1 份抄本' });
    }
}
// 热区外扩必须是 token (44 热区 = 26 盒 + 9 外扩, 抄 9 的人下次改 26 就漏了)
if (!/(^|[^A-Za-z0-9_.])anchors\.margins[ \t]*:[ \t]*-styles\.pageHeadTapPad\b/.test(bandSrc)) {
    hits.push({ f: BAND, line: 0, why: '返回方块热区没走 -styles.pageHeadTapPad —— 热区外扩也不许写死' });
}

// --- 判据 5 (2026-11-04 #42 / 定律 L6-1): band 高度必须 ≥ 三行自然高 ---
//   真机 0.0.7 走查 A 组判 FAIL: 营地页与求助页的微标签上缘 283、band 顶 279，
//   字的上半被切成 8 设备 px。根因是两条叠在一起:
//     ① PageHeadBand 的 Column 是 anchors.bottom 贴底，三行自然高 > pageHeadH(54)，
//        溢出只能往上冒;
//     ② 那两页把 band 放进 `ScrollView/Flickable { clip: true }` (不裁的话末段画进底部
//        导航条)，冒出去的部分就被裁了 —— 其余 9 页同样溢出，只是没有裁剪祖先。
//   判据要的是**形状**而不是"把 54 改成 62": 字号是 Styles 里的活值，
//   写死一个"今天够用的数"下一次改字号还会切。所以必须同时满足:
//     a) Layout.preferredHeight 是 `Math.max(styles.pageHeadH, headCol.implicitHeight)`;
//     b) headCol 这个名字在本文件里确实被声明成某个块的 id —— 否则 a) 读的是一个不存在的
//        对象。这里刻意只查"声明存在", 不查"它挂在那个 Column 上、且中间隔了个换行":
//        按换行写死等于把判据绑在排版格式上, 谁把 `Column {` 和 `id:` 并到一行就会被误判,
//        而挂错对象的写法 (id 给了 Rectangle) 隐式高度算不出来, qml_load_check 会先炸。
//        引用没声明的 id 这类坑 undefined_id_check.js 本该抓, 但它只认几何/可见性属性,
//        读 implicitHeight 不在它的形状表里, 所以这一条在本门禁里自己判。
{
    const h = /(^|[^A-Za-z0-9_.])Layout\.preferredHeight[ \t]*:[ \t]*Math\.max\([ \t]*styles\.pageHeadH[ \t]*,[ \t]*headCol\.implicitHeight[ \t]*\)/;
    if (!h.test(bandSrc)) {
        hits.push({ f: BAND, line: 0, why: '页头条高度没取 max(styles.pageHeadH, headCol.implicitHeight) —— 三行溢出会被带 clip 的视口裁顶 (真机 A 组 FAIL / L6-1)' });
    }
    if (!/(^|[^A-Za-z0-9_.])id[ \t]*:[ \t]*headCol\b/.test(bandSrc)) {
        hits.push({ f: BAND, line: 0, why: '页头条里没有 id: headCol —— max() 里读的是不存在的对象，高度会退回 undefined/0' });
    }
}

// --- 判据 4 兜底: 没有命中、又没有一个实例 = 本门禁没有对象可判 ---
// 顺序要紧: 全树退回抄本时 hits 非空, 必须按 exit 1 报出来 (那是最坏情况), 不能被
// "组件被架空" 的 exit 2 抢先 —— fixture 的 bad_copy 就是钉这个顺序的。
if (bandUses === 0 && hits.length === 0) {
    die2('全树 0 个 PageHeadBand 实例且 0 个页头条形状 (扫描了 ' + scanned + ' 个 qml) —— 本门禁无从判合规');
}

// 判据 6 同样要有"没对象"兜底: 页头带与 10 页 hero 的右上角方块同时被改没形状, 本判据就是
// 空转 —— 一个都不判还能打 0 条, 那是假绿。
if (heroBoxes === 0 && hits.length === 0) {
    die2('全树 0 个右上角方块 (贴右上角 + 自带 width/height + 子树有 IconLabel) —— 判据 6 没有对象可判');
}

console.log('扫描 ' + scanned + ' 个 .qml; PageHeadBand 实例 ' + bandUses + ' 处 / ' + bandFiles + ' 个页文件; '
    + '页头条形状块 ' + shapeBlocks + ' 处, 其中页文件里的手写复制体 ' + pageShape + ' 处; '
    + '右上角方块 ' + heroBoxes + ' 处');
if (VERBOSE) console.log('  token: pageHeadH/pageHeadBox/pageHeadTapPad 已核; 让位手抄判据 anchors.rightMargin:<数字>; 高度判据 max(pageHeadH, headCol.implicitHeight); 右上角方块判据 边长/热区/上边线/右让位/并排间距');
if (VERBOSE) console.log('  右上角方块清单 (' + boxSites.length + ' 处): ' + boxSites.join(' · '));
for (const h of hits) console.log('HIT ' + path.relative(ROOT, h.f) + (h.line ? ':' + h.line : '') + ' — ' + h.why);
console.log('=== L3 页头复制体 / 几何单点 / 让位手抄 / 高度不裁顶 / L13 右上角方块一套几何: 命中 ' + hits.length + ' 处 ===');
process.exit(hits.length ? 1 : 0);
