// int 属性吃字面小数 自检 —— 命中即真机白屏/秒退, 必须 0
//
// 为什么单独一个脚本: qmllint 和 qmlcachegen 都不报这一类.
//   `font.pixelSize: 13.5` 在 Qt 6.7 是**加载期硬错误**
//   ("Invalid property assignment: int expected"), 整棵组件树建不起来,
//   rootObjects 空, app 启动即退. 2026-10-21 真机就是这么炸的
//   (PositionReadout.qml:128, 见 tools/qml_load_check.sh 的说明).
//
// 只打"整值是裸字面小数"的情况. 下面这些一律放过, 因为运行期会被四舍五入, 不是错误:
//   font.pixelSize: styles.fsXs      // real 绑定, 8.5 → 9
//   font.pixelSize: 11.5 * 1         // 表达式走 JS 求值 → int 收窄
//   font.letterSpacing: 1.4          // 本来就是 real
// (实测: 13.5→14, 8.5→9, 12.5→13, Qt 是 round-half-up)
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');

// Qt 里声明成 int 的属性 (写 real 字面量 = 硬错误). 只列本项目会碰到的.
const INT_PROPS = [
    'font.pixelSize', 'font.pointSize', 'maximumLineCount', 'minimumPixelSize',
    'maximumPixelSize', 'font.weight',
    'duration', 'startDelay',                        // 动画: duration/startDelay 是 int
    'interval', 'maximumTicks',
    'maxLength', 'cursorPosition', 'tabStopDistance',
    'cacheBuffer', 'stepSize', 'decimals',
    'Layout.column', 'Layout.row', 'Layout.columnSpan', 'Layout.rowSpan',
];
// 反面对照 (都是 real, 别误加进上面): Layout.preferredWidth/Height、minimumWidth、
// spacing、padding、leftMargin…、font.letterSpacing、font.wordSpacing、lineHeight、opacity
function strip(t) {
    return t.replace(/\/\*[\s\S]*?\*\//g, '')          // 块注释
            .replace(/\/\/[^\n]*/g, '')                // 行注释
            .replace(/"(?:\\.|[^"\\])*"/g, '""')       // 字符串字面量
            .replace(/'(?:\\.|[^'\\])*'/g, "''");
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

const propRe = new RegExp('(?:^|[\\s{,])(' +
    INT_PROPS.map(p => p.replace('.', '\\.')).join('|') +
    ')\\s*:\\s*([-.+0-9eE_a-zA-Z]+)\\s*(?=$|[;,\\n})])', 'gm');

const hits = [];
for (const f of walk(ROOT, [])) {
    const src = fs.readFileSync(f, 'utf8');
    const raw = strip(src);
    for (const m of raw.matchAll(propRe)) {
        const val = m[2];
        const n = Number(val);
        // 只报"值本身带小数"的字面量. 2.0 / 1e3 这类整值 Qt 收得下, 放过;
        // NaN (如 1e 这种被字符类吃进来的残片) 也放过, 那是语法问题不归这里管.
        if (!Number.isFinite(n) || Number.isInteger(n)) continue;
        const line = raw.slice(0, m.index).split('\n').length;
        hits.push([path.relative(ROOT, f), line, m[1].trim() + ': ' + val]);
    }
}
console.log('=== int 属性写了字面小数 (加载期硬错误): ' + hits.length + ' 处 ===');
for (const [f, l, t] of hits) console.log(f + ':' + l + '  ' + t);
if (hits.length) console.log('改法: 换成整数 (Qt 是 round-half-up, 13.5 实际渲染 14), 或绑到 styles 的 real token.');
process.exit(hits.length ? 1 : 0);
