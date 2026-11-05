/**
 * strip_fake_reviewer.js — 把数据里 700 条 "审核人 XX" 占位符删掉 (2026-11-03 F3 / L12)
 *
 * 只删文本里那一行, 不重新序列化 JSON, 以免整份文件被改写格式.
 * 先看两种尾随逗号形态: "reviewer" 后面还有键 (删 key + 其后逗号) / 它是最后一个键
 * (删 key + 其前逗号).
 *
 * 用法: <node> strip_fake_reviewer.js            # 预演, 只打印
 *       <node> strip_fake_reviewer.js --write    # 真写
 */
'use strict';
const fs = require('fs');
const path = require('path');

const dataDir = path.join(__dirname, '..', 'assets', 'data');
const write = process.argv.includes('--write');

// 只有整值都是占位符才算 (XX / XXX / XX 教授（植物学） / XX(昆虫学))
const PLACEHOLDER = /^\s*"X{2,}[^"]*"\s*$/;

let total = 0;
for (const name of fs.readdirSync(dataDir)) {
    if (!name.endsWith('.json')) continue;
    const p = path.join(dataDir, name);
    const before = fs.readFileSync(p, 'utf8');

    // 形态 1: "reviewer": "XX ...",   (后面还有键)
    let after = before.replace(
        /^[ \t]*"reviewer"[ \t]*:[ \t]*"X{2,}[^"]*"[ \t]*,\r?\n/gm, '');
    // 形态 2: 前一个值后面紧跟 ,"reviewer": "XX ..." 且它是块内最后一项
    after = after.replace(
        /,(\r?\n)[ \t]*"reviewer"[ \t]*:[ \t]*"X{2,}[^"]*"[ \t]*(\r?\n)/g, '$1$2');

    const removed = (before.match(/"reviewer"[ \t]*:[ \t]*"X{2,}/g) || []).length;
    const left = (after.match(/"reviewer"/g) || []).length;
    if (removed === 0 && left === 0) continue;

    // 反证占位符判定: 打印没被删掉的 reviewer (应为 0)
    for (const m of after.matchAll(/"reviewer"[ \t]*:[ \t]*("[^"]*")/g)) {
        if (!PLACEHOLDER.test(m[1])) console.log('  保留: ' + name + ' → ' + m[1]);
    }
    // JSON 必须仍然可解析
    try { JSON.parse(after); }
    catch (e) { console.error('解析失败 ' + name + ': ' + e.message); process.exit(2); }

    console.log(name + ': 删 ' + removed + ' 条 · 余 reviewer 键 ' + left
                + ' · ' + before.length + ' → ' + after.length + ' B');
    total += removed;
    if (write) fs.writeFileSync(p, after, 'utf8');
}
console.log((write ? '已删' : '预演将删') + '合计 ' + total + ' 条');
