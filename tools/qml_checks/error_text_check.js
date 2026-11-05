// L12 门禁 (src 侧): 错误通道的文案必须是中文, 驱动/底层原文只进日志 (2026-11-05 #37 / 真机 0.0.9)
//
// 为什么 QML 那半不够: user_text_marks_check.js 只扫 qml/, 而屏幕上「读不到: not found」这类
// 短句根本不在 qml 里 —— 它是 C++ service 用 fail(ServiceErrorCode::X, message, ctx) 塞进
// QVariantMap.error 的, QML 端只是把它画出来。真机 0.0.9 逐页判下来, 弹层与 Toast 里端出去的
// 英文与内部记号全部来自这一条通道, 所以这一半必须单独有个扫 src/ 的门禁。
//
// 判的形态 (六条, 每条都有本轮现场):
//   R1 英文字面量整句无汉字 —— "List not found"、"too few points" 这类整句上线
//   R2 内部记号进文案 —— entityId / listMap.id / user_ 开头 / index=%1 / DB 未打开:
//      与 QML 侧同一批口径 (camelCase 键名、snake_case 表名、键=占位、缩写), 只是这里
//      宿主是 C++ 字面量。
//   R3 驱动/底层原文被拼进文案 —— errorString() / lastError() / .message 出现在 fail() 的
//      message 表达式里 (哪怕前面有中文前缀, 拼出来的尾巴还是英文, 屏幕上就是半中半英)。
//      这些值只能进 Logger。
//   R4 message 实参是裸变量 —— 第二个参数既不是字面量也不是三元, 直接一个标识符 (err),
//      等于把上游任何东西原样端给用户; 静态判据看不出它今天是中文还是英文, 一律拦。
//   R5 `.arg(标识符)` 把运行期的内部记号灌进屏幕 —— 字面量写得再干净, 「清单不存在: %1」
//      .arg(listId) 出来的还是 user_1731746 这种尾巴。变量名 (…Id / …Path / err / ctx)
//      是开发者自己写的信号, 叫这个名字的值不是给人读的。带运算或取成员的 (.arg(int(s)) /
//      .arg(m["id"])) 静态分不清, 不骂。
//   R6 校验 helper 的字段名 —— requireNonEmpty(value, "listMap.id", ctx) 拼出的是
//      「listMap.id 不能为空」, 它不在 fail() 的实参里, R1~R5 永远看不见 (本轮实测全树 9 处
//      调用, 其中 6 处的字段名是 ASCII 键名)。字段名参数必须含汉字。
// 只判"第一个实参形如 ServiceErrorCode::X 的真调用", 所以头文件里的声明与定义不会被误读。
// 两条写入口都要判: fail(...) 是 QML 快捷封装, Err<T>(...) 是 Result 通道的原始构造 ——
//   两者写进同一个 ServiceError.message, 只封一条就等于没封 (本轮实测 Err<T>( 另有 44 处)。
// 注释先换成等量空白: QmlResultBridge.h 的用法示例 (QStringLiteral("…")) 写在 doc
// 注释里, 那不是调用点。
//
// 命中 exit 1 / 干净 exit 0 / src 目录找不到 = 门禁没跑起来, exit 2, 绝不静默 0 条。
//   可判对象有两族 (fail/Err 写入点、requireNonEmpty/NonBlank 字段名), 两族同时为 0 才算没对象可判 ——
//   只按第一族判会把"全是校验 helper 的树"当成空树放行 (fixture bad_field_label 钉住这一条)。
const fs = require('fs'), path = require('path');
const ARGS = process.argv.slice(2);
const VERBOSE = ARGS.includes('--verbose');
const ROOT = path.resolve(__dirname, '../..');
const SRC = ARGS.find((a) => !a.startsWith('--')) || path.resolve(ROOT, 'src');

function die2(msg) { console.error('!! ' + msg + ' —— 门禁没有真正运行, 判 exit 2'); process.exit(2); }
if (!fs.existsSync(SRC)) die2('找不到 src 目录 ' + SRC);

