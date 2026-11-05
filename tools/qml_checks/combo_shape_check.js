// L14 门禁: C++ 返回列表跨到 QML 是「包装列表」，判形态必须认 .length，不许只问 Array.isArray
// （2026-11-04 #48，真机 0.0.7 F1-2 + 当晚容器量实）
//
// 事实（不是推测，两条 ctest 槽各打一遍，见 tests/unit/test_common_options.cpp 的
//   cpp_qvariantlist_is_wrapped_not_js_array_in_qml / cpp_stringlist_is_wrapped_not_js_array_in_qml）：
//   Q_INVOKABLE QVariantList / QStringList 到了 QML 的 var 里 ——
//     typeof = 'object'   Array.isArray() = false   .count / .get = undefined
//     .length ✓   [i] ✓   [i].key ✓   indexOf() ✓   join() ✓   每次调用返回一个新对象
//   所以「是不是 JS 数组」和「能不能按行取数」是两件不同的事，用前者当唯一判据必错。
//
// 现场：FilterRow.comboRowCount 原来写 `Array.isArray(comboModel) ? comboModel.length : 0`，
//   包装列表两支都不认 → 行数 0 → textForRow 的 `if (n <= 0) return ""` → displayText 空。
//   图鉴页月份框整块空白（真机 F1-2），而同一文件上面的注释早就写了「QStringList 走 length」——
//   口径对、代码错。同一族第二处：SearchTab 的 `Array.isArray(provinces) ? indexOf : -1` 恒 -1。
//   而 FieldGuideDetailPage / KnotDetailPage 的 _toArr() 从 2026-09-19 起就认 .length，
//   所以那两页一直好好的 —— 定律早就在代码里，只是没有门禁，两个月后在新组件里漂回去了。
//
// 四条判据：
//   ① FilterRow.comboRowCount 必须同时读 comboModel.count 与 comboModel.length（ListModel 走
//      count，包装列表 / JS 数组都有 length），且这一支里不许再出现 Array.isArray。
//   ② 全树禁 `Array.isArray(x) ? <任意> : <常量>` —— 假分支写成 -1/0/false/null/""/[] 这类字面量，
//      说明"不是 JS 数组"被当成了"没有数据"。假分支是函数调用或成员访问则放行（归一器形状）。
//   ③ 凡定义 `function _toArr(` 的文件，函数体必须出现 `.length`（归一器必须认包装列表；
//      哪天有人把它"简化"成纯 Array.isArray，第二支会静默返回 []，整页列表画空）。
//   ④ 家底打印：.qml 文件数 / comboModel: 站点数 / _toArr 定义数 / Array.isArray 出现数。
//      comboModel 站点数为 0 或 FilterRow.qml 读不到 → exit 2，绝不静默报「0 条」。
//
// exit 0 干净 / 1 命中 / 2 门禁没跑起来。用法：node combo_shape_check.js [qml根目录]
// （一律不传参数，默认根 = ../../qml；传 Windows 看不懂的 /d/... 路径会静默 0 条，见同目录 README）
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
// 从 openIdx 处的 '(' 走到配对的 ')'，返回 [openIdx, closeIdx]
function parenRange(text, openIdx) {
    let d = 0;
    for (let i = openIdx; i < text.length; i++) {
        if (text[i] === '(') d++;
        else if (text[i] === ')') { d--; if (d === 0) return [openIdx, i]; }
    }
    return [openIdx, text.length - 1];
}
// 从 '{' 走到配对的 '}'
function braceRange(text, openIdx) {
    let d = 0;
    for (let i = openIdx; i < text.length; i++) {
        if (text[i] === '{') d++;
        else if (text[i] === '}') { d--; if (d === 0) return [openIdx, i]; }
    }
    return [openIdx, text.length - 1];
}
const isConstantExpr = (s) => /^[\s()]*(-?\d+(?:\.\d+)?|true|false|null|undefined|''|""|\[\]|\{\})[\s;]*$/.test(s);

const files = walk(QML, []);
if (files.length === 0) { console.error('qml 根目录下没有 .qml: ' + QML); process.exit(2); }

const hits = [];
let comboSites = 0, toArrDefs = 0, isArraySites = 0;

