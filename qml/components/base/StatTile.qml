/**
 * @file StatTile.qml
 * @brief 标签 + 数值 的小统计块 (海拔范围 / 活跃月份 / 里程 ...) (2026-10-19 新建)
 *
 * 4.jpg 物种详情页里 "海拔范围 / 活跃月份" 两格是手抄的 Column{Text,Text},
 * 图标码位猜错 (海拔那格画成了铅笔). 统一走本组件: 图标可选且必须是
 * IconLabel 语义名, 数值超长时 elide 而不是把相邻格子挤没.
 */

import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

ColumnLayout {
    id: tile

    property string label: ""
    property string value: ""
    property string iconName: ""
    property color valueColor: CommonOptions.colorText
    property int valueSize: styles.fsLg

    Styles { id: styles; visible: false }

    spacing: styles.spXs

    RowLayout {
        Layout.fillWidth: true
        spacing: styles.spXs
        IconLabel {
            visible: tile.iconName.length > 0
            name: tile.iconName
            size: styles.fsSm
            tintColor: CommonOptions.colorTextDim
        }
        Text {
            Layout.fillWidth: true
            text: tile.label
            color: CommonOptions.colorTextMuted
            font.pixelSize: styles.fsSm
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    Text {
        Layout.fillWidth: true
        text: tile.value
        color: tile.valueColor
        font.pixelSize: tile.valueSize
        font.bold: true
        elide: Text.ElideRight
    }
}
