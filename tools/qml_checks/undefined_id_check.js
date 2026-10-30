// 悬空 id 引用自检 (2026-10-23 #113 加)
//
// 为什么单独一道: crossfile_id_check.js 只报"这个名字在**别的文件**里有 id"的情况,
// 判定条件是 `if (!idOwner.has(id)) continue` —— 全工程查无此名的, 它直接放过.
// 于是 FieldGuideDetailPage 里那句 `implicitHeight: markRowCol.implicitHeight + ...`
// (markRowCol 从来没被声明过) 一路活到真机: 绑定求值即抛 ReferenceError,
// implicitHeight 停在 Rectangle 默认的 0, 46 行标注全塌成 0 高叠成一团黑字.
// release 包 logcat 全空, 这条错误只在 app 沙盒的 stage0.log 里 —— 门禁不抓就没人抓.
//
// 口径: 只认"小写名字 + . + 属性/方法"的形状, 先把本文件能起名的位置 (id / property /
// var / 函数·信号形参 / lambda 形参 / catch 形参 / for-in) 收齐, 再扣掉 C++ 侧
// setContextProperty 注入的服务名和 Qt 自带的全局名. 剩下的就是嫌疑.
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');
const SRC = process.argv[3] || path.resolve(__dirname, '../../src');

// 口径: 只看"几何/可见性"这一类属性前挂的名字 —— 因为绑定悬空 id 的杀伤力正好在这
// 几个属性上 (implicitHeight 停在默认值 → 整块塌成 0 高; visible 停在 false → 整块不见).
// 其余形状 (mn.push / border.color / legend.visible) 大量是 QML 的分组属性和"不写前缀
// 访问本类型自带属性", 静态扫不出来, 收进来只会把真问题埋掉.
const GEOMETRY = /^(implicitHeight|implicitWidth|height|width|x|y|visible|enabled|anchors|contentHeight|contentWidth|childrenRect|spacing|opacity|Layout)$/;

// Qt 自带的非声明式名字 + QML 引擎注入的上下文 (delegate 里的 model/index、
// 事件处理器里的 mouse/event/point 等). 这些不可能被本文件"声明", 必须白名单.
const GLOBAL = new Set([
    'Qt', 'Math', 'JSON', 'Date', 'console', 'Application', 'ApplicationWindow',
    'matrix4x4', 'quaternion4x4', 'vector2d', 'vector3d', 'vector4d',
    'color', 'real', 'int', 'string', 'var', 'url', 'point', 'size', 'rect',
    'font', 'image', 'list', 'date', 'time', 'datetime', 'value',
    'parent', 'children', 'child', 'contentItem', 'background', 'backgroundItem',
    'footer', 'header', 'overlay', 'window', 'application', 'screen', 'style',
    'palette', 'material', 'im', 'inputMethod', 'displayText', 'accessible',
    'index', 'model', 'delegate', 'section', 'root', 'item', 'items',
    'mouse', 'event', 'handler', 'button', 'modifiers', 'keys', 'e', 'err',
    'this', 'arguments', 'undefined', 'null', 'true', 'false',
    // QML 的分组属性 (border/anchors/line) 和"不写前缀访问本类型自带属性"
    // (TapHandler.anchorPoint、DragHandler.translation、ChartView.legend、
    //  ShapePath.line) —— 静态扫不出声明处, 收进来只会淹掉真命中.
    // xAxis/yAxis 同理: DragHandler 的轴分组 (xAxis.enabled / yAxis.enabled),
    //   LineProfile 的横向拖动 2026-10-29 起用到, 当时被误报成悬空 id.
    'border', 'line', 'legend', 'translation', 'anchorPoint', 'xAxis', 'yAxis',
    'activeTouchPoints', 'centroid', 'supportedMapTypes', 'activeMapType', 'plugin',
]);

function walkJs(d, ext, out) {
    if (!fs.existsSync(d)) return out;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walkJs(p, ext, out);
        else if (ext.some(x => e.name.endsWith(x))) out.push(p);
    }
    return out;
}

// 注释与字符串里的名字是噪音; 换行原样留着, 否则报出来的行号会整体上跳.
function strip(t) {
    const blank = m => m.replace(/[^\n]/g, ' ');
    return t.replace(/\/\*[\s\S]*?\*\//g, blank)
            .replace(/\/\/[^\n]*/g, '')
            .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
            .replace(/'(?:[^'\\\n]|\\.)*'/g, "''");
}

