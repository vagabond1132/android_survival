/**
 * @file Ladder.qml
 * @brief 档位梯 — N 个小方格, 实心格数 = 档位 (2026-10-20 「地物图例」v9)
 *
 * 为什么不用 "★★★☆☆": 星号既占宽又必须排进等宽字族, 而汉字不许进等宽
 * (见 [[qml-monofont-no-cjk]]); 这一栏只表达"要多费劲/多紧急", 5 个格子一眼数得完.
 *
 * 为什么做成组件而不是在 delegate 里内联 Repeater: 内联写法要嵌套一层 Repeater,
 * 内层 delegate 的 modelData 会被内层模型 (model: 3 这种整数) 遮蔽, 于是
 * `index < modelData.difficulty` 恒为 false —— 绳结目录的难度梯因此在真机上永远是空的,
 * 而且 qmllint 不报、加载不报, 只能肉眼看出来. 数值改由本组件的 property 传进来,
 * 遮蔽的可能性就没有了.
 *
 * topTone: 顶格单独给色. 绳结第 3 档 = 高难, 急救危急档 = hazard 红
 * (hazard 红全站只给 SOS 与真危险, 这里是"真危险"那一档).
 */

// delegate 要读组件自己的 id (ladder.cells / ladder.value), qmlcachegen 静态编译下
// 没有 Bound 语义会抛 ReferenceError —— 见 [[qml-delegate-outer-id-pragma]].
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: ladder

    property int cells: 5
    property int value: 0
    property color tone: CommonOptions.colorText
    property color topTone: tone
    property real cellWidth: 5
    property real cellHeight: 6
    property real gap: 2

    implicitWidth: cells * cellWidth + (cells > 1 ? (cells - 1) * gap : 0)
    implicitHeight: cellHeight

    Row {
        anchors.fill: parent
        spacing: ladder.gap
        Repeater {
            model: ladder.cells
            delegate: Rectangle {
                required property int index
                width: ladder.cellWidth
                height: ladder.cellHeight
                readonly property bool filled: index < ladder.value
                color: !filled ? CommonOptions.colorRuleSoft
                       : (index === ladder.cells - 1 ? ladder.topTone : ladder.tone)
            }
        }
    }
}
