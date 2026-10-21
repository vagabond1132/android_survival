/**
 * @file Chip.qml
 * @brief 文字胶囊 (单选/多选筛选、分类标签) (2026-10-19 整体改版新建)
 *
 * 为什么用文字而不是图标: assets/fonts/MaterialIcons-Regular.ttf 里
 * U+F000-F0FF 整段缺字, 蛇 / 蘑菇 / 昆虫 / 帐篷这类图形根本没有字形
 * (改版前拿别的码位凑, 真机上就是垃圾桶当"毒蛇"). 分类一律用文字胶囊,
 * 语义反而更准.
 */

import QtQuick
import OutdoorSurvival 1.0

Rectangle {
    id: chip

    property string text: ""
    property bool checked: false
    property color accent: CommonOptions.colorAccent
    property int textSize: styles.fsMd

    signal clicked()

    Styles { id: styles; visible: false }

    implicitWidth: Math.max(label.implicitWidth + styles.spLg, 52)
    implicitHeight: styles.chipH
    radius: styles.rPill
    color: checked ? accent : CommonOptions.colorSurfaceAlt
    border.color: checked ? accent : CommonOptions.colorDivider
    border.width: styles.lineHair

    Text {
        id: label
        anchors.centerIn: parent
        text: chip.text
        color: chip.checked ? CommonOptions.colorTextOnAccent : CommonOptions.colorTextMuted
        font.pixelSize: chip.textSize
        font.bold: chip.checked
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