// ---- ① FilterRow.comboRowCount 的形态判据 ----------------------------------
const filterRowPath = path.join(QML, 'components', 'base', 'FilterRow.qml');
if (!fs.existsSync(filterRowPath)) {
    console.error('读不到 FilterRow.qml: ' + filterRowPath);
    process.exit(2);
}
{
    const raw = stripComments(fs.readFileSync(filterRowPath, 'utf8'));
    const m = raw.match(/property\s+int\s+comboRowCount\s*:([\s\S]*?)\n[ \t]*property\s/);
    if (!m) {
        console.error('FilterRow.qml 里找不到 comboRowCount 表达式，门禁没有判据对象');
        process.exit(2);
    }
    const expr = m[1];
    const rel = path.relative(QML, filterRowPath).replace(/\\/g, '/');
    if (!/comboModel\.count\s*!==\s*undefined/.test(expr)) {
        hits.push(`${rel}: comboRowCount 不认 ListModel 的 .count (A43 那一族会复发)`);
    }
    if (!/comboModel\.length\s*!==\s*undefined/.test(expr)) {
        hits.push(`${rel}: comboRowCount 不认包装列表 / JS 数组的 .length —— F1-2 原样 (Array.isArray 认不出 QStringList)`);
    }
    if (/Array\.isArray\s*\(\s*comboModel\s*\)/.test(expr)) {
        hits.push(`${rel}: comboRowCount 用 Array.isArray 判形态 (C++ 返回列表恒 false)`);
    }
}

// ---- ②③④ 全树 -------------------------------------------------------------
for (const f of files) {
    const rel = path.relative(QML, f).replace(/\\/g, '/');
    const raw = stripComments(fs.readFileSync(f, 'utf8'));

    comboSites += (raw.match(/comboModel\s*:/g) || []).length;

    // ② Array.isArray(x) ? … : <常量>
    let idx = -1;
    while ((idx = raw.indexOf('Array.isArray(', idx + 1)) !== -1) {
        isArraySites++;
        const open = idx + 'Array.isArray'.length;
        const [, close] = parenRange(raw, open);
        // 条件右括号后**紧跟** '?' 才是三元判据；`if (Array.isArray(v)) return v` 是早退，放行。
        // 这里不能拿「后面第一个 ?」当分界 —— SearchTab 改前那句的下一个 '?' 在下一条语句
        // (`return i > 0 ? i : 0`) 里，那样会整条漏检（fixture 逼出来的）。
        const after = raw.slice(close + 1);
        const qm = /^\s*\?/.exec(after);
        if (!qm) continue;
        const s = after.slice(qm[0].length);
        // 真分支：扫到本层（深度 0）的第一个 ':'
        let depth = 0, ti = -1;
        for (let i = 0; i < s.length && i < 2000; i++) {
            const c = s[i];
            if (c === '(' || c === '[' || c === '{') depth++;
            else if (c === ')' || c === ']' || c === '}') { if (depth === 0) break; depth--; }
            else if (c === ':' && depth === 0) { ti = i; break; }
        }
        if (ti < 0) continue;
        // 假分支：截到本层的语句结束符（; , 换行 或 闭合括号）
        const rest = s.slice(ti + 1);
        depth = 0;
        let end = rest.length;
        for (let i = 0; i < rest.length && i < 200; i++) {
            const c = rest[i];
            if (c === '(' || c === '[' || c === '{') depth++;
            else if (c === ')' || c === ']' || c === '}') { if (depth === 0) { end = i; break; } depth--; }
            else if ((c === ';' || c === ',' || c === '\n') && depth === 0) { end = i; break; }
        }
        const falseBranch = rest.slice(0, end).trim();
        if (isConstantExpr(falseBranch)) {
            hits.push(`${rel}:${lineOf(raw, idx)}: Array.isArray(...) ? … : 常量 (${falseBranch}) —— `
                    + `包装列表不是 JS 数组，这一支会把有数据读成没数据`);
        }
    }

    // ③ _toArr 归一器必须认 .length
    let d = -1;
    while ((d = raw.indexOf('function _toArr(', d + 1)) !== -1) {
        toArrDefs++;
        const brace = raw.indexOf('{', raw.indexOf(')', d));
        if (brace < 0) continue;
        const [a, b] = braceRange(raw, brace);
        if (!/\.length/.test(raw.slice(a, b))) {
            hits.push(`${rel}:${lineOf(raw, d)}: _toArr() 不读 .length —— 包装列表会被归一成 []`);
        }
    }
}

if (comboSites === 0) {
    console.error('全树 0 处 comboModel: 站点，门禁没有判据对象（扫描根是不是给错了？）');
    process.exit(2);
}

console.log(`扫描 ${files.length} 个 .qml | comboModel 站点 ${comboSites} | _toArr 定义 ${toArrDefs} | Array.isArray 出现 ${isArraySites}`);
if (hits.length === 0) {
    console.log('✅ 定律 L14 成立: 列表形态判据都认包装列表 (.length)');
    process.exit(0);
}
for (const h of hits) console.log('❌ ' + h);
console.log(`命中 ${hits.length} 处`);
process.exit(1);
