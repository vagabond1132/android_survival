/**
 * @file PositionReadout.qml
 * @brief 墨底仪表 — ①营地与⑤求助共用的位置读数块 (2026-10-20 丁骨架 v8)
 *
 * 为什么单独成一个件: ①和⑤要读同一组数 (坐标 / 海拔 / 精度 / 朝向 / 读取时间),
 * 之前这类读数在 5 个页面里各写一遍, 字号与单位写法互不一致. 收成一个件之后,
 * 全站墨底仪表只有这两处 —— 墨底是"高优先级仪表"的信号, 出现第三次就贬值.
 *
 * 版式 (与已评审的 mock 逐行对应):
 *   ┌ 3px 橙条 ┌────────────────────────────────┐
 *   │ 实时位置                        10:42    │  微标签行: 汉字, 不加字距
 *   │ 40.43721 N / 115.90338 E                  │  等宽一行, 不许折
 *   │ - - - - - - - - - - - - - - - - - - - - -  │  虚线 (印刷套版)
 *   │ 1180 m   ±12 m   184°   10:42             │  四格读数, 每格 数 + 名
 *   └───────────────────────────────────────────┘
 *
 * 坐标行: 一行读不完就换行而不是 elide —— 坐标被截半比折成两行更糟 (读数会读错
 * 半截). ⑤把 74px 盘嵌进来之后宽度变窄, 走的就是折行分支.
 * coordText 与 cells 的 v 只许装拉丁和数字: 它们画在等宽 Text 里, monospace 族
 * 没有汉字字形, 混排会出方框 (见 Styles ⑦). 未定位就传 "--", "未定位"那类汉字说明
 * 写在同一行的 trailing 上; 读数单位要中文就放进 cells 的 k 里 (k 用默认字族).
 */

import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

// delegate 里用了外层 id `styles` (字号/间距), 必须 Bound 语义;
// 默认 Unbound 下 qmlcachegen 静态编译会把它编成 null 引用, 真机表现为整块读数
// 空白但没有任何 console 报错 (2026-10-19 同类 bug 一批, 见项目记忆).
pragma ComponentBehavior: Bound

Rectangle {
    id: readout

    Styles { id: styles; visible: false }

    property string label: "实时位置"
    property string trailing: ""            // 右上角时间/状态
    property string coordText: "--"
    // 2026-10-22 #98: 读数为什么是空的 —— 一句话说明 (汉字, 走默认字族).
    // "--" 自己不会说话: 用户分不清"还没定到位"和"这台机器定不到位", 只会反复重进页面.
    // 空串时整行不占版面.
    property string hint: ""
    // [{ v: "1180 m", k: "海拔" }, ...]  最多 4 格, 多了会挤
    property var cells: []
    property color panelColor: CommonOptions.colorInkPanel
    property color barColor: CommonOptions.colorBlazeSoft
    // 右上角状态色: ①给的是读取时间 (跟橙条同色), ⑤给的是 "● GPS 8 星" (绿)
    property color trailingColor: CommonOptions.colorBlazeSoft
    // ⑤求助: 墨底仪表左边嵌一个 74px 迷你盘 (mock 丁⑤). ①营地不开 (默认 false),
    // RowLayout 会跳过 invisible 子项, 连间距都不占, 所以①的版式一字未动.
    property bool showDial: false
    property real dialHeading: 0
    property bool dialHasFix: true
    property string dialValue: "--"
    property string dialLabel: "航向"
    property var dialSectors: []
    property var dialTargets: []

    implicitWidth: 280
    implicitHeight: row.implicitHeight + 2 * styles.readoutPad
    color: panelColor
    border.color: CommonOptions.colorText
    border.width: styles.lineHair

    // 3px 橙条: 主操作的标记, 不用阴影 (强光下阴影会消失, 边条不会)
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: styles.lineAccent
        color: readout.barColor
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: styles.readoutPad + styles.lineAccent + 6
        anchors.rightMargin: styles.readoutPad + 4
        spacing: 10

        Dial {
            visible: readout.showDial
            Layout.preferredWidth: styles.dialSizeMini
            Layout.preferredHeight: styles.dialSizeMini
            Layout.alignment: Qt.AlignVCenter
            onInk: true
            heading: readout.dialHeading
            hasFix: readout.dialHasFix
            hubValue: readout.dialValue
            hubLabel: readout.dialLabel
            sectors: readout.dialSectors
            targets: readout.dialTargets
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 3

        // --- 微标签行 ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: readout.label
                // 汉字不进等宽 (monoFont 无中文字形, 真机出方框)
                font.pixelSize: styles.fsXs
                color: CommonOptions.colorOnInkDim
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                visible: readout.trailing.length > 0
                text: readout.trailing
                font.pixelSize: styles.fsXs
                color: readout.trailingColor
            }
        }

        // --- 坐标 ---
        Text {
            Layout.fillWidth: true
            text: readout.coordText
            font.family: styles.monoFont
            // 14 而非 13.5: pixelSize 是 int, 写字面小数是**加载期硬错误**
            // ("Invalid property assignment: int expected", 整页起不来);
            // 走 styles.fsXs 这类 real 绑定反而没事, Qt 会四舍五入 (8.5→9).
            font.pixelSize: 14
            color: CommonOptions.colorOnInk
            elide: Text.ElideRight
            // 不带盘时一行读完; ⑤嵌了 74px 盘之后剩下的宽度不够一行, 这时必须折行
            // 而不能 elide —— 坐标被截半比折行更糟 (读数会读错).
            wrapMode: readout.showDial ? Text.Wrap : Text.NoWrap
            maximumLineCount: 2
        }

        // --- 虚线套版线 ---
        Item {
            id: dashRule
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    // 6px 一个周期 (2 实 4 空), 数量跟宽度走
                    model: Math.max(1, Math.floor(dashRule.width / 6))
                    Rectangle {
                        width: 2
                        height: 1
                        color: CommonOptions.colorOnInkDim
                    }
                }
            }
        }

        // --- 读数格 (等宽数字 + 7px 名) ---
        RowLayout {
            Layout.fillWidth: true
            spacing: styles.readoutCellGap
            Repeater {
                model: readout.cells
                delegate: ColumnLayout {
                    required property var modelData
                    property string valueText: modelData.v !== undefined ? String(modelData.v) : ""
                    property string nameText: modelData.k !== undefined ? String(modelData.k) : ""
                    spacing: 1
                    Layout.alignment: Qt.AlignBottom
                    Text {
                        text: valueText
                        font.family: styles.monoFont
                        font.pixelSize: 12
                        color: CommonOptions.colorOnInk
                        wrapMode: Text.NoWrap
                    }
                    Text {
                        text: nameText
                        font.pixelSize: 9
                        color: CommonOptions.colorOnInkDim
                    }
                }
            }
        }

        // --- 定位说明 (只在读数缺失时出现) ---
        Text {
            visible: readout.hint.length > 0
            Layout.fillWidth: true
            text: readout.hint
            font.pixelSize: styles.fsXs
            color: CommonOptions.colorBlazeSoft
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        }   // body (ColumnLayout)
    }       // row (RowLayout: 迷你盘 + 读数)
}
