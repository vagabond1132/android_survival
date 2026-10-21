/**
 * @file PrimaryButton.qml
 * @brief 主行动按钮 (2026-10-19 整体改版新建)
 *
 * 4.jpg 的 "启动急救决策 (" 被截断成半句话: 原实现把动态后缀拼进按钮文案,
 * 又用了 Button 默认 contentItem, 宽度不够时直接 elide 在括号处.
 * 本组件把图标/文案拆成两个节点, 文案 elide 且居中, 调用方负责写短标签.
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Rectangle {
    id: btn

    property string text: ""
    property string iconName: ""
    property color tone: CommonOptions.colorAccent
    property bool filled: true
    property bool busy: false
    property int textSize: styles.fsLg

    signal clicked()

    Styles { id: styles; visible: false }

    implicitHeight: styles.btnH
    height: implicitHeight
    Layout.preferredHeight: implicitHeight
    // 2026-10-19: 本组件是 Rectangle, 不会随内容变宽 —— 之前调用方必须写死
    //   Layout.preferredWidth (96 / 88 / 140 各处不一样). 改成用 TextMetrics
    //   量文案宽度: 测量与 btn.width 无关, 不会和下面 Text 的 Layout.maximumWidth
    //   (依赖 btn.width) 形成绑定环.
    implicitWidth: textMetrics.advanceWidth + 2 * styles.spLg
                   + (iconName.length > 0 ? styles.icMd + styles.spSm : 0)
    radius: styles.rPill
    opacity: enabled ? 1.0 : 0.45
    color: filled ? tone : "transparent"
    border.color: filled ? "transparent" : tone
    border.width: filled ? 0 : styles.lineHair

    TextMetrics {
        id: textMetrics
        font.pixelSize: btn.textSize
        font.bold: true
        text: btn.text
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: styles.spSm

        IconLabel {
            visible: btn.iconName.length > 0
            name: btn.iconName
            size: styles.icMd
            tintColor: btn.filled ? CommonOptions.colorTextOnAccent : btn.tone
        }
        Text {
            // 2026-10-19 真机 (56_route_detail.png 起终点"导航"按钮是空心色块):
            //   原来扣的是 icBoxSm(32) + 2*cardPad(32) = 64px, 与图标实际占位无关,
            //   窄按钮 (72/88/96) 一进来就把文案挤成 0~24px → 全部 elide 掉.
            //   改成只扣真实存在的图标宽度 + RowLayout spacing, 再留 spMd 呼吸位.
            Layout.maximumWidth: Math.max(0, btn.width - styles.spMd * 2
                                          - (btn.iconName.length > 0
                                             ? styles.icMd + styles.spSm : 0))
            text: btn.text
            color: btn.filled ? CommonOptions.colorTextOnAccent : btn.tone
            font.pixelSize: btn.textSize
            font.bold: true
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignHCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: btn.enabled && !btn.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
