// 模块单例引用自检: 用了 CommonOptions / App / ImageColorExtractor 却没写
// `import OutdoorSurvival 1.0` 的文件。
//
// 为什么必须有这道门禁: 这三个是 qmlRegisterSingletonInstance 注册的**模块单例**,
// 不是 setContextProperty 注入的上下文属性 (xxxService / styles 才是, 见
// src/services/ServiceRegistry.cpp)。单例必须在文件里 import 模块才可见 ——
// 少了这行, qmllint / qmlcachegen / ctest 全都不报, 真机上每次绑定求值都吐
// "ReferenceError: CommonOptions is not defined", 而且是**静默**画空:
// 2026-10-21 真机巡检就是靠这个才暴露出全站图标 100% 方框 (IconLabel 拿不到
// iconFontReady, 字体永远不切到 Material Icons) 和绳结难度梯整体变黑 (Ladder 拿不到色)。
//
// 判读: 期望 0 条。非 0 = 该文件在真机上对应绑定必然抛 ReferenceError。
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');

// 只有这三个是模块单例。新增单例时改这里 (注册点见 src/main.cpp 与 CommonOptions.cpp)。
const SINGLETONS = ['CommonOptions', 'App', 'ImageColorExtractor'];

function walk(d, out) {
    if (!fs.existsSync(d)) return out;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.qml')) out.push(p);
    }
    return out;
}
// 注释和字符串换成等量空白, **保留换行** —— 否则报出来的行号对不上文件。
function blank(t) {
    return t.replace(/\/\*[\s\S]*?\*\//g, m => m.replace(/[^\n]/g, ' '))
            .replace(/\/\/[^\n]*/g, m => ' '.repeat(m.length))
            .replace(/'(\\.|[^'\\])*'|"(\\.|[^"\\])*"/g, m => ' '.repeat(m.length));
}

const hits = [];
for (const f of walk(ROOT, [])) {
    const raw = fs.readFileSync(f, 'utf8');
    const t = blank(raw);
    // 属性定义名恰好叫 CommonOptions 之类不算引用; 只查 `<单例>.` 这种成员访问。
    const used = SINGLETONS.filter(s => new RegExp('(^|[^\\w.$])' + s + '\\s*\\.', 'g').test(t));
    if (!used.length) continue;
    if (/^import\s+OutdoorSurvival\b/m.test(t)) continue;
    // 行号要在**已挖空**的文本上找 —— 在原文上找会先撞上注释里的提及。
    const line = t.slice(0, t.search(new RegExp('(^|[^\\w.$])' + used[0] + '\\s*\\.')) + 1).split('\n').length;
    hits.push([path.relative(ROOT, f), line, used.join(',')]);
}
console.log('=== 引用模块单例但缺 import OutdoorSurvival 的文件: ' + hits.length + ' 个 ===');
for (const [f, l, u] of hits) console.log(f + ':' + l + '  用到 ' + u + ' -> 需要 import OutdoorSurvival 1.0');
process.exit(hits.length ? 1 : 0);
