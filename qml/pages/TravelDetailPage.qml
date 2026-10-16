/**
 * @file TravelDetailPage.qml
 * @brief 自驾游路线详情 (2026-09-14 UI 改版)
 *
 * 改进: token 化 + 卡片化 + hero 渐变
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: travelDetailPage
    property string travelId: ""
    // 2026-09-19: 改名 entity, 避开 Item 内置 data property (默认属性),
    // qmlcachegen 静态编译下 `data` 被绑到 children list (non-NOTIFYable),
    // 导致 data 后续赋值时, 所有 binding 不重新求值, 页面所有字段无信息.
    property var entity: ({})

    title: entity.name || "自驾游详情"

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    // 2026-09-16: 顶部工具栏 + 返回按钮 (系统返回键不灵时用)
    header: ToolBar {
        Material.foreground: "white"
        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8
            ToolButton {
                text: "‹"
                font.pixelSize: 28
                onClicked: travelDetailPage.ApplicationWindow.window.navBus.back()
            }
            Label {
                text: "返回"
                color: "white"
                font.pixelSize: 16
                Layout.fillWidth: true
            }
        }
    }

    // 2026-09-20: 修 Bug 15. 之前 onTravelIdChanged + Component.onCompleted 双触发,
    //   Component.onCompleted 时 travelId 还是空 (Qt 6.x qmlcachegen 顺序), 跑一次空 load
    //   然后 onTravelIdChanged 再跑一次 (有效 id), 浪费 + 偶发 visit count 跳 2.
    //   只用 onTravelIdChanged. 与 FieldGuideDetailPage 保持一致.
    onTravelIdChanged: travelDetailPage._loadData()

    function _loadData() {
        if (!travelId) return
        entity = travelService.getById(travelId)
        travelService.incrementVisitCount(travelId)
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

            // === 顶部 hero (统一深青绿) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 130
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
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Text {
                        text: "\ue0c8 " + (entity.province || "")
                        font.family: "Material Icons"
                        color: "#BBDEFB"
                        font.pixelSize: styles.fsSm
                    }
                    Text {
                        text: "\ue531 " + (entity.distanceKm || 0) + " km  ·  \ue425 " + (entity.days || 0) + " 天  ·  \ue989 ≈¥" + (entity.fuelCostCNY || 0)
                        font.family: "Material Icons"
                        color: "#BBDEFB"
                        font.pixelSize: styles.fsMd
                    }
                }
            }

            // === 起终点导航卡 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 120
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: CommonOptions.colorAccent
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: styles.spSm

                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle { width: 6; Layout.fillHeight: true; color: CommonOptions.colorSuccess; radius: 3 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { text: "起点: " + (entity.startName || ""); color: CommonOptions.colorText; font.pixelSize: styles.fsMd; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: entity.startCity || ""; color: CommonOptions.colorTextMuted; font.pixelSize: styles.fsXs }
                        }
                        Button {
                            text: "导航"
                            Material.background: CommonOptions.colorSuccess
                            Material.foreground: "white"
                            font.pixelSize: styles.fsSm
                            onClicked: {
                                if (entity.startLat) {
                                    Qt.openUrlExternally("geo:" + entity.startLat + "," + entity.startLon + "?q=" + encodeURIComponent(entity.startName || "起点"))
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle { width: 6; Layout.fillHeight: true; color: CommonOptions.colorDanger; radius: 3 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { text: "终点: " + (entity.endName || ""); color: CommonOptions.colorText; font.pixelSize: styles.fsMd; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: entity.endCity || ""; color: CommonOptions.colorTextMuted; font.pixelSize: styles.fsXs }
                        }
                        Button {
                            text: "导航"
                            Material.background: CommonOptions.colorDanger
                            Material.foreground: "white"
                            font.pixelSize: styles.fsSm
                            onClicked: {
                                if (entity.endLat) {
                                    Qt.openUrlExternally("geo:" + entity.endLat + "," + entity.endLon + "?q=" + encodeURIComponent(entity.endName || "终点"))
                                }
                            }
                        }
                    }
                }
            }

            // === 关键信息卡 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 90
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    columns: 2
                    rowSpacing: styles.spSm
                    columnSpacing: styles.spSm
                    InfoItem { label: "里程"; value: (entity.distanceKm || 0) + " km" }
                    InfoItem { label: "天数"; value: (entity.days || 0) + " 天" }
                    InfoItem { label: "驾驶时长"; value: (entity.driveHours || 0) + " h" }
                    InfoItem { label: "最高海拔"; value: (entity.maxAltitude || 0) + " m" }
                }
            }

            Section { titleIcon: "\ue922"; title: "路面类型"; items: entity.roadType ? [entity.roadType] : []; asInline: true }  // route
            Section { titleIcon: "\ue989"; title: "沿途补给"; items: entity.supply ? entity.supply.split(/[,、]/) : []; asInline: true }  // local_gas_station
            Section { titleIcon: "\ue878"; title: "最佳季节"; items: entity.bestSeason || []; textColor: CommonOptions.colorWarn; prefix: "• " }  // event
            Section { titleIcon: "\ue87e"; title: "沿途亮点"; items: entity.highlights ? entity.highlights.split(/[,、]/) : []; textColor: CommonOptions.colorSuccess; prefix: "• " }  // stars
            Section { titleIcon: "\ue873"; title: "路线描述"; items: entity.description ? [entity.description] : []; asInline: true }  // description

            // 收藏按钮
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                spacing: styles.spSm

                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    text: entity.isFavorite ? "★ 已收藏" : "☆ 收藏"
                    Material.background: entity.isFavorite ? CommonOptions.colorWarn : CommonOptions.colorAccent
                    Material.foreground: "white"
                    font.pixelSize: styles.fsLg
                    onClicked: {
                        // 2026-09-21: Phase 5 - addFavorite/deleteFavorite 现在返回 Result.
                        var r = entity.isFavorite
                                ? travelService.deleteFavorite(travelDetailPage.travelId)
                                : travelService.addFavorite(travelDetailPage.travelId)
                        if (r.ok) {
                            entity = travelService.getById(travelDetailPage.travelId)
                        } else {
                            toast.error(r.error.message || "收藏操作失败")
                        }
                    }
                }
            }

            // 2026-09-15: 在地图查看 - 跳到 MapPage 并传 pendingTravelId
            Button {
                Layout.fillWidth: true
                Layout.leftMargin: styles.spLg
                Layout.rightMargin: styles.spLg
                Layout.preferredHeight: 50
                text: "\ue55b 在地图查看"  // Material Icons: map
                font.family: "Material Icons"
                Material.background: CommonOptions.colorAccent
                Material.foreground: "white"
                font.pixelSize: styles.fsMd
                font.bold: true
                onClicked: {
                    travelDetailPage.ApplicationWindow.window.navBus.navigateTo(
                        "MapPage", { pendingTravelId: travelDetailPage.travelId })
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spLg }
        }
    }
}
