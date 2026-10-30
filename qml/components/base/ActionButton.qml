/**
 * @file ActionButton.qml
 * @brief 全站按钮母版 (2026-10-26 按钮体系定稿, 用户选定「色口 + 文案 + 附注」这一种)
 *
 * 形态三件事, 缺一就不是这颗:
 *   ① 左侧 16px **色口** —— 语义只写在这里 (橙=有代价 / 蓝=交给外部程序 / 绿=移动到达 /
 *      红=不可撤). 色口画在按钮内侧, 不占文案宽度以外的空间.
 *   ② 中间 **文案** —— 汉字, 加粗, fsLg.
 *   ③ 右侧 **附注** —— 编号 (拉丁, 等宽) 或预警字 (汉字, 非等宽). 只在真有预警时出现.
 *
 * 为什么不是胶囊: Styles.qml 里 rPill 注释写明"chip 专用", 丁骨架的卡片/角标一律直角.
 * 2026-10-26 真机那张「删除」确认框 (PrimaryButton 两字 → implicitWidth 40 × 高 44 +
 * rPill 999) 直接画成了一颗红圆, 压在 Dialog 右下圆角上 —— 圆形在移动端是"图标键"的
 * 形态, 写两个字进圆里读起来像关闭气泡. 这颗改成直角 + 最小宽 = 高, 短标签不再成圆.
 *
 * 为什么必须有按压态: 旧 PrimaryButton 全篇只有 enabled 一个视觉状态 (opacity .45),
 * pressed 一条绑定都没写 → 真机上按下去颜色和抬起完全一样, 用户以为没反应.
 *
 * 附注字族规则 (见 Styles.qml ⑦): 汉字进 monoFont 真机会回退失败出方框, 所以附注按
 * 内容分两颗 Text —— 纯拉丁走等宽, 含汉字走正文族. 不要合并成一颗.
 */

import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

Rectangle {
    id: btn

    Styles { id: styles; visible: false }

    // === 对外属性 ===
    property string text: ""
    property string iconName: ""          // IconLabel 语义名, 空 = 不画图标
    property string code: ""              // 右侧附注: "SP-009" / "不可撤" / "外部"
    property color accent: "transparent"  // 色口颜色; 透明 = 不画色口
    property bool filled: false           // true = 实心 (主键), false = 描边 (次键)
    property color tone: filled ? CommonOptions.colorAccent : CommonOptions.colorText
    property real textSize: styles.fsLg
    property bool busy: false
    property real buttonHeight: styles.btnH   // 44 = 主/次; 32 = 行内与紧凑排 (btnHSm)

    signal clicked()

    // === 派生尺寸 (只读 TextMetrics, 与 btn.width 无关 → 不会成绑定环) ===
    readonly property bool hasAccent: accent.alpha > 12
    readonly property real accentW: hasAccent ? styles.spLg : 0
    readonly property bool hasIcon: iconName.length > 0
    readonly property bool hasCode: code.length > 0
    // 附注里只要有一个汉字就不许进等宽字族
    readonly property bool codeIsLatin: !/[\u3000-\u303F\u4E00-\u9FFF\uFF00-\uFFEF]/.test(code)

    readonly property real iconW: hasIcon ? styles.icMd + styles.spSm : 0
    readonly property real codeW: hasCode
        ? styles.spMd + (codeIsLatin ? codeLatinMetrics.advanceWidth : codeCjkMetrics.advanceWidth) : 0

    implicitWidth: Math.max(buttonHeight,
        Math.round(accentW + styles.spLg + iconW + labelMetrics.advanceWidth + codeW
                   + styles.spMd))
    implicitHeight: buttonHeight
    height: implicitHeight
    Layout.preferredHeight: implicitHeight

    // 实心: 底 = tone, 按下往深一档. 描边: 底 = surface, 按下填一档灰 (边框不变).
    // Rectangle 自己没有 pressed (那是 MouseArea/Controls 的), 必须显式声明再绑 ——
    // 直接读 pressed 会得到一个静默的 undefined, 整条 color 绑定跟着失效.
    property bool pressed: tapArea.pressed
    color: filled ? (pressed ? Qt.darker(btn.tone, 1.22) : btn.tone)
                  : (pressed ? CommonOptions.colorSurfaceAlt : CommonOptions.colorSurface)
    border.color: filled ? "transparent" : CommonOptions.colorDivider
    border.width: filled ? 0 : styles.lineHair
    opacity: enabled ? 1.0 : 0.42

    Behavior on color { ColorAnimation { duration: 90 } }

    TextMetrics {
        id: labelMetrics
        font.pixelSize: btn.textSize
        font.bold: true
        text: btn.text
    }
    TextMetrics {
        id: codeLatinMetrics
        font.pixelSize: styles.fsSm
        font.family: styles.monoFont
        text: btn.code
    }
    TextMetrics {
        id: codeCjkMetrics
        font.pixelSize: styles.fsSm
        text: btn.code
    }

    // ① 色口
    Rectangle {
        visible: btn.hasAccent
        width: btn.accentW
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: btn.accent
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: btn.accentW + styles.spLg
        anchors.rightMargin: styles.spMd
        spacing: styles.spSm

        // ② 图标 (可选)
        IconLabel {
            visible: btn.hasIcon
            name: btn.iconName
            size: styles.icMd
            tintColor: btn.filled ? CommonOptions.colorTextOnAccent : btn.tone
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: btn.text
            color: btn.filled ? CommonOptions.colorTextOnAccent : btn.tone
            font.pixelSize: btn.textSize
            font.bold: true
            elide: Text.ElideMiddle
            verticalAlignment: Text.AlignVCenter
        }

        // ③ 附注: 拉丁走等宽 (编号对齐图例), 汉字走正文族 (monoFont 装汉字 = 方框)
        Text {
            visible: btn.hasCode && btn.codeIsLatin
            Layout.alignment: Qt.AlignVCenter
            text: btn.code
            font.pixelSize: styles.fsSm
            font.family: styles.monoFont
            color: btn.filled ? CommonOptions.colorTextOnAccent : CommonOptions.colorTextDim
            opacity: btn.filled ? 0.66 : 1.0
        }
        Text {
            visible: btn.hasCode && !btn.codeIsLatin
            Layout.alignment: Qt.AlignVCenter
            text: btn.code
            font.pixelSize: styles.fsSm
            color: btn.filled ? CommonOptions.colorTextOnAccent : CommonOptions.colorTextDim
            opacity: btn.filled ? 0.66 : 1.0
        }
    }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        enabled: btn.enabled && !btn.busy
        cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: btn.clicked()
    }

    // 外接键盘 / 无障碍焦点环: 弹层里"看不见焦点"就等于只能靠猜按哪颗
    activeFocusOnTab: true
    Keys.onReturnPressed: if (enabled && !busy) clicked()
    Keys.onSpacePressed: if (enabled && !busy) clicked()
    Rectangle {
        visible: btn.activeFocus
        anchors.fill: parent
        anchors.margins: -2
        color: "transparent"
        border.color: CommonOptions.colorInfo
        border.width: 2
    }

    Accessible.role: Accessible.Button
    Accessible.name: btn.text.length > 0 ? btn.text : btn.code
    Accessible.onPressAction: if (btn.enabled && !btn.busy) btn.clicked()
}
