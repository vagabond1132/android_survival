/**
 * @file RouteDetailPage.qml
 * @brief 路线详情 (2026-09-14 UI 改版)
 *
 * 改进:
 *   - 顶部 hero 渐变 + 难度色
 *   - 信息卡 / 评分卡 / 导航卡 / 沿途物种卡 token 化
 *   - 全部颜色走 CommonOptions
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: detailPage
    property string routeId: ""
    // 2026-09-19: 改名 entity, 避开 Item 内置 data property (默认属性),
    // qmlcachegen 静态编译下 `data` 被绑到 children list (non-NOTIFYable),
    // 导致 data 后续赋值时, 所有 binding 不重新求值, 页面所有字段无信息.
    property var entity: ({})

    title: entity.name || "路线详情"

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
                onClicked: detailPage.ApplicationWindow.window.navBus.back()
            }
            Label {
                text: "返回"
                color: "white"
                font.pixelSize: 16
                Layout.fillWidth: true
            }
        }
    }

    // 2026-09-20: 修 Bug 15. 之前 onRouteIdChanged + Component.onCompleted 双触发.
    //   Component.onCompleted 时 routeId 还是空, onRouteIdChanged 时才是有效 id.
    //   只用 onRouteIdChanged. 与 FieldGuideDetailPage / TravelDetailPage 一致.
    onRouteIdChanged: detailPage._loadData()

    function _loadData() {
        if (!routeId) return
        entity = routeService.getById(routeId)
        routeService.incrementVisitCount(routeId)
        var assoc = routeService.getAssociatedSpecies(routeId)
        var plants = []
        var animals = []
        for (var i = 0; i < (assoc.plants || []).length; ++i) {
            var p = plantService.getById(assoc.plants[i])
            if (p && p.id) plants.push(p)
        }
        for (var j = 0; j < (assoc.animals || []).length; ++j) {
            var a = animalService.getById(assoc.animals[j])
            if (a && a.id) animals.push(a)
        }
        associatedSpeciesCol.assocData = {"plants": plants, "animals": animals}
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

            // === 顶部 hero (按难度着色) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                color: {
                    if (entity.difficulty >= 5) return "#B71C1C"
                    if (entity.difficulty >= 4) return CommonOptions.colorDanger
                    if (entity.difficulty >= 3) return CommonOptions.colorWarn
                    if (entity.difficulty >= 2) return "#FBC02D"
                    return CommonOptions.colorSuccess
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
                        text: "难度: " + "★".repeat(entity.difficulty || 0)
                        color: "white"
                        font.pixelSize: styles.fsMd
                    }
                    Text {
                        text: "\ue0c8 " + (entity.province || "") + " · " +
                              (entity.city || "") + " · " +
                              (entity.mountain || "")
                        font.family: "Material Icons"
                        color: "white"
                        font.pixelSize: styles.fsSm
                    }
                }
            }

            // === 关键信息卡 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 120
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

                    InfoItem { label: "距离"; value: (entity.distanceKm || 0) + " km" }
                    InfoItem { label: "时长"; value: (entity.durationHours || 0) + " h" }
                    InfoItem { label: "天数"; value: (entity.daysNeeded || 0) + " 天" }
                    InfoItem { label: "爬升"; value: (entity.elevationGainM || 0) + " m" }
                    InfoItem { label: "最高"; value: (entity.maxAltitudeM || 0) + " m" }
                    InfoItem { label: "最低"; value: (entity.minAltitudeM || 0) + " m" }
                }
            }

            // === 综合评分卡 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 90
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: entity.score >= 80 ? CommonOptions.colorSuccess : entity.score >= 65 ? CommonOptions.colorWarn : CommonOptions.colorDanger
                border.width: 2

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: styles.spMd

                    Rectangle {
                        width: 64; height: 64
                        radius: 32
                        color: entity.score >= 80 ? CommonOptions.colorSuccess : entity.score >= 65 ? CommonOptions.colorWarn : CommonOptions.colorDanger
                        Text {
                            anchors.centerIn: parent
                            text: entity.score || 0
                            color: "white"
                            font.pixelSize: 24
                            font.bold: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            text: "综合评分 (越高越推荐)"
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsMd
                            font.bold: true
                        }
                        Text {
                            text: entity.isWild ? "野线 | " + (entity.routeNature||"穿越") : (entity.routeNature||"穿越")
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsSm
                        }
                        Text {
                            text: {
                                if (entity.score >= 90) return "高度推荐:路况好/补给足/安全"
                                if (entity.score >= 80) return "推荐:适合大众"
                                if (entity.score >= 70) return "良好:需一定经验"
                                if (entity.score >= 60) return "较难:需充分准备"
                                return "高难/高风险:专业选手"
                            }
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsXs
                        }
                    }
                }
            }

            // === 起终点卡 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: startEndCol.implicitHeight + 32
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: CommonOptions.colorAccent
                border.width: 1

                ColumnLayout {
                    id: startEndCol
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: styles.spSm

                    Text {
                        text: "\ue1b7 起终点 (导航)"  // Material Icons: exploration
                        font.family: "Material Icons"
                        color: CommonOptions.colorAccent
                        font.pixelSize: styles.fsMd
                        font.bold: true
                    }

                    // 起点
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm

                        Rectangle {
                            width: 6; Layout.fillHeight: true
                            color: CommonOptions.colorSuccess
                            radius: 3
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "起点: " + (entity.trailheadName || "未提供")
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsMd
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: entity.trailheadAddress || "无详细地址"
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: styles.fsXs
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Text {
                                // 2026-09-28: 修 - 之前 visible 未排除 lat===0 (getById 在
                                //   trailhead 无效时返 0.0), 0 不是 undefined/null → visible
                                //   =true 但 text 三元走 else 分支 → 渲染出空的橙色 warn 行
                                //   (用户报"路线信息详情有问题"). 现要求 lat 有真实非 0 值.
                                visible: entity.trailheadLat !== undefined && entity.trailheadLat !== null
                                         && Number(entity.trailheadLat) !== 0
                                text: "\ue0c8 " + Number(entity.trailheadLat).toFixed(5) + ", " + Number(entity.trailheadLon).toFixed(5)
                                font.family: "Material Icons"
                                color: CommonOptions.colorWarn
                                font.pixelSize: 10
                            }
                        }

                        Button {
                            text: "导航"
                            Material.background: CommonOptions.colorSuccess
                            Material.foreground: "white"
                            font.pixelSize: styles.fsSm
                            onClicked: {
                                if (entity.trailheadLat) {
                                    Qt.openUrlExternally("geo:" + entity.trailheadLat + "," + entity.trailheadLon + "?q=" + encodeURIComponent(entity.trailheadName || "路线起点"))
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.darker(CommonOptions.colorSurface, 1.3)
                    }

                    // 终点
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm

                        Rectangle {
                            width: 6; Layout.fillHeight: true
                            color: CommonOptions.colorDanger
                            radius: 3
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "终点: " + (entity.trailendName || "未提供")
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsMd
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: entity.trailendAddress || "无详细地址"
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: styles.fsXs
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Text {
                                // 2026-09-28: 终点坐标行, 同起点修复 - 排除 lat===0 空 warn 行.
                                visible: entity.trailendLat !== undefined && entity.trailendLat !== null
                                         && Number(entity.trailendLat) !== 0
                                text: "\ue0c8 " + Number(entity.trailendLat).toFixed(5) + ", " + Number(entity.trailendLon).toFixed(5)
                                font.family: "Material Icons"
                                color: CommonOptions.colorWarn
                                font.pixelSize: 10
                            }
                        }

                        Button {
                            text: "导航"
                            Material.background: CommonOptions.colorDanger
                            Material.foreground: "white"
                            font.pixelSize: styles.fsSm
                            onClicked: {
                                if (entity.trailendLat) {
                                    Qt.openUrlExternally("geo:" + entity.trailendLat + "," + entity.trailendLon + "?q=" + encodeURIComponent(entity.trailendName || "路线终点"))
                                }
                            }
                        }
                    }
                }
            }

            Section {
                titleIcon: "\ue87e"  // stars
                title: "亮点"
                items: entity.highlights ? [entity.highlights] : []
                asInline: true
            }

            Section {
                titleIcon: "\ue873"  // description
                title: "路线描述"
                items: entity.description ? [entity.description] : []
                asInline: true
            }

            Section {
                titleIcon: "\ue878"  // event (最佳季节)
                title: "最佳季节"
                items: entity.bestSeason || []
                textColor: CommonOptions.colorWarn
                prefix: "• "
            }

            Section {
                titleIcon: "\ue564"  // terrain (2026-09-19: 之前 \ue52f 是 bicycle, 改 terrain)
                title: "地形"
                items: entity.terrain || []
                textColor: CommonOptions.colorSuccess
                prefix: "• "
            }

            // === 救援卡 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 60
                color: CommonOptions.colorDanger
                radius: styles.rMd
                visible: !!entity.rescuePhone

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd

                    Text {
                        text: "\ue1b1 救援: " + (entity.rescuePhone || "")
                        font.family: "Material Icons"
                        color: "white"
                        font.pixelSize: styles.fsMd
                        Layout.fillWidth: true
                    }
                    Button {
                        text: "拨打"
                        Material.background: "white"
                        Material.foreground: CommonOptions.colorDanger
                        onClicked: emergencyService.callNumber(entity.rescuePhone)
                    }
                }
            }

            // === 沿途物种卡 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                // 2026-09-16: 修复 height binding bug
                implicitHeight: associatedSpeciesCol.implicitHeight + 24
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1
                visible: associatedSpeciesCol.assocData.plants.length > 0 ||
                         associatedSpeciesCol.assocData.animals.length > 0

                ColumnLayout {
                    id: associatedSpeciesCol
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: 6

                    property var assocData: ({"plants": [], "animals": []})
                    property int plantCount: assocData.plants ? assocData.plants.length : 0
                    property int animalCount: assocData.animals ? assocData.animals.length : 0

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "\ue406 沿途物种"  // Material Icons: eco (leaf)
                            font.family: "Material Icons"
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsLg
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: associatedSpeciesCol.plantCount + " 植 / " +
                                  associatedSpeciesCol.animalCount + " 动"
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsSm
                        }
                    }

                    Repeater {
                        model: associatedSpeciesCol.assocData.plants || []
                        delegate: Text {
                            Layout.fillWidth: true
                            text: "▸ 植物: " + modelData.commonName +
                                  "  (Lv" + (modelData.dangerLevel || 0) + ")"
                            color: (modelData.dangerLevel || 0) >= 3 ? CommonOptions.colorDanger : CommonOptions.colorSuccess
                            font.pixelSize: styles.fsMd
                            wrapMode: Text.WordWrap
                        }
                    }

                    Repeater {
                        model: associatedSpeciesCol.assocData.animals || []
                        delegate: Text {
                            Layout.fillWidth: true
                            text: "▸ 动物: " + modelData.commonName +
                                  "  (Lv" + (modelData.dangerLevel || 0) + ")"
                            color: (modelData.dangerLevel || 0) >= 3 ? CommonOptions.colorDanger : CommonOptions.colorWarn
                            font.pixelSize: styles.fsMd
                            wrapMode: Text.WordWrap
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        color: CommonOptions.colorWarn
                        radius: styles.rSm
                        visible: associatedSpeciesCol.plantCount > 0 ||
                                 associatedSpeciesCol.animalCount > 0
                        Text {
                            anchors.fill: parent
                            anchors.margins: 6
                            text: "\ue002 6-9 月注意毒蛇/毒蘑菇,穿高帮鞋,带蛇毒吸附器"  // Material Icons: warning
                            font.family: "Material Icons"
                            color: "white"
                            font.pixelSize: styles.fsXs
                            wrapMode: Text.WordWrap
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            // === 操作按钮 ===
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
                    onClicked: {
                        // 2026-09-21: Phase 5 - addFavorite/deleteFavorite 现在返回 Result.
                        var r = entity.isFavorite
                                ? routeService.deleteFavorite(detailPage.routeId)
                                : routeService.addFavorite(detailPage.routeId)
                        if (r.ok) {
                            entity = routeService.getById(detailPage.routeId)
                        } else {
                            toast.error(r.error.message || "收藏操作失败")
                        }
                    }
                }

                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    text: "查看装备"
                    Material.background: CommonOptions.colorSuccess
                    Material.foreground: "white"
                    // 2026-09-30: 改为进"时节装备推荐"页 — 读路线海拔/天数/难度 +
                    //   用户所选月份, 一键生成可勾选清单 (EquipmentDetailPage).
                    //   之前直接跳 EquipmentPage, 用户还要照抄一遍路线参数.
                    onClicked: {
                        detailPage.ApplicationWindow.window.navBus.navigateTo(
                            "RouteGearRecommendPage",
                            { "routeId": detailPage.routeId })
                    }
                }
            }

            // 2026-09-15: 在地图查看 - push MapPage 并传 routeId, 地图上自动画线 + fit
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
                    // 2026-09-15: 通过 navBus 跳到 MapPage, 并把 routeId 作为 props 传过去
                    // MapPage 启动时读 pendingRouteId, 自动 addOrToggleRoute
                    detailPage.ApplicationWindow.window.navBus.navigateTo("MapPage", { pendingRouteId: detailPage.routeId })
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 24 }
        }
    }
}
