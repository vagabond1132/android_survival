/**
 * @file Toast.qml
 * @brief 统一错误反馈组件 (5 阶段架构重构 Phase 3 + Phase 5 接入)
 *
 * 设计:
 *   - 普通组件,Main.qml 顶层 Window 实例化 1 次 (id: toast)
 *   - 4 级别: info / success / warn / error (颜色统一引用 CommonOptions)
 *   - 自动隐藏: 3 秒后渐隐
 *   - 队列: 同时只显示 1 个,新消息打断旧的
 *   - 玻璃态: 半透明背景 + 阴影 + 顶部 accent 边线
 *
 * 接入模式:
 *   import OutdoorSurvival 1.0
 *   toast.success("已保存")         // toast 是 Main.qml 的 id
 *   toast.error(result.error.message)
 *
 * 2026-09-21 UI 改版: 颜色收口 CommonOptions, 字号/圆角改 Styles token, 加阴影.
 * 2026-10-16 整体改版:
 *   - 图标从裸 PUA 码位 + 手设 font.family 改为 IconLabel { name: ... }.
 *     原先那个 Text 一旦漏绑 family 就变方框 (真机出现过).
 *   - 渐隐 Behavior 从 root (Item, opacity 恒为 1) 移到真正变化的 toastBg 上.
 *     放在 root 上永远不会触发, 导致 toast 是"突然消失"而不是渐隐.
 *   - 尺寸/间距全部走 styles.*.
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: root

    Styles { id: styles; visible: false }

    // 队列状态
    property var _current: null   // {message, level}
    property int _duration: 3000

    // ===== 颜色 / 图标 (统一引用 CommonOptions + IconLabel 语义名) =====
    function _bgColor(level) {
        if (level === "success") return CommonOptions.colorSuccess
        if (level === "warn")    return CommonOptions.colorWarn
        if (level === "error")   return CommonOptions.colorDanger
        return CommonOptions.colorAccent
    }
    function _iconName(level) {
        // 2026-10-19: 原来返回 "check_circle" (\ue876). 逐码位渲染核对后确认本字体
        //   该码位不是勾圈, 且该语义名已从 IconLabel 表中删除 → 图标渲染成空白.
        //   改用实测有勾形的 "check".
        if (level === "success") return "check"
        if (level === "warn")    return "warning"
        if (level === "error")   return "error"
        return "info"
    }

    // ===== 公开 API =====
    function info(msg)    { _show(msg, "info") }
    function success(msg) { _show(msg, "success") }
    function warn(msg)    { _show(msg, "warn") }
    function error(msg)   { _show(msg, "error") }

    function _show(message, level) {
        _current = {message: message, level: level}
        toastBg.opacity = 1
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: root._duration
        repeat: false
        onTriggered: toastBg.opacity = 0
    }

    // ===== 视觉 =====
    Item {
        id: toastBg
        anchors.bottom: parent.bottom
        anchors.bottomMargin: styles.spXl * 4
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(560, (parent.width || 360) - styles.pageMargin * 2)
        height: Math.max(styles.rowHSm, msgText.implicitHeight + styles.cardPad * 2)
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        // 阴影底 (墨色 18% —— 用 colorText 而不是裸 #000000, 换肤时阴影跟着走)
        Rectangle {
            anchors.fill: parent
            anchors.margins: -styles.spXs
            radius: toastBody.radius + styles.lineAccent
            color: CommonOptions.withAlpha(CommonOptions.colorText, 0.18)
            visible: toastBg.opacity > 0
        }

        // 主体
        Rectangle {
            id: toastBody
            anchors.fill: parent
            radius: height / 2   // 胶囊: 高度随消息行数变, 圆角跟着走
            color: root._bgColor(root._current ? root._current.level : "info")

            // 顶部 accent 边线 (玻璃态点缀)
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: styles.lineHair
                color: CommonOptions.withAlpha(CommonOptions.colorTextOnAccent, 0.35)
                radius: parent.radius
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: styles.spLg
                anchors.rightMargin: styles.spLg
                anchors.topMargin: styles.spSm
                anchors.bottomMargin: styles.spSm
                spacing: styles.spMd

                IconLabel {
                    name: root._current ? root._iconName(root._current.level) : ""
                    size: styles.icLg
                    tintColor: CommonOptions.colorTextOnAccent
                }

                Text {
                    id: msgText
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root._current ? root._current.message : ""
                    color: CommonOptions.colorTextOnAccent
                    font.pixelSize: styles.fsMd
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                }
            }
        }
    }
}
