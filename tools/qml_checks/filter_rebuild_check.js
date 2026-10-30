// 筛选器改了状态但列表不重算 (2026-10-27 A36 加)
//
// 真机现场: 急救页点「环境急症 3」, chip 变成选中态 (墨底), 下面 35 条一行没少。
// 根因不是筛选写错了, 而是筛选状态**没人重算**: rows 是 reload() 里命令式赋值的
// (`property var rows: []` + `ListView { model: page.rows }`), 而 reload() 只挂在
// Component.onCompleted 和 service.dataChanged 上 —— chip 的 onClicked 只写
// currentCategory, 既没有 onCurrentCategoryChanged, 也没有顺手调 reload()。
// 同一份复制体在 急救 / 绳结 / 野外生活 三页各一份 (2026-10-27 逐页排查)。
//
// 为什么 qmllint / 其余 13 道门禁抓不到: 代码本身完全合法, 属性名对、类型对、
// 作用域对。缺的是"谁在状态变化时被叫起来"这条运行期链路, 静态上只有从
// "写" 追到 "读" 再追到 "赋值给 model 用的属性" 才看得出来。
//
// 口径 (只认这一条链, 别的都不报):
//   1) P 是根对象上声明的 property;
//   2) P 在**输入处理器** (onClicked / onActivated / onComboActivated / onToggled /
//      onAccepted / onTextChanged / onStepper* / onValueChanged 之类) 里被赋值;
//   3) 存在函数 F, F 的函数体里读了 P, 且 F 给一个"喂给 model: 的属性"赋了值
//      (= 这一页的列表确实是在 F 里命令式拼出来的, 不是声明式绑定);
//   4) 那么必须满足其一, 否则报:
//      a. 本文件有 `on<P>Changed:` 处理器;
//      b. 那个写 P 的处理器自己也调了 F (显式提交式, 同一条语句里重算)。
//
// 已知不覆盖的: 声明式绑定 (`model: page.filtered` 且 filtered 是 readonly 内联求值)
// 本来就会自动重算, 第 3 步就把它排除了; 只写进函数但函数不给 model 属性赋值的
// (读数缓存一类) 也不报 —— 那类漏触发要另用真机 stage0.log 判。
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');

// 显式提交式设计, 不是漏触发: 选完条件要按「搜索」才查库。
// 加豁免必须写清理由, 且只按文件豁免, 不要退化成全局关掉。
const EXEMPT = {
    'pages/MapPageComponents/SearchTab.qml':
        '显式提交式搜索: 省份/难度选完要按「搜索」按钮才生效, 是设计不是漏触发',
};

function walk(d, out) {
    if (!fs.existsSync(d)) return out;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.qml')) out.push(p);
    }
    return out;
}

// 注释与字符串换成等量空白 (行号不能移位), 否则文案里的 "onClicked" / 属性名会误报。
function strip(t) {
    const blank = m => m.replace(/[^\n]/g, ' ');
    return t.replace(/\/\*[\s\S]*?\*\//g, blank)
            .replace(/\/\/[^\n]*/g, blank)
            .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
            .replace(/'(?:[^'\\\n]|\\.)*'/g, "''");
}

// 逐字符扫花括号, 记录每个偏移的嵌套深度 (深度 1 = 根对象体内; `{` 自身已经算进去)。
function depthOf(t) {
    const d = new Int32Array(t.length + 1);
    let dep = 0;
    for (let i = 0; i < t.length; i++) {
        if (t[i] === '{') dep++;
        else if (t[i] === '}') dep--;
        d[i] = Math.max(dep, 0);
    }
    d[t.length] = 0;
    return d;
}

function matchBrace(t, open) {
    let dep = 0;
    for (let i = open; i < t.length; i++) {
        if (t[i] === '{') dep++;
        else if (t[i] === '}') { dep--; if (dep === 0) return i; }
    }
    return t.length - 1;
}

const INPUT_RE = /\b(onClicked|onDoubleClicked|onPressed|onReleased|onAccepted|onTextChanged|onEditingFinished|onActivated|onHighlighted|onComboActivated|onStepperMinus|onStepperPlus|onToggled|onCheckedChanged|onValueChanged|onCommit)\s*:/g;

