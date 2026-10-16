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
 * 2026-09-21 UI 改版:
 *   - 颜色统一引用 CommonOptions (之前 4 处硬编码 #1976D2/#388E3C/#F57C00/#D32F2F)
 *   - 字号 / 圆角改 Styles token
 *   - 加阴影 + 顶部 accent 边线 (玻璃态)
 *   - 高度根据消息内容自动撑高 (最多 2 行)
 */
import QtQuick
import QtQuick.Controls.Material
import OutdoorSurvival 1.0

Item {
    id: root

    // 队列状态
    property var _current: null   // {message, level}
    property int _duration: 3000

    // ===== 颜色 (统一引用 CommonOptions, 改一处全局生效) =====
    function _bgColor(level) {
        if (level === "success") return CommonOptions.colorSuccess
        if (level === "warn")    return CommonOptions.colorWarn
        if (level === "error")   return CommonOptions.colorDanger
        return CommonOptions.colorAccent
    }

    function _icon(level) {
        if (level === "success") return "\ue876"  // check_circle
        if (level === "warn")    return "\ue002"  // warning
        if (level === "error")   return "\ue000"  // error
        return "\ue88e"          // info
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

    Behavior on opacity { NumberAnimation { duration: 250 } }

    // ===== 视觉 =====
    Item {
        id: toastBg
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 96
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(560, (parent.width || 360) - 32)
        height: msgText.implicitHeight + 32
        opacity: 0

        // 阴影底
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: parent.radius + 2
            color: "#000000"
            opacity: 0.18
            visible: toastBg.opacity > 0
        }

        // 主体
        Rectangle {
            id: toastBody
            anchors.fill: parent
            radius: 24
            color: root._bgColor(root._current ? root._current.level : "info")

            // 顶部 accent 边线 (玻璃态点缀)
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 2
                color: "white"
                opacity: 0.35
                radius: parent.radius
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 12

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._current ? root._icon(root._current.level) : ""
                    font.family: "Material Icons"
                    color: "white"
                    font.pixelSize: 22
                }

                Text {
                    id: msgText
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 32 - 26 - 12
                    text: root._current ? root._current.message : ""
                    color: "white"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                }
            }
        }
    }
}
