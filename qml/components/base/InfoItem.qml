/**
 * @file InfoItem.qml
 * @brief 信息项 (2026-09-14 token 化)
 *
 * 之前硬编码 "white" / "#90A4AE" 换为 CommonOptions.
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

ColumnLayout {
    id: infoItem
    property string label: ""
    property string value: ""

    spacing: 2

    Text {
        text: infoItem.label
        color: CommonOptions.colorTextMuted
        font.pixelSize: 11
    }
    Text {
        text: infoItem.value
        color: CommonOptions.colorText
        font.pixelSize: 16
        font.bold: true
    }
}
