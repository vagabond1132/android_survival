/**
 * @file SheetActionBand.qml
 * @brief 地图工作台「动作带」: 面板底部一排等宽动作格 (图标 + 文字)
 *
 * 2026-10-28 #156 新建. 语法抄自用户提供的两步路工作台真机截图 (pass9/ref/lbw2/lbw4):
 * 面板最底是一条 60 逻辑高的横带, 里面 3~4 等格, 每格一个图标 + 一行小字,
 * 格与格之间只有组线、没有按钮边框。我们原来是把「搜索/导入/刷新/清空/开始记录」
 * 做成通栏 PrimaryButton 或标题行右侧的小方块, 于是
 *   - pass9 ②: 查找那颗通栏搜索键图标巨大、压着文案, 按钮居中、左边一片残留;
 *   - pass9 ③: 轨迹行右侧那枚「分析」方块被 RowLayout 顶出行框 (ListRow 的
 *     implicitWidth 没设 Layout.minimumWidth, 长标题时 fillWidth 收不回去).
 * 两个根因是同一个: 动作没有自己的带, 就挤进内容行里。
 *
 * 高度 60 = styles.rowHTall (实测两步路那条带 180 raw ÷ 3)。
 * 只画右组线、最后一格不画 —— 与 CommonOptions 的三级描边口径一致 (colorRuleSoft 组线)。
 *
 * tone 只有三档, 故意不给"随便挑个颜色":
 *   prime  = 这一屏唯一的主操作 (实心 colorAccent + colorTextOnAccent)
 *   danger = 不可撤 (文字/图标走 colorDangerOnText —— colorDanger 画在 colorSurface
 *            深灰底上只有 2.7~2.9:1, 10.5px 的小字看不清, 见 #110 那次同样的取舍)
 *   其余   = 常态 (colorText)
 */
import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

// delegate 里读外层 id (band / styles): qmlcachegen 静态编译下没有 Bound 语义
// 会在真机静默 ReferenceError (见 [[qml-delegate-outer-id-pragma]]).
pragma ComponentBehavior: Bound

RowLayout {
    id: band

    Styles { id: styles; visible: false }

    // 每格: { key, icon, label, tone, enabled }
    //   icon  = IconLabel 语义名 (只许用本字体里真存在的字形)
    //   tone  = "" | "prime" | "danger"
    //   enabled 缺省即 true; 写 false 时整格变淡且不可点, 但**位置保留** ——
    //   记录没开始时"停止记录"要看得见才知道这格是干什么的.
    property var actions: []

    signal triggered(string key)

    Layout.fillWidth: true
    Layout.preferredHeight: styles.rowHTall
    spacing: 0

    Repeater {
        model: band.actions

        delegate: Rectangle {
            id: cell
            required property var modelData
            required property int index

            readonly property bool cellEnabled: cell.modelData.enabled !== false
            readonly property bool prime: cell.modelData.tone === "prime"
            readonly property bool danger: cell.modelData.tone === "danger"
            readonly property color fgColor: !cell.cellEnabled ? CommonOptions.colorTextDisabled
                : cell.prime ? CommonOptions.colorTextOnAccent
                : cell.danger ? CommonOptions.colorDangerOnText
                : CommonOptions.colorText

            Layout.fillWidth: true
            Layout.preferredHeight: styles.rowHTall
            color: cell.prime
                    ? (padTap.pressed ? Qt.darker(CommonOptions.colorAccent, 1.22)
                                      : CommonOptions.colorAccent)
                    : (padTap.pressed ? CommonOptions.colorSurfaceAlt
                                      : CommonOptions.colorSurface)
            opacity: cellEnabled ? 1.0 : 0.42

            // 组线 (右缘 1px, 最后一格不画)
            Rectangle {
                visible: cell.index < band.actions.length - 1
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: styles.lineHair
                color: CommonOptions.colorRuleSoft
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: styles.spXs

                IconLabel {
                    // 同 MapBottomSheet: ColumnLayout 的子项用 Layout.alignment,
                    // anchors.horizontalCenter 会被 positioner 覆盖 → 图标/文字贴左.
                    Layout.alignment: Qt.AlignHCenter
                    name: cell.modelData.icon || ""
                    size: styles.icMd
                    tintColor: cell.fgColor
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: cell.modelData.label || ""
                    font.pixelSize: styles.fsSm
                    font.bold: cell.prime
                    color: cell.fgColor
                }
            }

            MouseArea {
                id: padTap
                anchors.fill: parent
                enabled: cell.cellEnabled
                cursorShape: cell.cellEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: band.triggered(String(cell.modelData.key || ""))
            }
        }
    }
}
