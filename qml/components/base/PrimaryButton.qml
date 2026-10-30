/**
 * @file PrimaryButton.qml
 * @brief 主行动按钮 = ActionButton 的实心档 (2026-10-26 收进母版)
 *
 * 原来这里是一份独立实现 (Rectangle + rPill 胶囊 + TextMetrics), 只有 enabled 一个视觉
 * 状态。2026-10-19 那次改的是"文案被压成空白", 形态问题留着: 44 高的胶囊配两字标签
 * (implicitWidth = 文字 + 2*16 ≈ 40) 就是一颗圆 —— 真机③详情页的「删除」确认框即现场。
 * 现在形态统一交给 ActionButton (直角 + 最小宽 = 高 + 按压态), 本文件只把 filled 打开,
 * text / iconName / tone / textSize / busy / code / accent 全部是 ActionButton 的属性,
 * 调用方按原写法用即可 (不要再在这里 property alias 自己 → 那是自引用)。
 *
 * filled:false 的用法保留 (有几处调用方拿它当空心键), 但空心键请优先用 OutlineButton。
 */

import QtQuick
import OutdoorSurvival 1.0

ActionButton {
    filled: true
}
