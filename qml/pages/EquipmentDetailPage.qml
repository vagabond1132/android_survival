/**
 * @file EquipmentDetailPage.qml
 * @brief 装备清单详情 (2026-09-14 UI 改版)
 *
 * 改进: token 化 + hero 渐变 + 分类卡 token 化
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: detailPage
    property string listId: ""
    property var entity: ({})

    title: entity.name || "装备清单"

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    // 2026-09-20: 修 Bug 15 (与 Route/TravelDetailPage 一致). 之前
    //   Component.onCompleted: refresh() 在 listId 还未设置时跑 (空 load), 然后
    //   onListIdChanged (虽然没显式声明) 隐式触发再跑一次. 改用 onListIdChanged 单次加载.
    onListIdChanged: refresh()

    // 2026-09-28: 总件数声明式统计 - 检查进度卡之前硬编码 "0 / 0",
    //   勾选后数字不动. entity 变化自动重算.
    readonly property int totalItems: (entity.critical ? entity.critical.length : 0)
                                    + (entity.important ? entity.important.length : 0)
                                    + (entity.recommended ? entity.recommended.length : 0)
                                    + (entity.optional ? entity.optional.length : 0)

    function refresh() {
        if (listId) {
            entity = equipmentService.getList(listId)
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

            // 2026-09-14: 顶部工具栏 - 返回
            PageHeader {
                title: entity.name || "装备清单"
            }

            // === 顶部 hero (统一深青绿) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                color: "#00695C"  // 深青绿
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00695C" }
                    GradientStop { position: 1.0; color: "#00897B" }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spLg
                    spacing: 4

                    Text {
                        text: entity.name || ""
                        color: "white"
                        font.pixelSize: styles.fs2xl
                        font.bold: true
                    }
                    Text {
                        text: "\ue0c8 最高海拔 " + (entity.altitudeMax || 0) + "m  ·  " +
                              "行程 " + (entity.days || 1) + " 天  ·  " +
                              "难度 " + (entity.difficulty || 1) + " 星"
                        font.family: "Material Icons"
                        color: "#FFE0B2"
                        font.pixelSize: styles.fsSm
                    }
                    Text {
                        text: "\ue6dd 总重量: " + ((entity.totalWeightG || 0) / 1000).toFixed(2) + " kg"
                        font.family: "Material Icons"
                        color: "white"
                        font.pixelSize: styles.fsMd
                        font.bold: true
                    }
                }
            }

            // === 检查进度卡 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 48
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: CommonOptions.colorAccent
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    Text {
                        text: "\ue5ca 强装检查进度"  // Material Icons: check
                        font.family: "Material Icons"
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsMd
                        Layout.fillWidth: true
                    }
                    Text {
                        id: progressText
                        // 2026-09-28: 接真实数据 (之前硬编码 "0 / 0", 勾选后不动)
                        text: (entity.checkedCount || 0) + " / " + detailPage.totalItems
                        color: CommonOptions.colorSuccess
                        font.pixelSize: styles.fsMd
                        font.bold: true
                    }
                }
            }

            CategorySection {
                titleIcon: "\ue1b1"  // Material Icons: report_problem
                title: "必带 (绝对关键)"
                accentColor: CommonOptions.colorDanger
                items: entity.critical || []
                listId: detailPage.listId
            }
            CategorySection {
                titleIcon: "\ue002"  // Material Icons: warning
                title: "强必带"
                accentColor: CommonOptions.colorWarn
                items: entity.important || []
                listId: detailPage.listId
            }
            CategorySection {
                titleIcon: "\ue838"  // Material Icons: star
                title: "推荐"
                accentColor: "#FBC02D"
                items: entity.recommended || []
                listId: detailPage.listId
            }
            CategorySection {
                titleIcon: ""  // 可选无 icon
                title: "可选"
                accentColor: CommonOptions.colorTextMuted
                items: entity.optional || []
                listId: detailPage.listId
            }

            // === 底部操作 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 140
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: styles.spSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm
                        Button {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            text: "\ue153 强装检查"  // Material Icons: fact_check
                            font.family: "Material Icons"
                            Material.background: CommonOptions.colorAccent
                            Material.foreground: "white"
                            onClicked: ApplicationWindow.window.navBus.navigateTo("ChecklistPage", {listId: detailPage.listId})
                        }
                        Button {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            text: "\ue873 导出"  // Material Icons: description
                            font.family: "Material Icons"
                            Material.background: CommonOptions.colorWarn
                            Material.foreground: "white"
                            onClicked: exportPdf()
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        text: "\ue872 删除此清单"  // Material Icons: delete
                        font.family: "Material Icons"
                        Material.background: CommonOptions.colorDanger
                        Material.foreground: "white"
                        onClicked: confirmDeleteDialog.open()
                    }
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spLg }
        }
    }

    function exportPdf() {
        // 2026-09-21: 之前写 /sdcard/Download/... 在 Android 11+ scoped storage 下
        //   必失败 (无 MANAGE_EXTERNAL_STORAGE 权限), 返回 "导出失败".
        //   改用 app 私有外部目录 (Android: /sdcard/Android/data/<pkg>/files/Download/),
        //   不需要任何运行时权限, 卸载 app 时自动清理.
        var basePath = ""
        if (typeof App !== "undefined" && App && App.dataPath) {
            basePath = App.dataPath + "/Download"
        } else {
            // 兜底: 标准路径 (在 QML 没拿到 App 时)
            basePath = "/sdcard/Android/data/com.outdoor.survival/files/Download"
        }
        // 简单的目录创建 (Qt 不提供 QDir.mkdir 在 QML 里, 用 XMLHttpRequest
        // 方式失败, 直接尝试写, 若失败 fallback 路径).
        var safeName = (entity.name || "装备清单").replace(/[\/\\:*?"<>|]/g, "_")
        var path = basePath + "/" + safeName + ".txt"
        var result = equipmentService.exportToPdf(detailPage.listId, path)
        if (result && result.indexOf && result.indexOf("失败") >= 0) {
            // 二次尝试: 写进 QStandardPaths 文档目录
            toast.warn("尝试清单文件目录...")
            var altPath = "/sdcard/Android/data/com.outdoor.survival/files/" + safeName + ".txt"
            var result2 = equipmentService.exportToPdf(detailPage.listId, altPath)
            if (result2 && result2.indexOf && result2.indexOf("失败") >= 0) {
                toast.error("导出失败: 无写权限")
            } else {
                toast.success("已导出: " + altPath)
            }
        } else {
            toast.success(result || "导出成功")
        }
    }

    // 2026-09-20: infoDialog 已切 Toast (统一反馈), 此处删除

    // 2026-09-19: 删除清单确认 Dialog
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
            // 2026-09-21: Phase 5 - deleteList 返回 Result.
            if (equipmentService && detailPage.listId) {
                var r = equipmentService.deleteList(detailPage.listId)
                if (r && r.ok === false) {
                    toast.error(r.error.message || "删除清单失败")
                } else {
                    detailPage.ApplicationWindow.window.navBus.back()
                }
            }
        }
    }

    Connections {
        target: equipmentService
        function onListModified(listId) {
            if (listId === detailPage.listId) {
                detailPage.refresh()
            }
        }
    }
}
