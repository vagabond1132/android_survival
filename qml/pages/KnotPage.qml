/**
 * @file KnotPage.qml
 * @brief 绳结主页
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: knotPage
    title: "绳结"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // 进度
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: "#1A237E"
            radius: 8

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                Text {
                    text: "\ue5d2"  // Material Icons: link
                    font.family: "Material Icons"
                    font.pixelSize: 32
                }
                Column {
                    Layout.fillWidth: true
                    Text {
                        text: "学习进度"
                        color: "#B0BEC5"
                        font.pixelSize: 12
                    }
                    Text {
                        text: knotService.learnedCount + " / " + knotService.totalCount
                        color: "white"
                        font.pixelSize: 24
                        font.bold: true
                    }
                }
                Button {
                    text: "重置"
                    flat: true
                    onClicked: knotService.resetProgress()
                }
            }
        }

        // 学习路径
        Text {
            text: "\ue1db 推荐学习路径"  // Material Icons: gps_fixed (target)
            font.family: "Material Icons"
            color: "white"
            font.pixelSize: 16
            font.bold: true
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            clip: true

            model: ServiceListModel {
                id: pathModel
                service: knotService
                method: "getLearningPath"
            }

            Component.onCompleted: refreshPath()

            function refreshPath() {
                // 2026-09-20: 用 ServiceListModel 替代 clear+for+append 模板 (Phase 3)
                Qt.callLater(function() { pathModel.refresh() })
                // 注: index 字段 (i+1) 在 delegate 里用 modelData.length/position 算
            }

            delegate: Rectangle {
                width: ListView.view.width
                height: 64
                color: CommonOptions.colorSurface

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 12

                    // 序号
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 18
                        color: model.learned ? "#388E3C" : "#37474F"
                        Text {
                            anchors.centerIn: parent
                            text: model.learned ? "✓" : (index + 1)  // 2026-09-20: 改用 ListView 内置 index (1-based)
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Text {
                            text: model.nameCn
                            color: CommonOptions.colorText
                            font.pixelSize: 16
                        }
                        Text {
                            text: "难度: " + "★".repeat(model.difficulty)
                            color: "#FFC107"
                            font.pixelSize: 12
                        }
                    }

                    Text {
                        text: "›"
                        color: "#607D8B"
                        font.pixelSize: 24
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // 2026-09-11: 同 Main.qml 修复, 用 Qt.resolvedUrl 显式 qrc 路径
                        ApplicationWindow.window.navBus.navigateTo("KnotDetailPage", {knotId: model.id})
                    }
                }
            }
        }
    }
}
