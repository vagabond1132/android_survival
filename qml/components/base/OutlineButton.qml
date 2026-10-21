/**
 * @file OutlineButton.qml
 * @brief 空心描边按钮 — 次级动作 (2026-10-20 「地物图例」丁骨架)
 *
 * 为什么不用 PrimaryButton(filled: false): 那颗是胶囊 (rPill), 属于旧 Material 味.
 * 丁骨架是印刷场卡, 卡片/角标一律直角, 次级按钮要跟同一套角; 而且它的高度锁
 * styles.btnHSm=32 —— 主按钮 44 是"一个屏最多一颗"的主角, 次级必须明显矮一档.
 *
 * 宽度用 TextMetrics 量而不是写死: PrimaryButton 早期调用方各处抄 96/88/140,
 * 窄了就 elide. 这里测量与自身宽度无关, 不会形成绑定环.
 */

import QtQuick
import OutdoorSurvival 1.0

Rectangle {
    id: btn

    Styles { id: styles; visible: false }

    property string text: ""
    property color tone: CommonOptions.colorText
    property real textSize: styles.fsSm
    signal clicked()

    implicitWidth: Math.round(metrics.advanceWidth + 2 * styles.spMd)
    implicitHeight: styles.btnHSm
    radius: styles.rSm
    opacity: enabled ? 1.0 : 0.4
    color: CommonOptions.colorSurface
    border.color: btn.tone
    border.width: styles.lineHair

    TextMetrics {
        id: metrics
        font.pixelSize: btn.textSize
        text: btn.text
    }

    Text {
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 2 * styles.spXs)
        text: btn.text
        color: btn.enabled ? btn.tone : CommonOptions.colorTextDisabled
        font.pixelSize: btn.textSize
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignHCenter
    }

    MouseArea {
        anchors.fill: parent
        enabled: btn.enabled
        cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: btn.clicked()
    }
}