function stripComments(t) {
    return t.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
            .replace(/\/\/[^\n]*/g, (m) => ' '.repeat(m.length));
}
function walk(d, out) {
    if (!fs.existsSync(d)) return out;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (/\.(cpp|h|inl|hpp)$/.test(e.name)) out.push(p);
    }
    return out;
}
const lineOf = (s, i) => s.slice(0, i).split('\n').length;
const CJK = /[\u4e00-\u9fff]/;
const hasCjk = (s) => CJK.test(s);
// 取一个字符串字面量里的内容 (本仓不用转义引号, 中文文案里没有 \")
function literals(s) {
    const out = [];
    const re = /"((?:[^"\\\n]|\\.)*)"/g;
    for (let m = re.exec(s); m; m = re.exec(s)) out.push(m[1]);
    return out;
}
// 从 fail( 的左括号起, 按引号与括号配对收整条实参表, 再按顶层逗号切
function callArgs(raw, openParen) {
    let depth = 0, inStr = false, esc = false;
    for (let i = openParen; i < raw.length; i++) {
        const c = raw[i];
        if (inStr) {
            if (esc) esc = false;
            else if (c === '\\') esc = true;
            else if (c === '"') inStr = false;
            continue;
        }
        if (c === '"') { inStr = true; continue; }
        if (c === '(') depth++;
        else if (c === ')') {
            depth--;
            if (depth === 0) {
                const body = raw.slice(openParen + 1, i);
                const parts = [];
                let d = 0, s = false, start = 0;
                for (let j = 0; j < body.length; j++) {
                    const ch = body[j];
                    if (s) { if (ch === '"') s = false; continue; }
                    if (ch === '"') { s = true; continue; }
                    if (ch === '(' || ch === '[' || ch === '{') d++;
                    else if (ch === ')' || ch === ']' || ch === '}') d--;
                    else if (ch === ',' && d === 0) { parts.push(body.slice(start, j)); start = j + 1; }
                }
                parts.push(body.slice(start));
                return parts;
            }
        }
    }
    return null;
}

