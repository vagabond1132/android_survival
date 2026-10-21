/**
 * @file NavBands.qml
 * @brief 底部 5 方位带导航 — 丁骨架的一级索引 (2026-10-20)
 *
 * 替换原来的 12 项侧边抽屉作一级导航 (抽屉保留在顶栏当"全部入口"的逃生口).
 * 5 格 = BASE 营地 / RES 资源 / ROUTE 路线 / SOS 求助 / 我.
 *   · 第 5 格是 2026-10-20 用户拍板补上的: 丁原本只有 4 方位格, 「装备」和「我的」
 *     没有一级入口, 这是它相对甲的 5 Tab 唯一的功能性缺口.
 *   · 每格两行: 上面等宽拉丁代号 (允许字距), 下面中文 (永不加字距).
 *   · 选中格 = 墨底 + on-ink 文字 + 代号变亮橙. 不用下划线: 48px 高的条里下划线
 *     会被状态栏手势区吃掉.
 *
 * 高度固定 styles.navBandH(48), 每格 flex 等分. 这一条要常驻, 所以①营地正文
 * 的可用量是 屏高 - 状态栏 - 标题条 - 本条, 新加区块必须从别处腾地方.
 */

import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

// delegate 里引用外层 id (bands.current), qmlcachegen 静态编译下必须 Bound 语义,
// 否则真机上是静默 ReferenceError (见 2026-10-19 stage0.log 那一批同类 bug).
pragma ComponentBehavior: Bound

Rectangle {
    id: bands

    Styles { id: styles; visible: false }

    signal bandActivated(string key)

    property string current: "base"
    property var items: [
        { key: "base",   code: "BASE",  zh: "营地" },
        { key: "res",    code: "RES",   zh: "资源" },
        { key: "route",  code: "ROUTE", zh: "路线" },
        { key: "sos",    code: "SOS",   zh: "求助" },
        { key: "me",     code: "ME",    zh: "我" }
    ]

    implicitHeight: styles.navBandH
    color: CommonOptions.colorSurfaceAlt

    // 顶边用墨而不是 hairline: 导航条与正文之间要一眼分界, 这是强调描边
    // (全站一屏最多 2 处强调描边, 这一处是常驻的那一处)
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: styles.lineHair
        color: CommonOptions.colorText
    }

    RowLayout {
        id: rowLay
        anchors.fill: parent
        anchors.topMargin: styles.lineHair
        spacing: 0

        Repeater {
            model: bands.items
            delegate: Rectangle {
                id: cell
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: styles.touchMin
                color: bands.current === modelData.key
                       ? CommonOptions.colorText : "transparent"

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 3
                    Text {
                        text: cell.modelData.code
                        Layout.alignment: Qt.AlignHCenter
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        font.letterSpacing: 1.2
                        color: bands.current === cell.modelData.key
                               ? CommonOptions.colorBlazeSoft : CommonOptions.colorText
                    }
                    Text {
                        text: cell.modelData.zh
                        Layout.alignment: Qt.AlignHCenter
                        font.pixelSize: styles.fsSm
                        // 中文不加字距 (样式铁律), 这里显式写 0 以防父级继承
                        font.letterSpacing: 0
                        color: bands.current === cell.modelData.key
                               ? CommonOptions.colorOnInk : CommonOptions.colorTextMuted
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    // 点当前格不重复触发, 否则会把 StackView 根页重建一次
                    onClicked: if (bands.current !== cell.modelData.key)
                                   bands.bandActivated(cell.modelData.key)
                }
            }
        }
    }
}
