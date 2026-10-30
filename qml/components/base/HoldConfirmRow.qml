/**
 * @file HoldConfirmRow.qml
 * @brief 长按确认行 — ⑤求助页的号码/SOS 入口 (2026-10-20 丁骨架 v8)
 *
 * 为什么不用普通按钮: 「地物图例」⑤ 的评审结论是"号码只有列表 + 长按 2 秒进度条,
 * 没有任何自动拨号". 改版前这里是一颗 tap-to-dial 的 QuickCallButton, 口袋里误触
 * 就把 120 拨出去了 —— 户外求救电话占线是实打实的公共资源损失.
 * 长按把"决定"从一次点击拉成两秒, 两秒里随时松手就取消, 且进度条本身就是可读的
 * 状态 (0% → 100%), 不需要额外的确认弹窗.
 *
 * 分工: 本件只负责"什么时候算确认了"(发 confirmed 信号), 拨号/触发交给页面.
 * 好处是进度语义能同时给 120/110/119 和 SOS 触发复用, 而 SOS 那条要 3 秒.
 */

import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

// 2026-10-22 #96(c): 条内刻痕的 Repeater delegate 要读外层 styles(lineHair),
// qmlcachegen 静态编译下没有 Bound 语义就是静默 ReferenceError (同 [[qml-delegate-outer-id-pragma]]).
pragma ComponentBehavior: Bound

Rectangle {
    id: hold

    Styles { id: styles; visible: false }

    property string code: ""            // 左上方块里的号码 / "SOS"
    property string title: ""
    property string subtitle: ""
    property color accent: CommonOptions.colorHazard
    property int holdMs: 2000
    /// false 时按下不计时 (还没定位、SOS 已在进行等状态下用)
    property bool confirmable: true
    /// 0..1, 只读给外部看 (页面用它决定文案是否变"已确认")
    readonly property real progress: hold.progressValue
    signal confirmed()

    property real progressValue: 0

    /// 按住需要的整秒数 (2000→2, 3000→3); 文字与刻痕都以它为准, 不各写一份
    readonly property int _holdSeconds: Math.max(1, Math.round(holdMs / 1000))

    /// 条内整秒刻痕的位置 (0..1, 不含两端): 2 秒→[0.5], 3 秒→[1/3, 2/3]
    readonly property var tickFractions: {
        var out = []
        for (var i = 1; i < _holdSeconds; ++i) out.push(i / _holdSeconds)
        return out
    }

    /// 条下文字: 平时说要按多久, 按住之后改成还剩多久
    readonly property string holdLabel: progressValue <= 0
        ? ("长按 " + _holdSeconds + " 秒")
        : ("还需 " + ((1 - progressValue) * _holdSeconds).toFixed(1) + " 秒")

    // implicitHeight 而不是 height: 本件常被放进 ColumnLayout, 写死 height 的话
    // 布局只读到 implicitHeight=0, 整张号码卡会塌成一条线.
    implicitHeight: styles.touchMin
    color: CommonOptions.colorSurface
    // 按住时整行描边压成主色: 手套下看不清 9px 进度条时, 边框是第二处反馈
    border.color: fillAnim.running ? hold.accent : CommonOptions.colorRule
    border.width: styles.lineHair

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: styles.cardPad
        anchors.rightMargin: styles.cardPad
        spacing: styles.spSm

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: styles.numChip
            Layout.preferredHeight: styles.numChip
            radius: styles.rSm
            // 未确认时是实心 (号码要认得出), 确认后不返色, 靠松手回到 0%
            color: hold.accent
            Text {
                anchors.centerIn: parent
                text: hold.code
                font.family: styles.monoFont
                font.pixelSize: styles.fsXs
                font.bold: true
                color: CommonOptions.colorOnInk
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: hold.title
                font.pixelSize: styles.fsMd
                font.bold: true
                color: CommonOptions.colorText
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: hold.subtitle.length > 0
                text: hold.subtitle
                // 副标题里一定有汉字 ("不自动拨号 · 长按进度条确认"), 所以这一行不能进
                // monoFont: Android 的 monospace 族没汉字字形, 真机上混排的那几个字会出方框
                // (Dial 盘心副行同一个坑). 只有左边号码块和右侧进度条是纯数字才用等宽.
                font.pixelSize: styles.fsXs
                color: CommonOptions.colorTextDim
                elide: Text.ElideRight
            }
        }

        // 进度条 + 时长读数 —— 2026-10-22 #96(c):
        //   原来只有 52×9 的空心框, 第一次用根本读不出"要按多久" (⑤页 120 是 2 秒,
        //   SOS 是 3 秒, 差 1 秒在保命动作上不是小事). 现在补两样:
        //   ① 条下文字: 平时写"长按 2 秒", 按住之后改成剩余秒数, 松手立刻回原文;
        //   ② 条内按整秒切 1px 刻痕 (用行底色切断, 不加透明度, 保持全站硬边),
        //      让"还要按几格"不看字也能比长度.
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: styles.holdBarW
                Layout.preferredHeight: styles.holdBarH
                color: CommonOptions.colorSurfaceAlt
                border.color: CommonOptions.colorText
                border.width: styles.lineHair

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.round(parent.width * hold.progressValue)
                    color: hold.accent
                }

                Repeater {
                    model: hold.tickFractions
                    delegate: Rectangle {
                        required property var modelData
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.leftMargin: Math.round(parent.width * modelData)
                        width: styles.lineHair
                        // 刻痕颜色 = 本行底色: 等于把条子"切断"而不是在上面盖一层
                        color: CommonOptions.colorSurface
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: hold.holdLabel
                // 汉字读数不进 mono (Android monospace 无汉字字形 → 方框)
                font.pixelSize: styles.fsXs
                font.letterSpacing: 0
                color: CommonOptions.colorTextDim
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: hold.confirmable
        cursorShape: hold.confirmable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: fillAnim.start()
        // 松手 / 手指滑出 / 被系统抢走触摸, 三种中断都要清零, 否则进度条会停在半格
        // 看起来像"再按一点点就通了".
        onReleased: hold.abort()
        onCanceled: hold.abort()
    }

    NumberAnimation {
        id: fillAnim
        target: hold
        property: "progressValue"
        from: 0
        to: 1
        duration: hold.holdMs
        onFinished: {
            hold.progressValue = 1
            hold.confirmed()
            // 立刻回零: 确认后页面会切状态 (拨号盘已拉起 / SOS 进行中),
            // 进度条留满格反而像"还在等第二次确认".
            hold.progressValue = 0
        }
    }

    function abort() {
        fillAnim.stop()
        hold.progressValue = 0
    }
}
