/**
 * @file DuoRule.qml
 * @brief 双线规则 — 1px 墨线 + 1px 空 + 1px hairline (2026-10-20 「地物图例」)
 *
 * 印刷里的"套版线"分隔, 用来切区块. 单根 hairline 在任何浅色底上都太弱,
 * 而 Material Divider 的 1px @ 12% 黑又太糊; 双线既 divider 又是装饰, 且
 * 高度固定 3px, 不会像阴影那样在强光下消失.
 *
 * 用法: width 交给父布局 (Layout.fillWidth), 不要给它 height.
 */

import QtQuick
import OutdoorSurvival 1.0

Item {
    id: duo

    Styles { id: styles; visible: false }

    property color strongTone: CommonOptions.colorText
    property color softTone: CommonOptions.colorRule

    implicitWidth: 100
    implicitHeight: 3
    height: implicitHeight

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: duo.strongTone
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: duo.softTone
    }
}
