/**
 * @file DifficultyChip.qml
 * @brief 难度筛选 chip (2026-09-14 token 化)
 */

import QtQuick
import QtQuick.Controls.Material
import OutdoorSurvival 1.0

Rectangle {
    id: chip
    property string label: ""
    property bool selected: false
    signal clicked()

    height: 32
    radius: 16
    color: chip.selected ? CommonOptions.colorWarn : "transparent"
    border.color: chip.selected ? CommonOptions.colorWarn : "#60FFFFFF"
    border.width: 1

    Text {
        anchors.centerIn: parent
        text: chip.label
        color: chip.selected ? "black" : CommonOptions.colorText
        font.pixelSize: 12
        font.bold: chip.selected
        leftPadding: 12
        rightPadding: 12
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
