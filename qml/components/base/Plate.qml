/**
 * @file Plate.qml
 * @brief 图鉴编号角标 — "SV-007" 这种目录卡片号 (2026-10-20 「地物图例」)
 *
 * 作用: 每一条图鉴/急救/绳结条目带一个稳定编号, 让它读起来是"可引用的场卡"
 *       而不是列表里的一行字. 野外口述"看到 SV-007"比描述形态有用.
 * 规则: 等宽字族 + 微字号 + 字距. 这里的 letterSpacing 是允许的, 因为内容
 *       是拉丁与数字 —— CJK 永远不加字距 (那条是样式铁律).
 *
 * 取号: CommonOptions.plateCode(prefix, id). 非数字 id 走 FNV-1a, 跨启动稳定.
 */

import QtQuick
import OutdoorSurvival 1.0

Text {
    id: plate

    Styles { id: styles; visible: false }

    property string prefix: ""
    property string entryId: ""
    // 直接给号时用这个 (列表已有现成编号就不再算)
    property string code: ""
    property color tone: CommonOptions.colorInk3
    // 方括号: 详情页用 true 让它像图版框, 列表行用 false 保持轻
    property bool bracketed: false

    text: (bracketed ? "[ " : "")
          + (code.length > 0 ? code : CommonOptions.plateCode(prefix, entryId))
          + (bracketed ? " ]" : "")
    font.family: styles.monoFont
    font.pixelSize: styles.fsXs
    font.letterSpacing: 1.3
    color: tone

    // 编号不许折行: 折了就变成两行乱码, 整张卡片的"印刷感"就没了
    elide: Text.ElideNone
    wrapMode: Text.NoWrap
}
