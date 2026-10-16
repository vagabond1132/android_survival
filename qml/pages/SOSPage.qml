/**
 * @file SOSPage.qml
 * @brief SOS 紧急页面
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: sosPage
    title: "SOS 紧急"

    // 倒计时
    property int countdown: 0
    Timer {
        id: countdownTimer
        interval: 1000
        onTriggered: {
            if (sosPage.countdown > 0) {
                sosPage.countdown--
            } else {
                countdownTimer.stop()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // 顶部警告
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: "#D32F2F"

            Column {
                anchors.centerIn: parent
                spacing: 4
                Text {
                    text: "\ue1b1 紧急情况？"  // Material Icons: sos
                    font.family: "Material Icons"
                    color: "white"
                    font.pixelSize: 22
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "长按下方按钮 3 秒触发 SOS"
                    color: "white"
                    font.pixelSize: 14
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // SOS 大按钮
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 200

            Rectangle {
                id: sosButton
                anchors.centerIn: parent
                width: Math.min(parent.width, 200)
                height: width
                radius: width / 2
                color: pressArea.pressed ? "#B71C1C" : "#D32F2F"

                Behavior on color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: sosPage.countdown > 0 ? sosPage.countdown : "SOS"
                    color: "white"
                    font.pixelSize: sosPage.countdown > 0 ? 72 : 48
                    font.bold: true
                }
            }

            MouseArea {
                id: pressArea
                anchors.fill: sosButton
                onPressed: {
                    sosPage.countdown = 3
                    countdownTimer.start()
                    // 2026-09-20: 修 Bug 16. 之前用 Connections 监听 countdownTimer.onTriggered
                    //   然后调 triggerTimer.interval=1 立即触发, 再 reset 回 3000 ——
                    //   每次 countdownTimer tick 都跑 (每秒 1 次), 多次改 interval 会
                    //   让 QML 内部计时漂移. 改为 triggerTimer.repeat=false 的单次
                    //   Timer, interval=3000, 跟随 onPressed 重启, 跟着 onReleased 停止.
                    triggerTimer.restart()
                }
                onReleased: {
                    if (sosPage.countdown > 0) {
                        sosPage.countdown = 0
                        countdownTimer.stop()
                        triggerTimer.stop()
                    }
                }
            }

            // 2026-09-20: 修 Bug 16. 单次 Timer, 跟随 press/restart, 跟随 release/stop.
            Timer {
                id: triggerTimer
                interval: 3000
                repeat: false
                running: false
                onTriggered: {
                    emergencyService.triggerSOS()
                    sosPage.countdown = 0
                }
            }
        }

        // 快速拨号
        Text {
            text: "快速拨号"
            font.pixelSize: 16
            font.bold: true
            color: "white"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            QuickCallButton {
                Layout.fillWidth: true
                number: "120"
                label: "急救"
                accentColor: "#D32F2F"
            }
            QuickCallButton {
                Layout.fillWidth: true
                number: "110"
                label: "报警"
                accentColor: "#1976D2"
            }
            QuickCallButton {
                Layout.fillWidth: true
                number: "119"
                label: "火警"
                accentColor: "#F57C00"
            }
        }

        // 紧急联系人
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 16
            Label {
                text: "紧急联系人"
                color: "white"
                font.pixelSize: 16
                font.bold: true
                Layout.fillWidth: true
            }
            Button {
                text: "+ 添加"
                flat: true
                onClicked: {
                    // 2026-09-14: signal 上抛, 避免在 Page 内隐式依赖外层 stackView
                    ApplicationWindow.window.navBus.navigateTo("EmergencyContactsPage", {})
                }
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            model: contactList

            // 2026-09-20: 用 ServiceListModel 替代 clear+for+append 模板 (Phase 3)
            ServiceListModel {
                id: contactList
                service: emergencyService
                method: "getContacts"
            }

            Component.onCompleted: refreshContacts()

            function refreshContacts() {
                // 2026-09-20: 用 ServiceListModel 替代 clear+for+append 模板 (Phase 3)
                // Qt.callLater 避免与 Component.onCompleted 的 auto-refresh 冲突.
                Qt.callLater(function() { contactList.refresh() })
            }

            delegate: Rectangle {
                width: ListView.view.width
                height: 56
                color: CommonOptions.colorSurface

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 12
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 18
                        color: model.isPrimary ? "#D32F2F" : "#455A64"
                        Text {
                            anchors.centerIn: parent
                            text: model.isPrimary ? "★" : "●"
                            color: "white"
                        }
                    }
                    Column {
                        Layout.fillWidth: true
                        Text {
                            text: model.name
                            color: CommonOptions.colorText
                            font.pixelSize: 14
                            font.bold: model.isPrimary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: model.phone + " · " + model.relation
                            color: "#90A4AE"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    Button {
                        text: "拨打"
                        flat: true
                        onClicked: emergencyService.callNumber(model.phone)
                    }
                }
            }
        }

        // SOS 状态
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            visible: emergencyService.isSosActive
            color: "#1B5E20"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                Text {
                    text: "\ue5ca SOS 已触发 - 正在救援"  // Material Icons: check
                    font.family: "Material Icons"
                    color: "white"
                    Layout.fillWidth: true
                }
                Button {
                    text: "取消"
                    Material.background: "#D32F2F"
                    onClicked: emergencyService.cancelSOS()
                }
            }
        }
    }

    Connections {
        target: emergencyService
        function onSosTriggered() {
            // 2026-09-20: 修 Bug 17. 之前是 TODO 空 handler.
            //   SOS 触发后用 toast 反馈给用户 (避免用户在 UI 上找反馈, 误以为没成功).
            if (typeof toast !== "undefined" && toast && toast.success) {
                toast.success("SOS 已触发, 等待救援")
            } else {
                console.log("[SOS] triggered")
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            contactList.refreshContacts()
        }
    }
}
