#!/usr/bin/env node
/**
 * layout_collapse_check.js — 扫"布局子项没有高度、子项又 anchors.fill: parent"的塌陷块 (2026-10-22)
 *
 * 为什么需要它: Rectangle / Item 这类**纯 Item 系**类型没有 implicitHeight (不像 Text/Image/Row
 * 会自己长出来). 把它们直接放进 ColumnLayout/RowLayout/GridLayout 时, 如果不给
 * height / implicitHeight / Layout.preferredHeight / Layout.fillHeight, 布局给的分配高度就是 0;
 * 块里再用 `anchors.fill: parent` 挂一个 ColumnLayout, 子项会照原样画出来 —— 于是
 * **卡片高度 0、内容溢出压到后面几行**. 真机上表现为"文字互相叠在一起", 但:
 *   - qmllint 不报 (类型合法、语法合法);
 *   - int_prop / layout_prop 也不报 (没有写错的属性名);
 *   - 截图上看像数据问题, 排查成本极高.
 * 2026-10-22 在 EquipmentPage 的"环境条件读数条"抓到一处 (EquipmentPage.qml:1040).
 *
 * 判据 (三条同时成立才算命中, 少一条就放过):
 *   ① 父块是 ColumnLayout / RowLayout / GridLayout (StackLayout 不在名单里: 它把所有子项
 *      强制拉成自己的尺寸, 子项不给高度也不塌, 加进去只会造假阳性);
 *   ② 本块类型是纯 Item 系 (Rectangle / Item / Canvas / Flickable / ScrollView 等, 见 IMPLICIT_ZERO);
 *   ③ 本块自身没有任何高度来源, 且块内出现 `anchors.fill: parent`.
 * 注: ③ 只看块**自己那一层**的属性, 子块里写 height 不算 (子块救不了父块).
 *
 * 用法: ELECTRON_RUN_AS_NODE=1 <Qoder.exe> layout_collapse_check.js [qml目录]
 * 退出码: 0 = 干净, 1 = 有命中.
 * ⚠ 任何"0 条"结论必须先用一个已知命中的样例反证脚本是活的 (见 README 的踩坑记录).
 */
const fs = require('fs')
const path = require('path')

const ROOT = process.argv[2] || path.resolve(__dirname, '../../qml')

// 这些类型没有 implicitHeight, 放进布局不给高度就是 0.
const IMPLICIT_ZERO = new Set([
  'Rectangle', 'Item', 'Canvas', 'Flickable', 'ScrollView', 'OpacityMask',
  'ShaderEffect', 'Flipable', 'Transform', 'FocusScope', 'MouseArea', 'GestureArea'
])
// 会自己撑出 implicitHeight 的类型, 即使命中也先不算 (留给"已知样例"反证段).
// StackLayout **不算**: 它把所有子项强制拉成自己的尺寸, 子项不给高度也不会塌.
const LAYOUT_PARENTS = new Set([
  'ColumnLayout', 'RowLayout', 'GridLayout'
])
const HEIGHT_PROPS = new Set([
  'height', 'implicitHeight', 'Layout.preferredHeight', 'Layout.fillHeight',
  'Layout.minimumHeight', 'Layout.maximumHeight', 'Layout.columnSpan'
])

function walk(dir, out) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name)
    const st = fs.statSync(p)
    if (st.isDirectory()) walk(p, out)
    else if (name.endsWith('.qml')) out.push(p)
  }
  return out
}

/** 把注释与字符串换成等量空白: 保住行号与列宽, 又不会把注释里的 `Rectangle {` 当代码. */
function blankOut(src) {
  const out = src.split('')
  let i = 0
  const n = out.length
  while (i < n) {
    const c = src[i], d = src[i + 1]
    if (c === '/' && d === '/') {
      while (i < n && src[i] !== '\n') { out[i] = ' '; i++ }
    } else if (c === '/' && d === '*') {
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) {
        if (src[i] !== '\n') out[i] = ' '
        i++
      }
      out[i] = ' '; out[i + 1] = ' '; i += 2
    } else if (c === '"' || c === "'") {
      const q = c
      out[i] = ' '
      i++
      while (i < n && src[i] !== q) {
        if (src[i] === '\\') { out[i] = ' '; i++ }
        if (src[i] !== '\n') out[i] = ' '
        i++
      }
      if (i < n) { out[i] = ' '; i++ }
    } else i++
  }
  return out.join('')
}

const hits = []
let scanned = 0

for (const file of walk(ROOT, [])) {
  scanned++
  const code = blankOut(fs.readFileSync(file, 'utf8'))
  const lines = code.split('\n')

  // 逐行维护块栈: 栈里每一项 = { type, line, depth, ownProps:Set, bodyStart }
  const stack = []
  const blocks = []
  let pendingType = null   // 上一段读到的对象类型名 (等下一个 '{' 认领)

  for (let li = 0; li < lines.length; li++) {
    const line = lines[li]
    // 本行自己那一层的属性赋值 (只看行首, 且当前栈顶就是它的宿主)
    const head = line.match(/^\s*([A-Za-z_][\w]*(?:\.[a-zA-Z_][\w]*)*)\s*:/)
    if (head && stack.length) stack[stack.length - 1].ownProps.add(head[1])
    const propDecl = line.match(/^\s*property\s+(?:readonly\s+)?[\w<>]+\s+(\w+)\s*:/)
    if (propDecl && stack.length) stack[stack.length - 1].ownProps.add(propDecl[1])

    for (let ci = 0; ci < line.length; ci++) {
      const ch = line[ci]
      if (ch === '{') {
        const before = line.slice(0, ci)
        const m = before.match(/([A-Za-z_][\w.]*)\s*$/)
        const type = m ? m[1] : (pendingType || '<anon>')
        const blk = { type, line: li + 1, depth: stack.length, ownProps: new Set(),
                      bodyStart: li + 1, parent: stack.length ? stack[stack.length - 1] : null }
        stack.push(blk)
        blocks.push(blk)
        pendingType = null
      } else if (ch === '}') {
        const blk = stack.pop()
        if (blk) blk.bodyEnd = li + 1
      }
    }
    const t = line.match(/^\s*(?:component|required property|readonly property)?\s*([A-Z][\w]*)\s*$/)
    if (t) pendingType = t[1]
  }

  for (const b of blocks) {
    if (!IMPLICIT_ZERO.has(b.type)) continue
    if (!b.parent || !LAYOUT_PARENTS.has(b.parent.type)) continue
    let hasHeight = false
    for (const p of b.ownProps) if (HEIGHT_PROPS.has(p)) { hasHeight = true; break }
    if (hasHeight) continue
    const body = lines.slice(b.bodyStart, b.bodyEnd === undefined ? lines.length : b.bodyEnd).join('\n')
    if (!/anchors\.fill:\s*parent/.test(body)) continue
    hits.push({ file, line: b.line, type: b.type, parent: b.parent.type })
  }
}

for (const h of hits) {
  console.log(`${h.file}:${h.line}  ${h.type} 直接放在 ${h.parent} 里没有高度, 块内又 anchors.fill: parent`
    + `  →  分配高度 0, 内容溢出压住后面的行`)
}
console.log(`\n扫描 ${scanned} 个 .qml: 塌陷块 ${hits.length} 处`)
process.exit(hits.length > 0 ? 1 : 0)
