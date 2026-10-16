/**
 * @file RouteGearRecommendPage.qml
 * @brief 路线 · 时节装备推荐 (2026-09-30 新增)
 *
 * 背景:
 *   RouteDetailPage 的「查看装备」原本直接跳 EquipmentPage (装备清单生成器表单),
 *   用户需要自己再填海拔/天数/难度/季节才能生成 → 路线已有的参数白填一遍.
 *   本页面改为: 读路线参数 (海拔/天数/难度) + 用户选择的时节, 一键生成
 *   "可勾选"装备清单 (EquipmentDetailPage: 勾选 / 强装检查 / 导出 PDF).
 *
 * 设计要点:
 *   - 时节选择器粒度 = 月份 1-12 (路线数据 best_season 就是 "5月" 这类月份 token,
 *     可直接比对; 月份再映射为 EquipmentService::Season 喂给规则引擎)
 *   - 默认选中当前月, 页面内可随时切换
 *   - 展示"该路线适游季"并与所选月份做匹配提示 (仅供参考, 不限制生成)
 *   - 其余环境维度 (降水/湿度/UV/风级/地区标记) 沿用 EquipmentPage 默认值,
 *     避免本页变成第二张长表单; 海拔相关的高原标记由 C++ 端按海拔自动推断
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: gearPage
    property string routeId: ""
    property var entity: ({})
    // 生成中标志, 防连点 (生成含磁盘写入)
    property bool _generating: false

    // 所选时节: 月份 1-12, 默认当前月
    property int selectedMonth: new Date().getMonth() + 1

    title: "时节装备推荐"

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    // 月份 -> EquipmentService::Season 枚举 (0 春 / 1 夏 / 2 秋 / 3 冬)
    readonly property int seasonIndex: {
        if (selectedMonth >= 3 && selectedMonth <= 5) return 0
        if (selectedMonth >= 6 && selectedMonth <= 8) return 1
        if (selectedMonth >= 9 && selectedMonth <= 11) return 2
        return 3
    }
    readonly property var seasonNames: ["春季", "夏季", "秋季", "冬季"]

    // 路线适游季 "5月" -> [5]; 用于网格高亮 + 匹配提示
    readonly property var bestSeasonMonths: {
        var arr = entity.bestSeason || []
        var out = []
        for (var i = 0; i < arr.length; ++i) {
            var n = parseInt(arr[i])
            if (!isNaN(n) && n >= 1 && n <= 12) out.push(n)
        }
        return out
    }
    readonly property bool monthInBestSeason: bestSeasonMonths.indexOf(selectedMonth) >= 0

    onRouteIdChanged: gearPage._loadData()

    function _loadData() {
        if (!routeId) return
        entity = routeService.getById(routeId)
    }

    /**
     * 按所选时节生成装备清单, 成功后进入 EquipmentDetailPage (可勾选/强装检查/导出).
     * params 字段与 EquipmentPage.generateList() 保持一致, 只是把"季节"换成
     * 由月份推导的 seasonIndex, 并把路线自带的海拔/天数/难度带进去.
     */
    function generateList() {
        if (!entity || !entity.id) {
            toast.error("路线数据未就绪, 请返回重进")
            return
        }
        if (!equipmentService) {
            toast.error("engine 未就绪, 重启 app 后重试")
            return
        }
        gearPage._generating = true

        var altMax = entity.maxAltitudeM || 0
        if (altMax <= 0) altMax = 500  // 兜底: 缺海拔数据的路线按低海拔处理
        var days = entity.daysNeeded || 1
        var diff = entity.difficulty || 2

        // 沿用 EquipmentPage 默认环境值; 高原标记由 C++ 端按海拔自动推断
        var params = {
            "altitudeMax": altMax,
            "altitudeMin": Math.max(0, altMax - 500),
            "altitudeCamp": Math.max(0, altMax - 200),
            "days": days,
            "people": 1,
            "difficulty": diff,
            "season": gearPage.seasonIndex,
            "tempAvg": 15.0,
            "tempMin": 5.0,
            "windSpeed": 2.0,
            "precipitation": 0,
            "uvIndex": 5.0,
            "diurnalRange": 10,
            "humidity": 1,
            "uvLevel": 2,
            "windLevel": 1,
            "isRainySeason": false,
            "isDesert": false,
            "isCoastal": false
        }

        var listName = (entity.name || "路线") + " · " + gearPage.selectedMonth + "月装备"
        var result = equipmentService.generateList(listName, params)
        gearPage._generating = false

        if (!result || !result.id) {
            toast.error("生成失败, 请检查路线参数")
            return
        }
        ApplicationWindow.window.navBus.navigateTo("EquipmentDetailPage", {listId: result.id})
    }

    // 顶部工具栏 + 返回
    header: ToolBar {
        Material.foreground: "white"
        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8
            ToolButton {
                text: "‹"
                font.pixelSize: 28
                onClicked: gearPage.ApplicationWindow.window.navBus.back()
            }
            Label {
                text: "时节装备推荐"
                color: "white"
                font.pixelSize: 16
                Layout.fillWidth: true
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

            // === 顶部 hero (深青绿, 与装备页统一) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                color: "#00695C"
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00695C" }
                    GradientStop { position: 1.0; color: "#00897B" }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spLg
                    spacing: styles.spMd

                    Text {
                        text: "\ue53f"  // Material Icons: backpack
                        font.family: "Material Icons"
                        font.pixelSize: 32
                        color: "white"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: entity.name || "路线"
                            color: "white"
                            font.pixelSize: styles.fsXl
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: "\ue0c8 " + (entity.province || "") + " · "
                                  + (entity.mountain || "")
                            font.family: "Material Icons"
                            color: "#B2DFDB"
                            font.pixelSize: styles.fsSm
                        }
                        Text {
                            text: "海拔 " + (entity.maxAltitudeM || 0) + "m   ·   "
                                  + (entity.daysNeeded || 1) + " 天   ·   难度 "
                                  + "★".repeat(entity.difficulty || 0)
                            color: "white"
                            font.pixelSize: styles.fsSm
                        }
                    }
                }
            }

            // === 时节选择卡 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: seasonCol.implicitHeight + styles.spLg * 2
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.2)
                border.width: 1

                ColumnLayout {
                    id: seasonCol
                    anchors.fill: parent
                    anchors.margins: styles.spLg
                    spacing: styles.spSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm
                        Text {
                            text: "\ue5d3"  // Material Icons: schedule
                            font.family: "Material Icons"
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsLg
                        }
                        Text {
                            text: "选择出行时节"
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        Text {
                            text: gearPage.seasonNames[gearPage.seasonIndex]
                            color: CommonOptions.colorAccent
                            font.pixelSize: styles.fsSm
                            font.bold: true
                        }
                    }

                    // 12 个月份 chip
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 6
                        rowSpacing: 6
                        columnSpacing: 6

                        Repeater {
                            model: 12
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: styles.rSm

                                readonly property int _m: index + 1
                                readonly property bool _sel: _m === gearPage.selectedMonth
                                readonly property bool _best: gearPage.bestSeasonMonths.indexOf(_m) >= 0

                                // 选中=主题色; 未选中但在适游季=深绿底白字; 其余=卡面
                                // (整页是深色主题, 故用深底+白字, 与 FirstAid/FieldGuide 页一致)
                                color: _sel ? CommonOptions.colorAccent
                                            : (_best ? Qt.darker(CommonOptions.colorSuccess, 1.6)
                                                     : CommonOptions.colorSurface)
                                border.width: 1
                                border.color: _sel ? CommonOptions.colorAccent
                                                   : (_best ? CommonOptions.colorSuccess
                                                            : Qt.darker(CommonOptions.colorSurface, 1.2))

                                Text {
                                    anchors.centerIn: parent
                                    text: parent._m + "月"
                                    color: (parent._sel || parent._best) ? "white"
                                                                         : CommonOptions.colorText
                                    font.pixelSize: styles.fsSm
                                    font.bold: parent._sel || parent._best
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: gearPage.selectedMonth = parent._m
                                }
                            }
                        }
                    }

                    // 适游季匹配提示
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        radius: styles.rSm
                        // 整页深色主题: 用暗色底 + 亮字, 避免浅底浅字看不清
                        color: gearPage.monthInBestSeason ? Qt.darker(CommonOptions.colorSuccess, 2.4)
                                                          : Qt.darker(CommonOptions.colorWarn, 2.4)
                        border.width: 1
                        border.color: gearPage.monthInBestSeason ? CommonOptions.colorSuccess
                                                                 : CommonOptions.colorWarn

                        Text {
                            anchors.fill: parent
                            anchors.margins: 8
                            text: {
                                var s = gearPage.bestSeasonMonths.join("、")
                                if (s.length === 0) return "\ue002 该路线暂无适游季数据"
                                if (gearPage.monthInBestSeason)
                                    return "\ue5ca " + gearPage.selectedMonth + "月属于适游季 (" + s + "月)"
                                return "\ue002 " + gearPage.selectedMonth + "月非适游季, 该路线适游季: " + s + "月"
                            }
                            font.family: "Material Icons"
                            color: gearPage.monthInBestSeason ? CommonOptions.colorSuccess
                                                              : CommonOptions.colorWarn
                            font.pixelSize: styles.fsXs
                            wrapMode: Text.WordWrap
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "提示: 装备按路线海拔/天数/难度 + 所选时节生成, 降水/湿度/风级等按常规值估算。"
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsXs
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // === 生成按钮 ===
            Button {
                Layout.fillWidth: true
                Layout.leftMargin: styles.spLg
                Layout.rightMargin: styles.spLg
                Layout.preferredHeight: 50
                text: gearPage._generating ? "生成中…" : "\ue53f 生成 " + gearPage.selectedMonth + "月装备清单"
                font.family: "Material Icons"
                font.pixelSize: styles.fsMd
                font.bold: true
                Material.background: CommonOptions.colorSuccess
                Material.foreground: "white"
                // 只按"生成中"禁用; 路线数据未就绪时点击给 toast 提示, 不静默置灰
                enabled: !gearPage._generating
                onClicked: gearPage.generateList()
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: styles.spLg
                Layout.rightMargin: styles.spLg
                Layout.topMargin: styles.spSm
                text: "生成后可逐项勾选、查看强装检查结果并导出 PDF。"
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsXs
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 32 }
        }
    }
}
