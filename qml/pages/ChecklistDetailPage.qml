/**
 * @file ChecklistDetailPage.qml
 * @brief 应急清单详情
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: detailPage
    property string checklistId: ""
    property var entity: ({})

    title: entity.name || "清单"

    // 2026-09-20: 修 Bug 15 (与 Route/TravelDetailPage 一致). 只用 onChecklistIdChanged.
    onChecklistIdChanged: refresh()

    function refresh() {
        if (checklistId) {
            entity = checklistService.getById(checklistId)  // 2026-09-20: rename
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // 顶部信息
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: "#1A237E"
            radius: 8

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: entity.name || ""
                        color: "white"
                        font.pixelSize: 18
                        font.bold: true
                    }
                    Text {
                        text: entity.description || ""
                        color: "#B0BEC5"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
                Column {
                    spacing: 2
                    Text {
                        text: (entity.totalCount || 0) + " 项"
                        color: "white"
                        font.pixelSize: 18
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                    }
                    Text {
                        text: ((entity.totalWeightG || 0) / 1000).toFixed(2) + " kg"
                        color: "#FFEB3B"
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }

        // 进度
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            color: "#37474F"
            radius: 3

            Rectangle {
                width: parent.width * ((entity.checkedCount || 0) / Math.max(1, entity.totalCount || 1))
                height: parent.height
                color: "#4CAF50"
                radius: 3
            }
        }

        // 项目
        ListView {
            id: itemList
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            clip: true

            model: entity.items || []
            delegate: Rectangle {
                width: ListView.view.width
                height: modelData.required ? 56 : 48
                color: CommonOptions.colorSurface
                radius: 4

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 12

                    CheckBox {
                        checked: modelData.checked
                        onClicked: {
                            // 2026-09-21: Phase 5 - setItemChecked 返回 Result.
                            // 失败时 Toast 提示 (错误率高说明 db 已损坏)
                            var r = checklistService.setItemChecked(
                                detailPage.checklistId,
                                modelData.id,
                                checked)
                            if (r && r.ok === false) {
                                toast.error(r.error.message || "勾选失败")
                            }
                            detailPage.refresh()
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: 8
                            Text {
                                text: modelData.required ? "★ " : ""
                                color: CommonOptions.colorDanger
                                font.pixelSize: 14
                            }
                            Text {
                                text: modelData.name
                                color: modelData.checked ? CommonOptions.colorTextMuted : CommonOptions.colorText
                                font.pixelSize: 14
                                font.strikeout: modelData.checked
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "× " + modelData.quantity
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: 12
                            }
                        }
                        Text {
                            text: modelData.category + " · " +
                                  (modelData.weightG * modelData.quantity).toFixed(0) + " g" +
                                  (modelData.note ? " · " + modelData.note : "")
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        // 操作
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                Layout.fillWidth: true
                text: "全部勾选"
                flat: true
                onClicked: {
                    // 2026-09-21: Phase 5 - 批量勾选, 任何一个失败都 Toast
                    for (var i = 0; i < entity.items.length; i++) {
                        var r = checklistService.setItemChecked(
                            detailPage.checklistId,
                            entity.items[i].id, true)
                        if (r && r.ok === false) {
                            toast.error(r.error.message || "勾选失败: " + entity.items[i].name)
                        }
                    }
                    detailPage.refresh()
                }
            }
            Button {
                Layout.fillWidth: true
                text: "全部取消"
                flat: true
                onClicked: {
                    for (var i = 0; i < entity.items.length; i++) {
                        var r = checklistService.setItemChecked(
                            detailPage.checklistId,
                            entity.items[i].id, false)
                        if (r && r.ok === false) {
                            toast.error(r.error.message || "取消失败: " + entity.items[i].name)
                        }
                    }
                    detailPage.refresh()
                }
            }
        }
    }
}
