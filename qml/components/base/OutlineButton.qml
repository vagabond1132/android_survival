/**
 * @file OutlineButton.qml
 * @brief 空心描边按钮 = ActionButton 的次级档 (2026-10-26 收进母版)
 *
 * 为什么不用 PrimaryButton(filled: false): 那颗是胶囊 (rPill), 属于旧 Material 味.
 * 丁骨架是印刷场卡, 卡片/角标一律直角, 次级按钮要跟同一套角; 而且它的高度锁
 * styles.btnHSm=32 —— 主按钮 44 是"一个屏最多一颗"的主角, 次级必须明显矮一档.
 *
 * 2026-10-26: 形态 (直角 / 按压态 / 色口 / 附注 / 最小宽) 全部收进 ActionButton,
 * 这里只留"矮一档 + 小一号字 + 不实心"三个默认值. 宽度不再自己量.
 * 边框颜色从"跟 tone 同色"改成固定 colorDivider —— 语义色现在只出现在色口与文字上,
 * 一颗按钮上同时有红边 + 红字 + 红色块就没人读得出哪个才是重点.
 */

import QtQuick
import OutdoorSurvival 1.0

ActionButton {
    id: btn

    Styles { id: styles; visible: false }

    filled: false
    buttonHeight: styles.btnHSm
    textSize: styles.fsSm
}
