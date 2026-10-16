/**
 * @file DangerChip.qml
 * @brief 统一危险等级色条 (5 阶段架构重构 Phase 3)
 *
 * 背景: 5 处 species 显示 danger level,各自写 5 段 if-else,色值/阈值不一致。
 *       抽成统一组件后,色值阈值一处定义,5 处复用。
 *
 * 等级映射 (1-5):
 *   1 - 安全 (绿)
 *   2 - 低度 (黄)
 *   3 - 中度 (橙)
 *   4 - 高度 (深橙)
 *   5 - 致命 (红)
 */
import QtQuick
import QtQuick.Controls.Material
import OutdoorSurvival 1.0

Rectangle {
    id: root

    property int level: 1         // 1-5
    property bool compact: false  // 小尺寸 (用于列表项)
    property string label: ""     // 自定义标签 (默认按 level 翻译)

    readonly property var _colors: ["#388E3C", "#FBC02D", "#FB8C00", "#E64A19", "#D32F2F"]
    readonly property var _labels: ["安全", "低度", "中度", "高度", "致命"]

    readonly property color _bg: level >= 1 && level <= 5 ? _colors[level - 1] : "#9E9E9E"
    readonly property string _text: label !== "" ? label : (level >= 1 && level <= 5 ? _labels[level - 1] : "未知")

    color: _bg
    radius: compact ? 3 : 4
    implicitHeight: compact ? 18 : 24
    implicitWidth: txt.implicitWidth + (compact ? 12 : 16)

    Text {
        id: txt
        anchors.centerIn: parent
        text: root._text
        color: "white"
        font.pixelSize: root.compact ? 10 : 12
        font.bold: !root.compact
    }
}