/**
 * @file RouteListPage.qml
 * @brief 路线列表 (2026-09-14 UI 改版)
 *
 * 改进:
 *   - 顶部 hero 渐变 (深绿山主题) + 标题 + 副标题
 *   - 筛选区: 卡片化, 圆角 12, padding 12
 *   - 列表项: 难度色条 + 卡片 + 元信息
 *   - 全部用 CommonOptions + Styles 设计 token
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: routeListPage
    title: "路线"

    property int filterDifficulty: 0
    property string filterProvince: "全部"
    property int filterMonth: 0

    property var provinces: ["全部"]
    property var months: ["全部"]

    // 2026-09-21: 同 TravelListPage — FilterRow 暴露的 ComboBox 替代之前不存在的
    //   provinceCombo / monthCombo id.
    property int _provIndex: 0
    property int _monthIndex: 0

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    function rebuildList() {
        var provinceKey = filterProvince === "全部" ? "" : filterProvince
        // 2026-09-14 修: 难度 chip 选 N 星 = 显示 1-N 星 (难度上限语义)
        var minDiff = 1
        var maxDiff = filterDifficulty === 0 ? 5 : filterDifficulty
        // 2026-09-20: 用 ServiceListModel 替代 clear+for+append 模板 (Phase 3)
        routeModel.args = [provinceKey, minDiff, maxDiff, filterMonth]
        // 2026-09-20: Qt.callLater 让 ServiceListModel.Component.onCompleted 的
        //   auto-refresh 先跑 (此时 args 已是当前值), 避免 race 导致首次结果为空.
        Qt.callLater(function() { routeModel.refresh() })
        // 2026-09-28: 删掉结果计数的手写赋值. 之前在这同步读 routeModel.count,
        //   但 refresh() 被 Qt.callLater 延后 → 首次必显示"共 0 条路线", 之后每次
        //   筛选显示的都是上一次的旧值. 改为 resultLabel 声明式绑定 routeModel.count
        //   (ListModel.count 是 NOTIFYable), refresh 完成后自动刷新.
    }

    Component.onCompleted: {
        provinces = routeService.getAvailableProvinces()
        months = routeService.getAvailableMonths()
        rebuildList()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // === 顶部 hero (统一深青绿) ===
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            color: "#00695C"  // 深青绿
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00695C" }
                GradientStop { position: 1.0; color: "#00897B" }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: styles.spLg
                spacing: styles.spMd

                Text {
                    text: "\ue536"  // Material Icons: hiking (2026-09-19: 之前 \ue52f 是 bicycle, 改 hiking)
                    font.family: "Material Icons"
                    font.pixelSize: 32
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "徒步路线"
                        color: "white"
                        font.pixelSize: styles.fs2xl
                        font.bold: true
                    }
                    Text {
                        text: "国内经典徒步路线合集"
                        color: "#B0BEC5"
                        font.pixelSize: styles.fsSm
                    }
                }
            }
        }

        // === 筛选区 (卡片) ===
        Rectangle {
            Layout.fillWidth: true
            Layout.margins: styles.spLg
            Layout.topMargin: styles.spLg
            Layout.preferredHeight: filterCol.implicitHeight + 24
            color: CommonOptions.colorSurface
            radius: styles.rLg
            border.color: Qt.darker(CommonOptions.colorSurface, 1.2)
            border.width: 1

            ColumnLayout {
                id: filterCol
                anchors.fill: parent
                anchors.margins: styles.spMd
                spacing: styles.spSm

                // 2026-09-20: 改用 FilterRow 组件 (chip + combo), 跟 TravelListPage /
                //   NearbyTab 风格统一. chipCount=5 表示 1-5 星, chipSelected=0 表示"全部".
                FilterRow {
                    Layout.fillWidth: true
                    label: "难度"
                    chipCount: 5
                    chipSelected: routeListPage.filterDifficulty
                    onChipClicked: (n) => routeListPage.filterDifficulty = n
                }
                FilterRow {
                    id: filterRowProv
                    Layout.fillWidth: true
                    label: "省份"
                    comboModel: routeListPage.provinces
                    comboCurrentIndex: routeListPage._provIndex
                    onComboActivated: (i, v) => {
                        routeListPage._provIndex = i
                        routeListPage.filterProvince = v
                    }
                }
                FilterRow {
                    id: filterRowMonth
                    Layout.fillWidth: true
                    label: "月份"
                    comboModel: routeListPage.months
                    comboCurrentIndex: routeListPage._monthIndex
                    onComboActivated: (i, v) => {
                        routeListPage._monthIndex = i
                        if (v === "全部") routeListPage.filterMonth = 0
                        else {
                            var digits = String(v).replace(/[^0-9]/g, "")
                            routeListPage.filterMonth = parseInt(digits) || 0
                        }
                    }
                }

                // 计数 + 重置
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: styles.spXs
                    spacing: 4
                    // 2026-09-29: 同 TravelListPage — 图标字形拆到 IconLabel, 中文/
                    //   数字用默认字体, 避免 PUA 码位 (\ue01d 等) 与中文混排.
                    IconLabel {
                        name: "hiking"
                        size: 13
                        tintColor: CommonOptions.colorTextMuted
                    }
                    Text {
                        id: resultLabel
                        // 2026-09-28: 声明式绑定 routeModel.count (NOTIFYable),
                        //   refresh() 完成后自动更新, 修复"共 0 条路线"恒定 bug.
                        text: "共 " + (routeModel.count || 0) + " 条路线"
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: 4
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                routeListPage.filterDifficulty = 0
                                routeListPage.filterProvince = "全部"
                                routeListPage.filterMonth = 0
                                // 2026-09-21: 同 TravelListPage — 用 page 自身 _xxIndex
                                //   + filterRow.comboBoxInstance.
                                routeListPage._provIndex = 0
                                routeListPage._monthIndex = 0
                                if (filterRowProv.comboBoxInstance) filterRowProv.comboBoxInstance.currentIndex = 0
                                if (filterRowMonth.comboBoxInstance) filterRowMonth.comboBoxInstance.currentIndex = 0
                            }
                        }
                        IconLabel {
                            name: "refresh"
                            size: 13
                            tintColor: CommonOptions.colorAccent
                        }
                        Text {
                            text: "重置"
                            color: CommonOptions.colorAccent
                            font.pixelSize: styles.fsSm
                        }
                    }
                }
            }
        }

        // === 列表 ===
        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: styles.spLg
            Layout.topMargin: 0
            spacing: styles.spSm
            clip: true

            model: ServiceListModel {
                id: routeModel
                service: routeService
                method: "getFiltered"
            }

            delegate: Rectangle {
                width: ListView.view.width
                height: 90
                radius: styles.rMd
                color: CommonOptions.colorSurface
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                // 2026-09-29: bestSeason 安全格式化 (同 TravelListPage) — 防
                //   非数组容器被字符串化成 "QQmlListModel(...)" 之类脏数据.
                readonly property string _seasonText: {
                    var s = model.bestSeason
                    if (s === undefined || s === null || s === "") return ""
                    if (Array.isArray(s)) return s.join("、")
                    if (typeof s === "object") {
                        var out = []
                        var n = (s.length !== undefined) ? s.length : 0
                        for (var i = 0; i < n; i++) out.push(s[i])
                        return out.join("、")
                    }
                    return String(s)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        ApplicationWindow.window.navBus.navigateTo("RouteDetailPage", {routeId: model.id})
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spSm
                    spacing: styles.spSm

                    // 左侧难度色条
                    Rectangle {
                        width: 6
                        Layout.fillHeight: true
                        radius: 3
                        color: {
                            if (model.difficulty >= 5) return "#B71C1C"
                            if (model.difficulty >= 4) return CommonOptions.colorDanger
                            if (model.difficulty >= 3) return CommonOptions.colorWarn
                            if (model.difficulty >= 2) return "#FBC02D"
                            return CommonOptions.colorSuccess
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: model.name
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: "★".repeat(model.difficulty) + " · " +
                                  model.distanceKm + " km"
                            color: CommonOptions.colorWarn
                            font.pixelSize: styles.fsSm
                        }
                        // 2026-09-29: 图标字形 (\ue0c8) 从混排 Text 中拆出, 中文/
                        //   数字用默认字体; 分隔符由 "  ·  " 收敛为 " · ".
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            IconLabel {
                                name: "place"
                                size: 12
                                tintColor: CommonOptions.colorTextMuted
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (model.province || "") +
                                      (_seasonText ? " · " + _seasonText : "")
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: styles.fsXs
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Text {
                        text: "›"
                        color: "#607D8B"
                        font.pixelSize: 22
                    }
                }
            }
        }
    }

    onFilterDifficultyChanged: rebuildList()
    onFilterProvinceChanged: rebuildList()
    onFilterMonthChanged: rebuildList()
}
