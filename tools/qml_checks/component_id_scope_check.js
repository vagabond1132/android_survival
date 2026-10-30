// id 的组件作用域自检 (2026-10-27 #134 加)
//
// 为什么 undefined_id_check.js 抓不到这一类: 它的口径是"全工程没有任何文件把这个名字
// 当 id 声明过"才报. 而 MapPage 的轨迹列表行写的是 `color: hoverArea.containsMouse` ——
// hoverArea 在同文件的**路线** delegate 里声明过, 于是被当作"有主的名字"放过. 但 QML 的
// id 作用域只在声明它的那个组件里 (每个 delegate / Component 各自一个作用域), 跨兄弟
// delegate 引用就是悬空: 整条绑定抛 ReferenceError 被吞, Rectangle 停在类型默认的
// #FFFFFF → 轨迹行永远白底, 用户看到的是"轨迹色彩不对", 而不是一个报错. release 包
// logcat 全空, 只在 app 沙盒 stage0.log 里留一行 —— 门禁不抓就没人抓.
//
// 口径: 按花括号把文件切成块树, 只有块头里出现 `delegate` / `Component` 的块才算
// 新的 id 作用域 (普通对象块 Rectangle{} / Styles{} 不是边界 —— 里面的 id 对整个
// 外层组件仍可见, 这就是每个页里那句 `Styles { id: styles; visible: false }` 能被
// 全页读到的原因). `id: X` 记它所属的组件; `X.属性` 记引用处从内到外的组件链;
// 合法 ⟺ 声明组件出现在这条链上。只查本文件确实当 id 声明过的名字。
const fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml');

function walk(d, ext, out) {
    if (!fs.existsSync(d)) return out;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, ext, out);
        else if (ext.some(x => e.name.endsWith(x))) out.push(p);
    }
    return out;
}

// 注释和字符串里的花括号/名字都是噪音; 换行原样留着, 否则报出来的行号会整体上跳。
function strip(t) {
    const blank = m => m.replace(/[^\n]/g, ' ');
    return t.replace(/\/\*[\s\S]*?\*\//g, blank)
            .replace(/\/\/[^\n]*/g, '')
            .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
            .replace(/'(?:[^'\\\n]|\\.)*'/g, "''");
}

function localNames(t) {
    const s = new Set();
    for (const m of t.matchAll(/\bproperty\s+(?:readonly\s+)?[A-Za-z_][\w<>?.]*\s+([A-Za-z_]\w*)/g)) s.add(m[1]);
    for (const m of t.matchAll(/\bproperty\s+([A-Za-z_]\w*)\s*:/g)) s.add(m[1]);
    for (const m of t.matchAll(/\b(?:var|let|const)\s+([A-Za-z_]\w*)/g)) s.add(m[1]);
    for (const m of t.matchAll(/(?:function|signal)\s*(?:[A-Za-z_]\w*)?\s*\(([^)]*)\)/g)) {
        for (const p of m[1].split(',')) {
            const bits = p.trim().split(/\s+/);
            const name = bits.length ? bits[bits.length - 1] : '';
            if (/^[A-Za-z_]\w*$/.test(name)) s.add(name);
        }
    }
    return s;
}

const files = walk(ROOT, ['.qml'], []);
let n = 0;
for (const f of files) {
    const t = strip(fs.readFileSync(f, 'utf8'));
    const locals = localNames(t);

    // compOf[i] = 第 i 个块所属的组件块号 (自身是组件则取自身); compParent[c] = 外层组件
    const compOf = [0];
    const compParent = [-1];
    const stack = [0];        // 块栈
    const compStack = [0];     // 组件栈
    const nodeAt = new Int32Array(t.length + 1);
    const compAt = new Int32Array(t.length + 1);
    let head = '';
    let blocks = 0;
    for (let i = 0; i < t.length; i++) {
        const ch = t[i];
        if (ch === '{') {
            blocks++;
            const parentBlock = stack[stack.length - 1];
            const isComp = /(^|[^\w.])(delegate|component)\b/i.test(head);
            let c;
            if (isComp) {
                c = blocks;                       // 新组件用块号当组件号
                compParent[c] = compStack[compStack.length - 1];
            } else {
                c = compStack[compStack.length - 1];
            }
            compOf.push(c);
            stack.push(blocks);
            if (isComp) compStack.push(c);
            head = '';
        } else if (ch === '}') {
            if (stack.length > 1) {
                const gone = stack.pop();
                if (compOf[gone] === gone) compStack.pop();   // 出的是一个组件块
            }
            head = '';
        } else if (ch === '\n' || ch === ';') {
            head = '';
        } else if (!/\s/.test(ch)) {
            head = (head + ch).slice(-160);
        }
        nodeAt[i + 1] = stack[stack.length - 1];
        compAt[i + 1] = compStack[compStack.length - 1];
    }

    const decls = new Map();
    for (const m of t.matchAll(/\bid\s*:\s*([A-Za-z_]\w*)/g)) {
        // 声明归属看它所在块的**外层组件** (id: styles 写在 Styles{…} 里, 作用域仍是本组件)
        const c = compOf[nodeAt[m.index]];
        const list = decls.get(m[1]) || [];
        list.push(c);
        decls.set(m[1], list);
    }

    const seen = new Set();
    for (const m of t.matchAll(/(^|[^\w.$])([a-z]\w*)\s*\.\s*[A-Za-z_]\w*/g)) {
        const id = m[2];
        if (!decls.has(id) || locals.has(id)) continue;
        let c = compAt[m.index + m[1].length];
        const chain = new Set();
        while (c !== undefined && c !== -1) { chain.add(c); c = compParent[c]; }
        let ok = false;
        for (const d of decls.get(id)) if (chain.has(d)) { ok = true; break; }
        if (ok) continue;
        const line = t.slice(0, m.index).split('\n').length;
        const once = id + ':' + line;
        if (seen.has(once)) continue;
        seen.add(once);
        console.log(path.relative(ROOT, f) + ':' + line + '  "' + id + '" 的 id 声明在别的组件里, '
            + '本处引用跨了 id 作用域 —— 绑定会抛 ReferenceError 并被吞掉, 属性停在类型默认值');
        n++;
    }
}
console.log('=== 跨组件 id 引用 ' + n + ' 处 ===');
process.exit(n ? 1 : 0);
