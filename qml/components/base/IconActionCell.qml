/**
 * @file IconActionCell.qml
 * @brief 行内小方块动作 (列表行右侧那一格: 分析 / 摘线 / 删除) — 全站同一套的母版
 *
 * 为什么要有这一枚 (2026-10-28 #156 控件样式盘点): 同一个形状此前有三份写法 ——
 *   ① MapPage 的已选清单 4 格用裸 `Button { contentItem: IconLabel }` + Material.background,
 *      圆角走 Material.buttonRadius, 与全站方角卡片的 rSm 不是一个形状;
 *   ② 「轨迹」Tab 的分析格是手搓 Rectangle + **MouseArea**;
 *   ③ ③详情页的行内删除格又是手搓 Rectangle + TapHandler.
 * 三份的差别不只是重复: ②那颗 MouseArea 按下即独占抓握 (见 [[qml-taphandler-exclusive-grab]]
 * 与 #105 目标列表那次), 列表一长就在行里拖不动. 统一成 TapHandler 之后这个坑不再靠
 * 每页自觉避开.
 *
 * 两档视觉:
 *   filled = true  → 底 colorAccent + 字 colorTextOnAccent (成对翻档, 白天墨底浅字 / 夜晚浅底墨字)
 *   filled = false → 底 colorSurface + divider 描边, 图标色由调用方给 (tone)
 * 危险动作**不**用实心红: 图例里色口才承载"红=不可撤", 实心红块会把它冲掉 (见 DialogFooter 同段注释)。
 */

import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

Rectangle {
    id: cell

    Styles { id: styles; visible: false }

    property string iconName: ""
    property color tone: CommonOptions.colorText
    property bool filled: false
    property int iconSize: styles.icSm
    property int cellSize: styles.icBox

    signal triggered()

    implicitWidth: cellSize
    implicitHeight: cellSize
    // 布局里的子项只认 Layout.preferred* (见 [[qml-layout-visible-vs-row]] 同族坑);
    // 不在布局里时用 implicitWidth/Height, 两边都给, 调用方什么都不用写。
    Layout.preferredWidth: cellSize
    Layout.preferredHeight: cellSize

    radius: styles.rSm
    color: cell.filled
            ? (tapArea.pressed ? Qt.darker(CommonOptions.colorAccent, 1.22)
                               : CommonOptions.colorAccent)
            : (tapArea.pressed ? CommonOptions.colorSurfaceDim
                               : CommonOptions.colorSurface)
    border.color: cell.filled ? "transparent" : CommonOptions.colorDivider
    border.width: cell.filled ? 0 : styles.lineHair
    opacity: cell.enabled ? 1.0 : 0.42

    IconLabel {
        anchors.centerIn: parent
        name: cell.iconName
        size: cell.iconSize
        tintColor: cell.filled ? CommonOptions.colorTextOnAccent : cell.tone
    }

    // TapHandler 而不是 MouseArea: 只处理点击, 不参与触摸抓握, 行内拖动照常滚列表
    TapHandler {
        id: tapArea
        cursorShape: Qt.PointingHandCursor
        onTapped: cell.triggered()
    }
}
