/**
 * @file ChecklistPage.qml
 * @brief 强装检查 - 出门前逐项核对
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: checklistPage
    property string listId: ""
    property var entity: ({})

    title: "强装检查"
    // 2026-09-20: 修 Bug 15 (与 Route/TravelDetailPage 一致). 只用 onListIdChanged.
    onListIdChanged: refresh()

    // 2026-09-28: 声明式统计量 - 之前进度文案/进度条硬编码为 0, 页面永远显示
    //   "完成度 0%", 用户以为强装检查坏了. refresh() 后 entity 变化自动重算.
    readonly property int totalItems: (entity.critical ? entity.critical.length : 0)
                                    + (entity.important ? entity.important.length : 0)
                                    + (entity.recommended ? entity.recommended.length : 0)
                                    + (entity.optional ? entity.optional.length : 0)
    readonly property int checkedItems: entity.checkedCount || 0
    readonly property int progressPct: totalItems > 0 ? Math.round(checkedItems * 100 / totalItems) : 0

    function refresh() {
        if (listId) {
            entity = equipmentService.getList(listId)
        }
    }

    // 2026-09-28: 勾选写回后刷新 (与 EquipmentDetailPage 同构).
    //   CategorySection 的 CheckBox 调 equipmentService.setItemChecked 会 emit
    //   listModified, 这里接住刷新 entity, 否则勾选态不持久回显.
    Connections {
        target: equipmentService
        function onListModified(listId) {
            if (listId === checklistPage.listId) {
                checklistPage.refresh()
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: parent.width
        contentHeight: contentColumn.height
        clip: true

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: 0

            // 进度
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                color: "#1A237E"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 4

                    Text {
                        text: entity.name || ""
                        color: "white"
                        font.pixelSize: 16
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            id: progressLabel
                            // 2026-09-28: 接真实进度 (之前硬编码 "完成度 0%")
                            text: "完成度 " + checklistPage.progressPct + "%"
                            color: "white"
                            font.pixelSize: 14
                            Layout.fillWidth: true
                        }
                        Text {
                            // 2026-09-28: 接真实勾选数 + 总重量 (之前硬编码 "已勾选 0 项")
                            text: "已勾选 " + checklistPage.checkedItems + "/"
                                  + checklistPage.totalItems + " 项 · "
                                  + ((entity.totalWeightG || 0) / 1000).toFixed(2) + " kg"
                            color: "#B0BEC5"
                            font.pixelSize: 12
                        }
                    }
                }
            }

            // 进度条
            ProgressBar {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                from: 0; to: 100
                // 2026-09-28: 接真实进度 (之前硬编码 value: 0)
                value: checklistPage.progressPct
            }

            // === 必带/强必带/推荐/可选 ===
            // 2026-09-23: 修 - 之前用 Section { items: entity.critical || [] }, Section
            //   内部把 model.value 整个 String() 出来, 而 entity.critical 是
            //   [{id, name, weightG}] 对象数组 → 显示 "[object Object]" / "object object".
            //   改用 CategorySection (EquipmentDetailPage 同构), 委托里取 item.name.
            CategorySection {
                titleIcon: "\ue1b1"  // Material Icons: report_problem
                title: "必带（绝对关键）"
                accentColor: CommonOptions.colorDanger
                items: entity.critical || []
                listId: checklistPage.listId
            }
            CategorySection {
                titleIcon: "\ue002"  // Material Icons: warning
                title: "强必带"
                accentColor: CommonOptions.colorWarn
                items: entity.important || []
                listId: checklistPage.listId
            }
            CategorySection {
                titleIcon: "\ue838"  // Material Icons: star
                title: "推荐"
                accentColor: "#FBC02D"
                items: entity.recommended || []
                listId: checklistPage.listId
            }
            CategorySection {
                titleIcon: ""
                title: "可选"
                accentColor: CommonOptions.colorTextMuted
                items: entity.optional || []
                listId: checklistPage.listId
            }

            // 完成按钮
            Rectangle {
                Layout.fillWidth: true
                // 2026-09-28: 100 -> 156, 容纳新增的「删除此清单」按钮 (用户反馈
                //   强装检查页无删除入口, 只能进装备详情页删).
                Layout.preferredHeight: 156
                color: "#1E272E"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    Button {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 50
                        text: "\ue5ca  全部确认完成"  // Material Icons: check
                        font.family: "Material Icons"
                        Material.background: "#4CAF50"
                        font.pixelSize: 16
                        onClicked: completeCheck()
                    }

                    // 2026-09-28: 删除此清单 (与 EquipmentDetailPage 同构, 调 deleteList)
                    Button {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        text: "\ue872  删除此清单"  // Material Icons: delete
                        font.family: "Material Icons"
                        Material.background: CommonOptions.colorDanger
                        Material.foreground: "white"
                        onClicked: confirmDeleteDialog.open()
                    }
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 24 }
        }
    }

    function completeCheck() {
        if (entity.isCompleted) {
            toast.info("已记录本次强装检查完成")  // 2026-09-20: 切 Toast
        } else {
            confirmDialog.open()
        }
    }

    // 2026-09-28: 删除清单确认 Dialog
    Dialog {
        id: confirmDeleteDialog
        title: "删除清单"
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.92, 420)
        standardButtons: Dialog.Yes | Dialog.No
        contentItem: Text {
            width: parent && parent.width ? Math.min(parent.width - 40, 400) : 360
            text: "确定要删除清单 \"" + (entity.name || "") + "\" 吗？\n此操作不可撤销。"
            color: CommonOptions.colorText
            wrapMode: Text.WordWrap
        }
        onAccepted: {
            if (equipmentService && checklistPage.listId) {
                var r = equipmentService.deleteList(checklistPage.listId)
                if (r && r.ok === false) {
                    toast.error(r.error.message || "删除清单失败")
                } else {
                    toast.success("已删除")
                    checklistPage.ApplicationWindow.window.navBus.back()
                }
            }
        }
    }

    Dialog {
        id: confirmDialog
        title: "确认"
        anchors.centerIn: parent
        standardButtons: Dialog.Yes | Dialog.No
        Label {
            text: "还有装备未勾选，确定完成？"
            color: "white"
        }
        onAccepted: {
            toast.info("已记录（部分勾选）")  // 2026-09-20: 切 Toast
        }
    }

    // 2026-09-20: infoDialog 已切 Toast (统一反馈), 此处删除
}
