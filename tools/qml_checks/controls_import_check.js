// 裸 `import QtQuick.Controls` 自检: 全工程只允许 import 带 style 后缀的那一个。
//
// 为什么必须有这道门禁 (2026-10-23 真机「我」页整页空白):
//   androiddeployqt 只把 APK 里**真正被 import 到**的 QML 插件塞进去. 本项目的基座
//   是 Material style, 所以打进去的是 qml_QtQuick_Controls_Material_* 和 impl 那几个,
//   **裸 `QtQuick.Controls` 的 qtquickcontrols2plugin 不在包里**. 这行 import 在桌面
//   上跑得通 (Qt 装了完整模块), 到真机上就是
//     StackView: push: MePage.qml:17 module "QtQuick.Controls" plugin
//     "qml_QtQuick_Controls_qtquickcontrols2plugin" not found
//   —— push 不出对象, 页体一句不画, 而且 release 包 logcat 全空, 只落 app 沙盒的
//   stage0.log. 现场看不出来, 只能靠这道静态门禁.
//
//   其余 34 处只 import `QtQuick.Controls.Material` 就够用: Material 的 qmldir 里
//   逐个列了 Page / ScrollView / Switch / Dialog 这些类型, 不需要基座插件.
//   所以修法是把那行裸 import 删掉, 不是给 APK 多塞一个 12KB 插件.
//
// 判读: 期望 0 条。非 0 = 该文件在真机上必然整页(或整块)画空.
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');

// 行首可选缩进的 import, 模块名正好是 QtQuick.Controls (后面不跟 `.`), 版本号可有可无。
const BARE = /^[ \t]*import[ \t]+QtQuick\.Controls(?![.\w])([ \t]+[\d.]+)?[ \t]*$/gm;

function walk(d, out) {
    if (!fs.existsSync(d)) return out;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.qml')) out.push(p);
    }
    return out;
}
// 注释和字符串换成等量空白, **保留换行** —— 否则报出来的行号对不上文件,
// 而且讲解这条坑的注释本身会被当成违规 import 报出来 (MePage.qml 就是这种注释)。
function blank(t) {
    return t.replace(/\/\*[\s\S]*?\*\//g, m => m.replace(/[^\n]/g, ' '))
            .replace(/\/\/[^\n]*/g, m => ' '.repeat(m.length))
            .replace(/'(\\.|[^'\\])*'|"(\\.|[^"\\])*"/g, m => ' '.repeat(m.length));
}

const hits = [];
for (const f of walk(ROOT, [])) {
    const t = blank(fs.readFileSync(f, 'utf8'));
    for (const m of t.matchAll(BARE)) {
        hits.push([path.relative(ROOT, f), t.slice(0, m.index).split('\n').length, m[0].trim()]);
    }
}
console.log('=== 裸 import QtQuick.Controls (真机上插件必然缺失): ' + hits.length + ' 处 ===');
for (const [f, l, s] of hits) console.log(f + ':' + l + '  `' + s + '` -> 删掉这行, 类型走 QtQuick.Controls.Material');
process.exit(hits.length ? 1 : 0);