const INTERNAL = [
    ['camelCase 键名', /[A-Za-z][A-Za-z0-9]*Id\b/],
    ['snake_case 表名/字段', /[a-z][a-z0-9]*(?:_[a-z][a-z0-9]*){1,}/],
    ['键=占位', /[A-Za-z_][A-Za-z0-9_]*=\s*%/],
    ['缩写 DB/SQL', /\b(?:DB|SQL)\b/],
    ['内部键名 id', /\bid\b/],
    ['圈号内部编号', /[①-⑳⒈-⒙]/],
];
const RAW_LEAK = /(?:errorString\s*\(|lastError\s*\(|\.message\b)/;
// R5: 字面量里没有记号, 但 `.arg(x)` 灌进去的运行期值就是记号 —— 屏幕上必然出现
//   「清单不存在: user_1731746」「无法打开 CSV 文件: /data/user/0/…」。变量名是开发者自己
//   写的信号, 叫 id/…Id/path/err 的变量不是给人读的东西。真正给人读的编号走 plateCode 这类名字。
const ARG_LEAK = /^(?:[A-Za-z0-9_]*Id|id|[A-Za-z0-9_]*Path|path|err|error|lastError|ctx)$/;

const hits = [];
const files = walk(SRC, []).sort();
let calls = 0, scanned = 0, fieldChecks = 0;

for (const f of files) {
    let srcText, raw;
    try {
        srcText = fs.readFileSync(f, 'utf8');
        raw = stripComments(srcText);
    } catch (e) { die2('读不了 ' + f + ': ' + e.message); }
    scanned++;
    // `L12 免: <理由>` 写在调用那一行或紧贴它上一行的注释里才放行 (与 state_truth 的 L11 免同族,
    // 只是这里的"块"是行, 因为 C++ 侧的豁免单位是一句调用, 不是整个函数)。
    // 注释会被 strip 掉, 所以这一条必须去原文 (srcText) 上查 —— 偏移量两边等长, 对得上。
    const waived = (idx) => {
        const lines = [idx];
        const ls = raw.lastIndexOf('\n', idx) + 1;
        lines.push(ls);
        if (ls > 0) lines.push(raw.lastIndexOf('\n', ls - 2) + 1);
        return lines.some((start) => {
            const end = srcText.indexOf('\n', start);
            return /L12[ \t]*免/.test(srcText.slice(start, end < 0 ? srcText.length : end));
        });
    };
    const re = /\b(?:fail|Err<[A-Za-z0-9_:<>]*>)[ \t]*\(/g;
    for (let m; (m = re.exec(raw));) {
        const parts = callArgs(raw, m.index + m[0].length - 1);
        if (!parts || parts.length < 2) continue;
        if (!/^ServiceErrorCode::[A-Za-z0-9_]+$/.test(parts[0].trim())) continue;
        calls++;
        const msg = parts[1].replace(/^[ \t\n]+|[ \t\n]+$/g, '');
        const where = { f, line: lineOf(raw, m.index) };
        const push = (why) => { if (!waived(m.index)) hits.push(Object.assign({ why }, where)); };

        const lits = literals(msg);
        // R4: 既没有字面量, 也不是三元/拼接表达式 —— 整颗实参就是一个变量
        if (!lits.length && !/[?+]|QString|tr\s*\(/.test(msg)) {
            push('错误文案是裸变量 `' + msg + '` —— 上游给什么屏幕上就画什么, 必须是中文字面量');
        }
        if (RAW_LEAK.test(msg)) {
            push('错误文案里拼了 errorString()/lastError()/.message —— 驱动原文只进 Logger, 屏上给中文');
        }
        // R5: `.arg(标识符)` 灌进去的运行期值 —— 带运算/取成员的 (.arg(int(x)) / .arg(m.id))
        //   静态分不清, 不骂; 只骂"整颗实参就是一个像内部记号的变量名"。
        for (const am of msg.matchAll(/\.arg[ \t]*\([ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*\)/g)) {
            if (ARG_LEAK.test(am[1])) {
                push('文案把内部记号 `' + am[1] + '` 用 .arg() 端上屏 —— 屏幕上是「…不存在: user_1731746」'
                    + '这种尾巴; 值进 Logger, 屏上只留中文');
            }
        }
        for (const lit of lits) {
            if (!/[A-Za-z]/.test(lit)) continue;              // 纯中文/纯符号, 没有可判的记号
            if (!hasCjk(lit)) {
                push('错误文案整句是英文 `' + lit + '` —— 面向用户的话必须是中文');
            }
            for (const [name, ban] of INTERNAL) {
                if (ban.test(lit)) {
                    // %1 之后灌进来的运行期值由 R5 单独判 (变量名是不是内部记号), 这一条只管字面量
                    push('错误文案含' + name + ' `' + lit + '` —— 内部记号对用户没有信息量');
                    break;
                }
            }
        }
        if (VERBOSE) console.log('  call @ ' + path.relative(ROOT, f) + ':' + where.line + ' → ' + msg.slice(0, 60));
    }

    // R6: 校验 helper 的字段名实参 —— requireNonEmpty(value, "字段名", ctx) 会拼出
    //   「字段名 不能为空」直接上屏, 写 "listMap.id" 屏幕上就是英文键名。这一条不在 fail() 的
    //   实参里, 上面四条永远看不见它 (本轮实测全树 7 处全是 ASCII)。
    for (const hm of raw.matchAll(/\brequire(?:NonEmpty|NonBlank)[ \t]*\([^,]*,[ \t]*"([^"]*)"/g)) {
        fieldChecks++;
        const label = hm[1];
        if (/[A-Za-z]/.test(label) && !hasCjk(label)) {
            if (!waived(hm.index)) {
                hits.push({ f, line: lineOf(raw, hm.index),
                    why: '校验 helper 的字段名写成 `' + label + '` —— 屏幕上出来的是「' + label + ' 不能为空」, 字段名要写给人读的中文' });
            }
        }
    }
}

// 两类可判对象各算一份家底: 只有 requireNonEmpty 字段名、一个 fail()/Err<>() 都没有的树,
//   R6 照样判得出 —— 只要任意一类有对象就不是"门禁没跑起来"。
if (calls === 0 && fieldChecks === 0) {
    die2('全树 0 个 fail()/Err<>() 错误文案写入点、0 个字段名校验 helper (扫描了 '
        + scanned + ' 个文件) —— 本门禁无从判合规');
}
console.log('扫描 ' + scanned + ' 个 src 文件; 错误文案写入点 (fail/Err) ' + calls + ' 处, '
    + '字段名校验 helper (requireNonEmpty/NonBlank) ' + fieldChecks + ' 处');
for (const h of hits) console.log('HIT ' + path.relative(ROOT, h.f) + ':' + h.line + ' — ' + h.why);
console.log('=== L12 src 侧 错误文案中文化 / 内部记号 / 驱动原文透传: 命中 ' + hits.length + ' 处 ===');
process.exit(hits.length ? 1 : 0);