let n = 0;
for (const f of walk(ROOT, [])) {
    const rel = path.relative(ROOT, f).replace(/\\/g, '/');
    if (EXEMPT[rel]) continue;
    const t = strip(fs.readFileSync(f, 'utf8'));
    const dep = depthOf(t);

    // 根对象的 id (写属性时常见 `pageId.foo = x`, 要认这个前缀)
    let rootId = '';
    const rid = t.match(/\bid\s*:\s*([A-Za-z_]\w*)/);
    if (rid && dep[rid.index] === 1) rootId = rid[1];

    // 根上声明的 property
    const props = new Set();
    for (const m of t.matchAll(/\bproperty\s+(?:readonly\s+)?[A-Za-z_][\w<>?.]*\s+([A-Za-z_]\w*)\s*:/g))
        if (dep[m.index] === 1) props.add(m[1]);
    if (!props.size) continue;

    // 函数体范围
    const fns = [];
    for (const m of t.matchAll(/\bfunction\s+([A-Za-z_]\w*)\s*\(/g)) {
        const open = t.indexOf('{', t.indexOf(')', m.index));
        if (open < 0) continue;
        fns.push({ name: m[1], start: open, end: matchBrace(t, open) });
    }
    const bodyOf = fn => t.slice(fn.start, fn.end + 1);

    // 喂给 model: 的属性 (命令式拼列表的那一个)
    const modelProps = new Set();
    for (const m of t.matchAll(/\bmodel\s*:\s*([^\n]*)/g)) {
        for (const p of props)
            if (new RegExp('(^|[.\\s(])(' + rootId + '\\.)?' + p + '\\b').test(m[1]))
                modelProps.add(p);
    }
    if (!modelProps.size) continue;

    // 重建函数: 函数体里给 modelProps 里的某个属性赋值
    const rebuild = [];
    for (const fn of fns) {
        const b = bodyOf(fn);
        let isRebuild = false;
        for (const p of modelProps)
            if (new RegExp('(^|[.\\s;{])((' + rootId + '\\.)?' + p + ')\\s*=[^=]').test(b))
                isRebuild = true;
        if (isRebuild) rebuild.push(fn);
    }
    if (!rebuild.length) continue;

    // 输入处理器范围 (带花括号的取块, 不带花括号的取到行尾)
    const handlers = [];
    INPUT_RE.lastIndex = 0;
    for (const m of t.matchAll(INPUT_RE)) {
        const colon = m.index + m[0].length - 1;
        const open = t.indexOf('{', colon);
        if (open < 0) continue;
        const nl = t.indexOf('\n', colon);
        if (t.slice(colon + 1, open).trim().length === 0 || (nl >= 0 && open < nl))
            handlers.push({ start: open, end: matchBrace(t, open) });
        else
            handlers.push({ start: colon + 1, end: nl < 0 ? t.length : nl });
    }

    const seen = new Set();
    for (const p of props) {
        // 只查"确实被某个重建函数**读**"的属性。赋值左值不算读: RouteDetailPage 的
        // `_load()` 里那句 `entity = routeService.getById(...)` 是取数, 不是按 entity
        // 分支, 把它当读会误报成"改了 entity 没人重算"。
        const asgnRe = new RegExp('(^|[.;{\\s])(' + rootId + '\\.)?' + p + '\\s*=[^=]', 'g');
        const readers = rebuild.filter(fn => bodyOf(fn).replace(asgnRe, '$1 ').match(
            new RegExp('(^|[^\\w.$])' + p + '\\b')));
        if (!readers.length) continue;
        const hasChanged =
            new RegExp('\\bon' + p[0].toUpperCase() + p.slice(1) + 'Changed\\s*:').test(t);
        if (hasChanged) continue;

        const writeRe = new RegExp('(^|[.\\s;{=(])(' + rootId + '\\.)?' + p + '\\s*=[^=]');
        for (const h of handlers) {
            const body = t.slice(h.start, h.end + 1);
            if (!writeRe.test(body)) continue;
            // 处理器自己就调了重建函数 = 显式提交, 算合法
            if (readers.some(fn => new RegExp('\\b' + fn.name + '\\s*\\(').test(body))) continue;
            const line = t.slice(0, h.start).split('\n').length;
            const key = p + ':' + line;
            if (seen.has(key)) continue;
            seen.add(key);
            console.log(rel + ':' + line + '  输入处理器写了 `' + p + '`, 而列表是在 '
                + readers.map(r => r.name + '()').join('/') + ' 里命令式赋值的 —— '
                + '本文件既没有 on' + p[0].toUpperCase() + p.slice(1)
                + 'Changed, 处理器也没调它, 所以点了筛选器列表不会重算');
            n++;
        }
    }
}
console.log('=== 筛选器改了状态但列表不重算 ' + n + ' 处 ===');
process.exit(n ? 1 : 0);
