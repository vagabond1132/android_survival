/**
 * @file CategoryChip.qml
 * @brief 分类选择 chip
 */

import QtQuick
import QtQuick.Controls.Material

Rectangle {
    id: chip
    property string label: ""
    property bool selected: false
    signal clicked()

    height: 32
    radius: 16
    color: chip.selected ? "#FF5722" : "transparent"
    border.color: chip.selected ? "#FF5722" : "#80FFFFFF"
    border.width: 1

    Text {
        anchors.centerIn: parent
        text: chip.label
        color: "white"
        font.pixelSize: 12
        font.bold: chip.selected
        leftPadding: 12
        rightPadding: 12
    }

    MouseArea {
        anchors.fill: parent
        onClicked: chip.clicked()
    }
}