// C++ 侧 setContextProperty("mapService", ...) 注入的名字 —— 扫源码, 不写死清单,
// 以后加服务不用回来改这道门禁.
function contextNames() {
    const s = new Set();
    for (const f of walkJs(SRC, ['.cpp', '.h'], [])) {
        const t = fs.readFileSync(f, 'utf8');
        for (const m of t.matchAll(/setContextProperty\s*\(\s*"([A-Za-z_]\w*)"/g)) s.add(m[1]);
        for (const m of t.matchAll(/qmlRegister\w+\s*<[^>]*>\s*\(\s*"[^"]*"\s*,[^,]*,[^,]*,\s*"([A-Za-z_]\w*)"/g)) s.add(m[1]);
    }
    return s;
}

// 本文件里所有"自己起的名"
function localNames(t) {
    const s = new Set();
    for (const m of t.matchAll(/\bid\s*:\s*([A-Za-z_]\w*)/g)) s.add(m[1]);
    for (const m of t.matchAll(/\bproperty\s+(?:readonly\s+)?[A-Za-z_][\w<>?.]*\s+([A-Za-z_]\w*)/g)) s.add(m[1]);
    for (const m of t.matchAll(/\bproperty\s+([A-Za-z_]\w*)\s*:/g)) s.add(m[1]);
    for (const m of t.matchAll(/\b(?:var|let|const)\s+([A-Za-z_]\w*)/g)) s.add(m[1]);
    // function name(a, b) / function (a, b) / signal foo(int a, string b)
    for (const m of t.matchAll(/(?:function|signal)\s*(?:[A-Za-z_]\w*)?\s*\(([^)]*)\)/g)) {
        for (const p of m[1].split(',')) {
            const bits = p.trim().split(/\s+/);
            const name = bits.length ? bits[bits.length - 1] : '';
            if (/^[A-Za-z_]\w*$/.test(name)) s.add(name);
        }
    }
    // lambda: (a, b) => … / a => …
    for (const m of t.matchAll(/\(([^()]*)\)\s*=>/g)) {
        for (const p of m[1].split(',')) {
            const name = p.trim().split(/\s+/)[0];
            if (/^[A-Za-z_]\w*$/.test(name)) s.add(name);
        }
    }
    for (const m of t.matchAll(/(?:^|[^\w.])([A-Za-z_]\w*)\s*=>/g)) s.add(m[1]);    for (const m of t.matchAll(/catch\s*\(\s*([A-Za-z_]\w*)/g)) s.add(m[1]);
    for (const m of t.matchAll(/for\s*\(\s*(?:var\s+|let\s+)?([A-Za-z_]\w*)\s+in/g)) s.add(m[1]);
    // 解构: var { a, b } = …
    for (const m of t.matchAll(/[{[]\s*([A-Za-z_]\w*)/g)) s.add(m[1]);
    return s;
}

const ctx = contextNames();
for (const n of ctx) GLOBAL.add(n);

const files = walkJs(ROOT, ['.qml'], []);
// 全工程声明过的 id —— 一次算完, 别在匹配循环里反复读盘
const allIds = new Set();
for (const f of files) {
    const t = strip(fs.readFileSync(f, 'utf8'));
    for (const m of t.matchAll(/\bid\s*:\s*([A-Za-z_]\w*)/g)) allIds.add(m[1]);
}
let n = 0;
for (const f of files) {
    const t = strip(fs.readFileSync(f, 'utf8'));
    const locals = localNames(t);
    const seen = new Map();
    for (const m of t.matchAll(/(^|[^\w.$])([a-z]\w*)\s*\.\s*([A-Za-z_]\w*)/g)) {
        const id = m[2], prop = m[3];
        if (!GEOMETRY.test(prop)) continue;
        if (GLOBAL.has(id) || locals.has(id)) continue;
        // 只报"全工程没有任何文件把它当 id 声明过"的 —— 别人的 id 归
        // crossfile_id_check.js 管, 两道门禁各查各的, 报错信息不重叠.
        if (allIds.has(id)) continue;
        const line = t.slice(0, m.index).split('\n').length;
        if (!seen.has(id)) seen.set(id, line + '|' + m[0].trim());
    }
    for (const [id, hit] of seen) {
        const [line, snippet] = hit.split('|');
        console.log(path.relative(ROOT, f) + ':' + line + '  "' + id + '" 本文件没声明、'
            + '全工程也没有同名 id、也不在上下文服务/Qt 全局里 —— ' + snippet);
        n++;
    }
}
console.log('=== 悬空 id 引用 ' + n + ' 处 ===');
process.exit(n ? 1 : 0);
