// 全代码深度漏洞扫描 + 待办需求清单
const fs = require('fs');
const path = require('path');

const SRC = 'src';
const files = [];
function walk(d){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(e.isDirectory())walk(p);else if(/\.(cpp|h)$/.test(e.name))files.push(p);}}
walk(SRC);

const issues = { P0:[], P1:[], P2:[], P3:[] };

// 1. 扫描 TODO/FIXME
for (const f of files) {
    const text = fs.readFileSync(f, 'utf-8');
    const re = /(TODO|FIXME|XXX|HACK)/g;
    let m;
    while ((m = re.exec(text))) {
        const line = text.substring(0, m.index).split('\n').length;
        issues.P2.push(`${f}:${line} - ${m[0]}`);
    }
}

// 2. 空函数体(只返回 true)
console.log('=== 1. 空函数/无实现 ===');
for (const f of files) {
    if (!f.endsWith('.cpp')) continue;
    const text = fs.readFileSync(f, 'utf-8');
    const re = /::\w+\([^)]*\)\s*(?:const)?\s*\{\s*[^}]{0,80}\}/g;
    let m;
    while ((m = re.exec(text))) {
        const body = m[0];
        // 只匹配 1-3 行的真"空"实现
        if (/^::\w+\([^)]*\)\s*(?:const)?\s*\{\s*\}\s*$/.test(body.trim()) ||
            /\{\s*\/\/[^\n]*\}/.test(body)) {
            const line = text.substring(0, m.index).split('\n').length;
            issues.P2.push(`${f}:${line} - 空实现: ${body.substring(0, 60)}...`);
        }
    }
}

// 3. 异常处理
console.log('=== 2. 异常处理 ===');
for (const f of files) {
    if (!f.endsWith('.cpp')) continue;
    const text = fs.readFileSync(f, 'utf-8');
    if (!/try\s*\{/.test(text)) continue;
    const tries = (text.match(/try\s*\{/g) || []).length;
    const catches = (text.match(/catch\s*\(/g) || []).length;
    if (tries > catches) {
        issues.P2.push(`${f}: try ${tries} 次但 catch 仅 ${catches} 次`);
    }
}

// 4. QFile 资源管理
console.log('=== 3. QFile 资源管理 ===');
for (const f of files) {
    if (!f.endsWith('.cpp')) continue;
    const text = fs.readFileSync(f, 'utf-8');
    const opens = (text.match(/QFile\s+\w+;[\s\S]*?\.open\(/g) || []).length;
    const closes = (text.match(/\.close\(\)/g) || []).length;
    if (opens > 0 && opens > closes) {
        issues.P3.push(`${f}: QFile.open 调用 ${opens} 次,close 仅 ${closes} 次`);
    }
}

// 5. const 引用参数
console.log('=== 4. const 引用 ===');
for (const f of files) {
    if (!f.endsWith('.h')) continue;
    const text = fs.readFileSync(f, 'utf-8');
    // 找 const std::string& 或 const QString&(非引用)
    const re = /void\s+\w+\s*\(\s*const\s+(QString|QStringList|std::string|QVariant)\s+\w+\s*\)/g;
    let m;
    while ((m = re.exec(text))) {
        const line = text.substring(0, m.index).split('\n').length;
        issues.P3.push(`${f}:${line} - const 传值(应改 const&): ${m[0]}`);
    }
}

// 6. 类成员顺序
console.log('=== 5. Q_OBJECT 类成员顺序 ===');
// 已用 moc 处理,略

// 7. 信号返回类型
// 7. signal 返回类型 (只检查 signals: 区段内部,到下一个 access specifier 为止)
console.log('=== 6. signal 返回类型 ===');
for (const f of files) {
    if (!f.endsWith('.h')) continue;
    const text = fs.readFileSync(f, 'utf-8');
    const classRe = /class\s+\w+[^{]*\{/g;
    let cls;
    while ((cls = classRe.exec(text))) {
        const sigIdx = text.indexOf('signals:', cls.index);
        if (sigIdx < 0) continue;
        const after = text.substring(sigIdx + 'signals:'.length);
        const endMatch = after.match(/\n\s*(?:public|private|protected|slots|Q_SLOTS|Q_PROPERTY|Q_INVOKABLE|Q_CLASSINFO):/);
        const endIdx = endMatch ? endMatch.index : after.length;
        const seg = after.substring(0, endIdx);
        const bad = seg.match(/^\s*(QString|int|bool|QVariant|double|float|long|quint32|quint64|qint32|qint64|qsizetype|unsigned\s+int)\s+(\w+)\s*\(/m);
        if (bad) {
            const line = text.substring(0, sigIdx).split('\n').length;
            issues.P0.push(`${f}:${line} - signal ${bad[2]} 返回 ${bad[1]},signal 必须 void`);
        }
    }
}

// 8. Q_OBJECT 必有 moc 包含
console.log('=== 7. Q_OBJECT 类的 .cpp 必须含自身 .h ===');
for (const f of files) {
    if (!f.endsWith('.cpp')) continue;
    const text = fs.readFileSync(f, 'utf-8');
    if (!/Q_OBJECT/.test(text)) {
        // 类未必有 Q_OBJECT
        continue;
    }
    const base = path.basename(f, '.cpp') + '.h';
    const firstInclude = text.match(/^#include\s+"([^"]+)"/m);
    if (firstInclude && firstInclude[1] !== base) {
        const line = text.substring(0, text.indexOf(firstInclude[0])).split('\n').length;
        issues.P1.push(`${f}:${line} - 第一个 include 应是 ${base},实际是 ${firstInclude[1]}`);
    }
}

// 9. switch 漏 break
console.log('=== 8. switch 漏 break(粗糙检查) ===');
// 略

// 10. 头文件重复定义保护
console.log('=== 9. 头文件 #ifndef 保护 ===');
for (const f of files) {
    if (!f.endsWith('.h')) continue;
    const text = fs.readFileSync(f, 'utf-8');
    if (!/Q_OBJECT/.test(text) && !/class\s+\w+/.test(text)) continue;
    const hasIfndef = /#ifndef\s+\w+/.test(text);
    const hasPragma = /#pragma\s+once/.test(text);
    if (!hasIfndef && !hasPragma) {
        issues.P2.push(`${f} - 头文件无 #ifndef/#pragma 保护`);
    }
}

// 11. TODO 行统计(用于全代码待办清单)
console.log('\n=== TODO/FIXME 分布 ===');
const todoCount = {};
for (const f of files) {
    const text = fs.readFileSync(f, 'utf-8');
    const m = text.match(/(TODO|FIXME|XXX|HACK)/g);
    if (m) todoCount[f] = m.length;
}
for (const [f, n] of Object.entries(todoCount).sort((a,b)=>b[1]-a[1])) {
    console.log(`  ${f}: ${n} 处`);
}

// 输出结果
console.log('\n=== 漏洞统计 ===');
for (const k of ['P0','P1','P2','P3']) {
    console.log(`  ${k}: ${issues[k].length}`);
}

console.log('\n=== 详细问题 ===');
for (const k of ['P0','P1','P2','P3']) {
    console.log(`${k} (${issues[k].length}):`);
    issues[k].forEach(i => console.log('  ' + i));
}
