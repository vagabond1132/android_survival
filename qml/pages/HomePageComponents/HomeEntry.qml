/**
 * @file HomeEntry.qml
 * @brief 主页入口卡片 (2026-09-14 token 化 + IconLabel 升级)
 *
 * 2026-09-10 修复: 不能用 property 名字 'icon' (与 Button 父类 AbstractButton.icon
 * FINAL 冲突). 改名为 iconText.
 * 2026-09-14 token 化: 引用 CommonOptions 颜色.
 * 2026-09-14 图标: 用 IconLabel (Material Icons 字体), name 优先, iconText 兜底.
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Button {
    id: entry
    property string title: ""
    property color accentColor: CommonOptions.colorAccent
    // 兼容旧调用: iconText 仍可传 emoji, 内部 Text 渲染
    property string iconText: ""
    // 新调用: 传 name="firstaid" 等, 走 IconLabel
    property string name: ""

    padding: 12
    flat: false

    contentItem: ColumnLayout {
        spacing: 4
        // 优先用 IconLabel (有 name 时), 否则回退到 Text (emoji)
        Loader {
            Layout.alignment: Qt.AlignHCenter
            sourceComponent: entry.name !== "" ? iconLabelComp : textComp
            Component {
                id: iconLabelComp
                IconLabel {
                    name: entry.name
                    size: 32
                    tintColor: "white"
                }
            }
            Component {
                id: textComp
                Text {
                    text: entry.iconText
                    font.pixelSize: 32
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
        Text {
            text: entry.title
            color: "white"
            font.pixelSize: 14
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }

    background: Rectangle {
        radius: 12
        color: entry.down ? Qt.darker(entry.accentColor, 1.3) : entry.accentColor
    }
}
