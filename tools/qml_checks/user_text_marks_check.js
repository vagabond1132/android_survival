// L12 门禁: 面向用户的文案里不许出现内部记号 (2026-11-03 #37 定律化, 真机 pass 2 F3/L12)
// 规则: 只查"会画到屏上"的字符串属性 (text / placeholderText / hint / subtitle / title /
//       actionText / description / emptyHint / label / holdLabel / confirmLabel);
//       注释与 console.log 一律不算 —— 注释先换成等量空白, 所以讲解这条坑的注释本身不误报。
//       属性值可以是三元/拼接表达式, 所以把整条语句里的**字符串字面量**逐个取出来判定。
// 禁用形态 (逐条都有真机现场, 见 讨论记录 12 §4.25):
//   1 圈号 ①-⑳ —— 「添加之后, ⑤求助页长按触发 SOS」把内部反馈编号直接上线
//   2 占位名 XX —— 「审核: XX(植物学)」(数据侧 696 条已由 tools/strip_fake_reviewer.js 清掉)
//   3 HSV 开发者口径 H50 S80 V70 —— 物种详情"代表色"那一行
//   4 内部口径词 本库/库里/决策树/读数/急教 —— 「本库无操作图示」「这条没有决策树」「急教读数」
//   5 数据表名与内部键名 (snake_case / entryId=) —— 急救决策页空态 hint 直接把
//     「firstaid_decision_nodes」与「entryId=」印在屏上, 用户读不到任何信息
// 命中 exit 1; qml 目录找不到 = 门禁没跑起来, exit 2, 绝不静默 0 条。
const fs = require('fs'), path = require('path');

const QML = process.argv[2] || path.resolve(__dirname, '../../qml');
if (!fs.existsSync(QML)) {
    console.error('找不到 qml 目录: ' + QML + ' (门禁未运行, 判 exit 2)');
    process.exit(2);
}

// 六条 ban, 每条自带 hanOnly 开关 (要不要只在含汉字的字面量里判):
//   表名与内部键名与语言无关。原先所有判据都挂在"字面量里有汉字"这个前置条件下,
//   于是 hint: "entryId=" 这种纯 ASCII 的内部键名整类漏过 —— 门禁安静地少查一类,
//   比不写更危险, 所以把前置条件收进每条 ban 自己。
const BANS = [
    ['圈号内部编号', /[①-⑳⒈-⒙]/, false],
    ['占位名 XX',    /(^|[^A-Za-z])XX([^A-Za-z]|$)/, false],
    ['HSV 口径',     /\bH\d+\s*S\d+\s*V\d+\b/, false],
    ['数据表名',     /[a-z]+(?:_[a-z]+){2,}/, false],
    ['内部键名',     /[A-Za-z]+Id\s*=/, false],
    ['内部口径词',   /本库|库里|决策树|急教|读数/, true],
];

function stripComments(t) {
    return t.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
            .replace(/\/\/[^\n]*/g, (m) => ' '.repeat(m.length));
}
function walk(d, out) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.qml')) out.push(p);
    }
    return out;
}
function literals(s) {
    const out = [];
    // 本仓的文案里没有转义引号 (要引号用「」), 所以按 " 到行尾取就行 —— 写成 [^"\\n] 会被
    // heredoc 吃掉一层反斜杠, 变成"排除反斜杠和字母 n", 靠后面的 \. 兜住才没漏检。
    const re = /"([^"\n]*)"/g;
    for (let m = re.exec(s); m; m = re.exec(s)) out.push(m[1]);
    return out;
}
// 从属性行起收到整条语句。两种续行都得吃进来, 否则三元里的第二支永远查不到:
//   1 括号/花括号没闭合 (拼接函数调用)
//   2 行首是 ? : + || && (本仓文案大量写成 decisionPage.x ? "…" : "…" 跨行排)
//      FirstAidDecisionPage:427 那句 "这个结论节点在库里没有写处理动作" 就是这么漏掉的。
function statement(lines, i, first) {
    let s = first === undefined ? lines[i] : first, depth = 0, j = i;
    for (const c of s) { if (c === '(' || c === '{') depth++; else if (c === ')' || c === '}') depth--; }
    for (;;) {
        if (j + 1 >= lines.length) break;
        const nxt = lines[j + 1];
        const cont = depth > 0 || /^\s*[?:+|&]/.test(nxt) || /[?:+|&]\s*$/.test(s);
        if (!cont) break;
        j++;
        s += '\n' + nxt;
        for (const c of nxt) { if (c === '(' || c === '{') depth++; else if (c === ')' || c === '}') depth--; }
    }
    return s;
}

// 属性名前面允许 行首 / { / ; / , / 空白 —— 老版本只认"整行就是一个属性", 于是
//   `Text { text: "类别:"; color: … }` 这种**单行对象**里的文案一条都不查 (真树里 MapPage
//   那一行就是)。这是"门禁安静地少查一类"的第四个现场, 反证 fixture 见 README。
//   一行里可以有两个属性, 所以用 exec 循环逐个取。
const PROP_RE = /(^|[{;,\s])(text|placeholderText|hint|subtitle|title|actionText|description|emptyHint|label|holdLabel|confirmLabel)\s*:\s*/g;

const files = walk(QML, []);
const hits = [];
for (const f of files) {
    const lines = stripComments(fs.readFileSync(f, 'utf8')).split('\n');
    for (let i = 0; i < lines.length; i++) {
        PROP_RE.lastIndex = 0;
        let mm;
        while ((mm = PROP_RE.exec(lines[i]))) {
            let s = statement(lines, i, lines[i].slice(mm.index));
            // 单行对象的第二个属性不属于这条文案: 在 "; 属性名:" 处截断。
            const cut = s.search(/;[ \t]*[A-Za-z][\w.]*[ \t]*:/);
            if (cut >= 0) s = s.slice(0, cut);
            for (const lit of literals(s)) {
                const hasHan = /[㐀-鿿]/.test(lit);
                for (const [why, re, hanOnly] of BANS) {
                    if (hanOnly && !hasHan) continue;
                    if (!re.test(lit)) continue;
                    hits.push([path.relative(QML, f), i + 1, mm[2], why, lit.slice(0, 80)]);
                    break;
                }
            }
        }
    }
}
console.log('=== L12 文案内部记号: ' + files.length + ' 个 .qml, 命中 ' + hits.length + ' 处 ===');
for (const [f, l, prop, why, v] of hits) console.log(f + ':' + l + '  [' + prop + '] ' + why + '  → "' + v + '"');
process.exit(hits.length ? 1 : 0);
