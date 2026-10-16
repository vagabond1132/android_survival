/**
 * @file FunctionEntry.qml
 * @brief 功能入口项 (2026-09-14 token 化 + IconLabel 升级)
 *
 * 改成: 左侧图标方块 + 右侧文字 + 右箭头. active=false 时灰色.
 * 图标: name 优先 (IconLabel 字体), icon 兜底 (emoji 文字).
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Rectangle {
    id: functionEntry
    property string title: ""
    property string subtitle: ""
    // 旧: icon (emoji 文字)
    property string icon: ""
    // 新: name (Material Icons 语义名, 走 IconLabel)
    property string name: ""
    property bool active: true

    signal clicked()

    height: 72
    radius: 10
    color: functionEntry.active ? CommonOptions.colorSurface : Qt.darker(CommonOptions.colorBg, 1.1)
    border.color: functionEntry.enabled ? Qt.darker(CommonOptions.colorSurface, 1.1) : CommonOptions.colorBg
    border.width: 1
    opacity: functionEntry.enabled ? 1.0 : 0.6

    MouseArea {
        anchors.fill: parent
        enabled: functionEntry.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: functionEntry.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // 图标方块
        Rectangle {
            width: 44
            height: 44
            radius: 10
            color: Qt.rgba(CommonOptions.colorAccent.r, CommonOptions.colorAccent.g, CommonOptions.colorAccent.b, 0.18)

            Loader {
                anchors.centerIn: parent
                sourceComponent: functionEntry.name !== "" ? iconLabelComp : textComp
                Component {
                    id: iconLabelComp
                    IconLabel {
                        name: functionEntry.name
                        size: 22
                        tintColor: CommonOptions.colorAccent
                    }
                }
                Component {
                    id: textComp
                    Text {
                        text: functionEntry.icon
                        font.pixelSize: 22
                    }
                }
            }
        }
        Column {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: functionEntry.title
                color: CommonOptions.colorText
                font.pixelSize: 16
                font.bold: true
            }
            Text {
                text: functionEntry.subtitle
                color: functionEntry.enabled ? CommonOptions.colorTextMuted : "#546E7A"
                font.pixelSize: 12
            }
        }
        Text {
            text: "›"
            color: functionEntry.enabled ? "#607D8B" : "#37474F"
            font.pixelSize: 24
        }
    }
}

