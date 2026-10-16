/**
 * @file Section.qml
 * @brief 通用章节组件 (2026-09-14 token 化)
 *
 * 之前硬编码 "white" / "#37474F" / "#90A4AE" 全部换为 CommonOptions.
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

ColumnLayout {
    id: sectionRoot
    property string title: ""
    // 2026-09-19: titleIcon 替代 emoji (避免 emoji 在系统字体下渲染为 X).
    //   调用方传 Material Icons codepoint, 如 "\ue1b1" (report_problem)
    property string titleIcon: ""
    property var items: []
    property color textColor: CommonOptions.colorText
    property string prefix: ""
    property bool asInline: false
    property int itemSpacing: 8

    Layout.fillWidth: true
    Layout.margins: 16
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
            visible: sectionRoot.titleIcon.length > 0
            text: sectionRoot.titleIcon
            font.family: "Material Icons"
            color: CommonOptions.colorText
            font.pixelSize: 16
        }
        Text {
            text: sectionRoot.title
            color: CommonOptions.colorText
            font.pixelSize: 16
            font.bold: true
        }
    }

    // 2026-09-11 (#15): Repeater model 用本地 ListModel, 避免 non-NOTIFYable 警告
    ListModel { id: _itemsModel }

    onItemsChanged: _refreshItems()
    Component.onCompleted: _refreshItems()

    function _refreshItems() {
        _itemsModel.clear()
        if (items) {
            for (var i = 0; i < items.length; ++i) {
                _itemsModel.append({ "value": items[i] })
            }
        }
    }

    Repeater {
        model: _itemsModel
        delegate: Loader {
            Layout.fillWidth: true
            sourceComponent: sectionRoot.asInline ? inlineItem : blockItem
            // 2026-09-19: Loader 内可访问 model, 但 Component 根 Item 拿不到.
            //   用 onItemChanged 把 model.value 显式塞到 item 的属性上.
            onItemChanged: {
                if (item) {
                    // 2026-09-21: 用 String() 强转. 之前 model.value 是 QJSValue 类型,
                    //   直接赋给 QString textValue 会报 "Cannot assign QJSValue to QString"
                    //   (Section.qml:71, app_log.txt 反复出现 50+ 次). String() 包一层
                    //   自动调 toString(), 转成原生 JS string 再赋 QString 兼容.
                    item.textValue = (model.value !== undefined && model.value !== null)
                                     ? String(model.value) : ""
                }
            }
        }
    }

    Component {
        id: blockItem
        Rectangle {
            id: blockRoot
            property string textValue: ""
            color: CommonOptions.colorSurface
            radius: 8
            border.color: Qt.darker(CommonOptions.colorSurface, 1.2)
            border.width: 1
            Layout.fillWidth: true
            implicitHeight: itemText.implicitHeight + 16

            Text {
                id: itemText
                anchors.fill: parent
                anchors.margins: 8
                text: sectionRoot.prefix + blockRoot.textValue
                color: sectionRoot.textColor
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }
        }
    }

    Component {
        id: inlineItem
        Text {
            id: inlineRoot
            property string textValue: ""
            text: "• " + inlineRoot.textValue
            color: sectionRoot.textColor
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
