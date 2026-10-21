/**
 * @file CheckTick.qml
 * @brief 方角勾选块 — 清单行左侧的"带了 / 没带" (2026-10-20 v9 F3)
 *
 * 为什么不用 Controls 的 CheckBox: 它是 Material 的圆角勾 + 24px indicator + 自带左
 * 侧留白, 与丁骨架"直角印刷场卡"不是一套; 而且点击热区在 indicator 上, 整行点不动.
 * 清单页的语义是"点这一行就勾上", 所以这里只画方块, MouseArea 交给调用方放在整行.
 *
 * 选中态 = 墨底 + on-ink 勾, 与 chip 的选中态同一个"压墨"语言; 未选 = 白底 + rule 描边.
 * 15px 只是视觉尺寸, 真实热区由调用方的行 (styles.touchMin / rowHSm) 提供.
 */

import QtQuick
import OutdoorSurvival 1.0

Rectangle {
    id: tick

    Styles { id: styles; visible: false }

    property bool on: false
    // 缺项行的勾选块描边走 hazard, 让"没带 + 必备"在扫一眼时就能挑出来
    property color tone: CommonOptions.colorText
    property color borderColor: on ? tone : CommonOptions.colorRule

    implicitWidth: 15
    implicitHeight: 15
    radius: styles.rSm
    color: on ? tick.tone : CommonOptions.colorSurface
    border.color: tick.borderColor
    border.width: styles.lineHair

    IconLabel {
        anchors.centerIn: parent
        visible: tick.on
        name: "check"
        size: 11
        tintColor: CommonOptions.colorTextOnAccent
    }
}
