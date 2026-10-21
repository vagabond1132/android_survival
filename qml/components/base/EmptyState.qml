/**
 * @file EmptyState.qml
 * @brief 空态 / 加载失败占位 (2026-10-19 整体改版新建)
 *
 * 改版前列表为空时只剩一片黑 (图鉴换省份后 0 条, 用户报"无数据"但其实只是筛没了).
 * 统一给一句人话 + 一个可点的恢复动作.
 */

import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

ColumnLayout {
    id: empty

    property string iconName: "list"
    property string text: "暂无数据"
    property string hint: ""
    property string actionText: ""
    property color tint: CommonOptions.colorTextDim

    signal actionTriggered()

    Styles { id: styles; visible: false }

    spacing: styles.spSm

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: styles.icBoxLg
        Layout.preferredHeight: styles.icBoxLg
        radius: styles.rPill
        color: CommonOptions.withAlpha(empty.tint, 0.14)
        IconLabel {
            anchors.centerIn: parent
            name: empty.iconName
            size: styles.icXl
            tintColor: empty.tint
        }
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: empty.text
        color: CommonOptions.colorTextMuted
        font.pixelSize: styles.fsLg
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: 260
        visible: empty.hint.length > 0
        text: empty.hint
        color: CommonOptions.colorTextDim
        font.pixelSize: styles.fsSm
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
    PrimaryButton {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: styles.spSm
        // 2026-10-19: 去掉写死的 Layout.preferredWidth: 140 —— PrimaryButton 现在
        //   按文案自带 implicitWidth, 不同长度的按钮标签都能刚好包住文字.
        visible: empty.actionText.length > 0
        text: empty.actionText
        iconName: "refresh"
        filled: false
        tone: CommonOptions.colorAccent
        textSize: styles.fsMd
        onClicked: empty.actionTriggered()
    }
}
