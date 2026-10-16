/**
 * @file SOSButton.qml
 * @brief SOS 浮动按钮
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Rectangle {
    id: sosBtn
    width: 56
    height: 56
    radius: 28
    color: pressedArea.pressed ? "#B71C1C" : "#D32F2F"
    border.color: "white"
    border.width: 2

    property int pressDuration: 0
    // 关键: 不能同时有 property triggered 和 signal triggered (同名冲突)
    // 改名为 m_triggered (内部状态), signal triggered() 保留 (外部响应)
    property bool m_triggered: false

    signal triggered()

    Behavior on color {
        ColorAnimation { duration: 200 }
    }

    // 2026-09-11: 缩 200x80 → 56x56 圆形, 单字符 🆘 / 倒计时秒数
    Text {
        anchors.centerIn: parent
        text: sosBtn.pressDuration > 0
              ? (sosBtn.pressDuration + "s")
              : "\ue1b1"  // Material Icons: sos
        font.family: "Material Icons"
        color: "white"
        font.pixelSize: sosBtn.pressDuration > 0 ? 18 : 26
        font.bold: true
    }

    Timer {
        id: pressTimer
        interval: 100
        repeat: true
        onTriggered: {
            sosBtn.pressDuration = Math.min(3, sosBtn.pressDuration + 1)
            if (sosBtn.pressDuration >= 3) {
                sosBtn.m_triggered = true
                sosBtn.pressDuration = 0
                pressTimer.stop()
                releaseTimer.start()
                sosBtn.triggered()
            }
        }
    }

    Timer {
        id: releaseTimer
        interval: 2000
        onTriggered: sosBtn.m_triggered = false
    }

    MouseArea {
        id: pressedArea
        anchors.fill: parent
        onPressed: {
            if (!sosBtn.m_triggered) {
                sosBtn.pressDuration = 0
                pressTimer.start()
            }
        }
        onReleased: {
            pressTimer.stop()
            if (sosBtn.pressDuration < 3) {
                sosBtn.pressDuration = 0
            }
        }
    }
}
