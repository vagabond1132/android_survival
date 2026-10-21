#!/usr/bin/env node
/**
 * layout_prop_check.js — 扫全站 QML 里写错的 Layout 附身属性 (2026-10-20)
 *
 * 为什么需要它: Qt 6.7 的 QQuickLayoutAttached **没有** visible / horizontalAlignment /
 * verticalAlignment, 也从来没有 maximumLineCount. 写成 `Layout.xxx` 不是警告而是
 * 加载期硬错误 "Cannot assign to non-existent property", 整个文件起不来 —— 而
 * qmllint 不报 (它没有 qmldir/类型信息时只查语法). 真机上表现就是"页面空白",
 * 排查成本极高. 2026-10-20 在 HomePage/SOSPage/FieldGuidePage 各抓到一处.
 *
 * 白名单来源: Qt 6.7 QQuickLayoutAttached (实测 Layout.margins 有效, 见 _scratch_debug).
 *
 * 用法: ELECTRON_RUN_AS_NODE=1 <Qoder.exe> layout_prop_check.js [qml目录]
 * 退出码: 0 = 干净, 1 = 有命中 (必须先验证脚本能抓到已知样例再信 0).
 */
const fs = require('fs')
const path = require('path')

const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml')

const VALID = new Set([
  'alignment', 'bottomMargin', 'column', 'columnSpan', 'fillHeight', 'fillWidth',
  'leftMargin', 'margins', 'maximumHeight', 'maximumWidth', 'minimumHeight',
  'minimumWidth', 'preferredHeight', 'preferredWidth', 'rightMargin', 'row',
  'rowSpan', 'topMargin'
])
// 这几个是 Qt 5 时代存在、6.7 已删的, 单独给一条更具体的提示
const REMOVED = new Set(['visible', 'horizontalAlignment', 'verticalAlignment'])

function walk(dir, out) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name)
    const st = fs.statSync(p)
    if (st.isDirectory()) walk(p, out)
    else if (name.endsWith('.qml')) out.push(p)
  }
  return out
}

const hits = []
for (const file of walk(ROOT, [])) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/)
  lines.forEach((line, i) => {
    const m = line.match(/Layout\.([A-Za-z]+)/)
    if (!m) return
    const before = line.slice(0, m.index)
    const trimmed = line.trim()
    // 注释里的不算: 行首注释、块注释续行 (* /), 或同一行 // 之后
    if (before.includes('//') || before.includes('/*')
        || trimmed.startsWith('//') || trimmed.startsWith('*')) return
    const prop = m[1]
    if (VALID.has(prop)) return
    hits.push({
      file, line: i + 1, prop,
      hint: REMOVED.has(prop)
        ? `Layout.${prop} 在 Qt 6.7 不存在 (${prop === 'visible' ? '用普通 visible' : '用 Layout.alignment'})`
        : `Layout.${prop} 不是布局附身属性, 应该去掉 Layout. 前缀`
    })
  })
}

for (const h of hits) {
  console.log(`${h.file}:${h.line}  ${h.hint}  →  加载期硬错误, 整页起不来`)
}
console.log(`\n扫描 ${ROOT}: Layout.* 误用 ${hits.length} 处`)
process.exit(hits.length > 0 ? 1 : 0)
