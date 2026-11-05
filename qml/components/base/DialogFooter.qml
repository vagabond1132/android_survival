/**
 * @file DialogFooter.qml
 * @brief Dialog 的按钮排 (2026-10-26 按钮体系定稿)
 *
 * 修的是 A34 收口时留下的同一个根因, 全站 7 个确认框都中招:
 * Qt 把 Dialog.footer 排在 padding **外面** (header/footer/contentItem 一律按弹窗全宽
 * 定位), 所以原来那套 `footer: RowLayout { Item{fillWidth}; 两颗按钮 }` 会让按钮贴着
 * 卡片边缘 —— 真机上那颗红圆就是这么压在右下圆角上、看起来"溢"出去了。
 * 这里把 footer 本体做成一条自带底色与顶线的横带, 内边距由带子自己管, 不再指望 Dialog 给。
 *
 * 排版规则 (定稿四条):
 *   ① 一排最多一颗实心;
 *   ② 顺序永远 取消 → 确认, 不可撤的确认键排最右;
 *   ③ 两颗都按内容宽, 左边留弹簧 —— 不铺满带子 (2026-10-28 用户: "按钮最左侧可以添加
 *      弹簧, 保持内容正常显示即可, 不需要两个按钮填充整个弹窗". 从前各占一半, 两颗
 *      两三个汉字的按钮被拉成两条通栏横块, 读起来像两栏内容而不是一颗按钮);
 *   ④ cancelText 写空串 = 只剩确认键: 贴右站 + 宽度按文案收 (2026-10-28 问题3 ——
 *      从前它占满整条带子, 两颗汉字被拉成一条通栏横块, 读起来像一栏而不是一颗按钮).
 *
 * 2026-10-26: 排布从 RowLayout 改成锚点自己算宽 —— Qt 6.7 的 Layout 附身属性里
 *   **没有** visible (写了是加载期硬错误), 单键情形只能靠子项 visible:false, 而布局是否
 *   为此收回空间在这个版本不确定; 少一颗时若留下半个带子的空位, 确认键就歪在中间.
 *   宽度是 (带子宽 - 间距) / 2 这种纯算术, 不需要布局参与.
 */

import QtQuick
import OutdoorSurvival 1.0

Rectangle {
    id: foot

    Styles { id: styles; visible: false }

    // === 确认键的三档 (kind 决定色口/底/字/附注, 单个属性仍可覆盖) ===
    //   danger  = 不可撤: 描边 + 红色口 + 红字 + 附注「不可撤」 (只给真删存储的动作)
    //   primary = 写进本机存储的常规确认: 实心墨底, 不占色口
    //   plain   = 只是关掉弹层 / 只擦屏上画线: 描边 + 正文色, 不占色口
    // 「清空」这个词两档都会用: 删文件的是 danger, 擦画线重新点一行就回来的是 plain ——
    //   判档看 onConfirm 落到哪个函数, 不看按钮文案。(每使用点必须显式写 kind, 别吃默认值)
    // 危险档为什么不是实心红: 实心红块是 Material 的"destructive button", 在这套图例里
    //   色口才是语义位 —— 一整块红把"红色=不可撤"这条只有色口承载的读法冲掉了, 而且
    //   白天 #B4290E 底上压浅色字只有 5.9:1, 夜晚同一颗翻不档就成了红底红字.
    property string kind: "danger"
    property string cancelText: "留着"     // 空串 = 只有确认键 (纯查看型弹层的「关闭」)
    property string confirmText: "确定"
    property string confirmIcon: ""
    property color confirmAccent: kind === "danger" ? CommonOptions.colorDanger : "transparent"
    property color confirmTone: kind === "danger" ? CommonOptions.colorDangerOnText
                             : kind === "primary" ? CommonOptions.colorAccent
                                                  : CommonOptions.colorText
    property bool confirmFilled: kind === "primary"
    property string confirmCode: kind === "danger" ? "不可撤" : ""
    property bool confirmEnabled: true

    signal cancel()
    signal confirm()

    implicitWidth: 240
    implicitHeight: styles.btnH + 2 * styles.spMd
    color: CommonOptions.colorSurfaceAlt

    // 只要顶线: Rectangle 的 border 是四边的, 所以描边交给下面这一条
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: styles.lineHair
        color: CommonOptions.colorDivider
    }

    // 两颗按钮的宽度算式 (不用 RowLayout: 本文件已不 import QtQuick.Layouts,
    //   而缺这个 import 时 RowLayout 是加载期硬错误 → 整张 Dialog 画不出来, 真机上
    //   表现为"确认框点不开". 单键情形也不靠布局收回空间, 自己贴右边站.)
    // 2026-10-28 (问题3): 单键从前是 `_innerW` 整条带子占满, 两颗汉字被拉成一条
    //   通栏横块、文字还靠左 —— 真机上用户把它当成一栏而不是一颗按钮. 现在按规则 ②
    //   "确认键排最右" 办到底: 单键 = 贴右 + 内容多宽按钮多宽 (ActionButton 的
    //   implicitWidth 只由 TextMetrics 算, 与 width 无关, 不会成绑定环).
    // 2026-10-28 (用户: 不需要两个按钮填充整个弹窗): 双键从前各占一半, 于是「取消」
    //   两个字被拉成一条通栏横块. 改成两颗都按内容宽、一起贴右, 剩下的宽度就是左侧
    //   那根弹簧. 只有内容宽之和超过带子时才等分收缩, 保证文案不会被挤没.
    readonly property bool _two: foot.cancelText.length > 0
    readonly property real _innerW: foot.width - 2 * styles.pageMargin
    readonly property real _naturalW: confirmBtn.implicitWidth
                                      + (foot._two ? cancelBtn.implicitWidth + styles.spMd : 0)
    readonly property real _btnW: Math.min(confirmBtn.implicitWidth, foot._innerW)
    readonly property real _cancelW: foot._naturalW <= foot._innerW
                                     ? cancelBtn.implicitWidth
                                     : Math.max(0, foot._innerW - styles.spMd - foot._btnW)

    ActionButton {
        id: cancelBtn
        visible: foot._two
        anchors.right: confirmBtn.left
        anchors.rightMargin: styles.spMd
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: styles.spMd
        anchors.bottomMargin: styles.spMd
        width: foot._cancelW
        text: foot.cancelText
        tone: CommonOptions.colorTextMuted
        onClicked: foot.cancel()
    }

    ActionButton {
        id: confirmBtn
        anchors.right: parent.right
        anchors.rightMargin: styles.pageMargin
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: styles.spMd
        anchors.bottomMargin: styles.spMd
        width: foot._btnW
        text: foot.confirmText
        code: foot.confirmCode
        iconName: foot.confirmIcon
        accent: foot.confirmAccent
        tone: foot.confirmTone
        filled: foot.confirmFilled
        enabled: foot.confirmEnabled
        onClicked: foot.confirm()
    }
}
