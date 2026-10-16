/**
 * @file PageHeader.qml
 * @brief 通用页面顶部工具栏: 返回 + 标题 (2026-09-14)
 *
 * 之前各 Page 各自实现顶部 hero + 返回, 风格不统一, 不少 Page 还忘了
 * 加 back 按钮导致"返回不了主页". 抽出来统一.
 *
 * 用法:
 *   Page {
 *       PageHeader { title: "详情" }
 *       ...
 *   }
 *   // 标题栏下方接 hero / 列表等
 *
 * 返回按钮直接调 navBus.back() (Page 内任意位置都可达).
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Rectangle {
    id: header
    property string title: ""
    property bool showBack: true
    property color bg: CommonOptions.colorSurface
    // 2026-09-19: 不能再叫 height, Rectangle.height 是内置 FINAL 属性, 覆盖会编译失败
    property int barHeight: 48

    Layout.fillWidth: true
    Layout.preferredHeight: barHeight
    color: bg

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 12
        spacing: 4

        ToolButton {
            visible: header.showBack
            text: "←"
            font.pixelSize: 22
            onClicked: header.ApplicationWindow.window.navBus.back()
        }
        Text {
            Layout.fillWidth: true
            text: header.title
            color: CommonOptions.colorText
            font.pixelSize: 18
            font.bold: true
            elide: Text.ElideRight
        }
    }
}
