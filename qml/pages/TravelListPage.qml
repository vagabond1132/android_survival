/**
 * @file TravelListPage.qml
 * @brief 自驾游路线列表 (2026-09-14 UI 改版)
 *
 * 改进:
 *   - 顶部 hero 渐变 (深海蓝主题) + 标题 + 副标题
 *   - 筛选区: 卡片化, 圆角 12, padding 12
 *   - 列表项: 卡片 + 元信息 + 右箭头
 *   - 全部用 CommonOptions + Styles 设计 token
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: travelListPage
    title: "自驾游"

    property string filterProvince: "全部"
    property int filterMinDays: 0
    property int filterMaxDays: 0
    property int filterMonth: 0
    property real filterMinKm: 0
    property real filterMaxKm: 0

    property var provinces: ["全部"]
    property var months: ["全部"]

    // 2026-09-21: FilterRow 内部 ComboBox 暴露为 comboBoxInstance, 改用 page 自身
    //   的 _xxIndex 字段保存当前 index, 让 onComboActivated 更新自身状态而非依赖
    //   不存在的 provCombo 等 id. 重置时直接对这些字段写 0.
    property int _provIndex: 0
    property int _daysIndex: 0
    property int _distIndex: 0
    property int _monthIndex: 0

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    function refresh() {
        var provKey = filterProvince === "全部" ? "" : filterProvince
        // 2026-09-20: 用 ServiceListModel 替代 clear+for+append 模板 (Phase 3)
        routeModel.args = [provKey, filterMinDays, filterMaxDays,
                           filterMinKm, filterMaxKm, filterMonth]
        // 2026-09-20: Qt.callLater 让 ServiceListModel.Component.onCompleted 的
        //   auto-refresh 先跑, 避免 race.
        Qt.callLater(function() { routeModel.refresh() })
        // 2026-09-28: 删掉结果计数的手写赋值 (与 RouteListPage 同构). 之前在这
        //   同步读 routeModel.count, 但 refresh() 被 Qt.callLater 延后 → 首次必
        //   显示"共 0 条路线", 之后每次筛选显示的都是上一次的旧值. 改为
        //   resultLabel 声明式绑定 routeModel.count (ListModel.count 是
        //   NOTIFYable), refresh 完成后自动刷新.
    }

    Component.onCompleted: {
        // 2026-09-14: travelService.getAvailableProvinces() 已返回中文全称
        // 不再手动加 "全部" 前缀, 避免重复
        provinces = travelService.getAvailableProvinces()
        months = travelService.getAvailableMonths()
        refresh()
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
                    text: "\ue531"  // Material Icons: directions_car
                    font.family: "Material Icons"
                    font.pixelSize: 32
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "自驾游"
                        color: "white"
                        font.pixelSize: styles.fs2xl
                        font.bold: true
                    }
                    Text {
                        text: "国内经典自驾路线合集"
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
            clip: false   // 允许 ComboBox popup 溢出

            ColumnLayout {
                id: filterCol
                anchors.fill: parent
                anchors.margins: styles.spMd
                spacing: styles.spSm

                // 2026-09-20: 全部改用 FilterRow 组件, 视觉风格与 RouteListPage /
                //   NearbyTab 完全一致
                // 2026-09-21: FilterRow 把内部 ComboBox 暴露为 comboBoxInstance,
                //   之前直接用 provCombo 等 id 报 "is not defined" 因为 ComboBox
                //   藏在 Loader 里. 现在改成有 id 的 FilterRow, 通过
                //   filterRowProv.comboBoxInstance.currentIndex 操作.
                FilterRow {
                    id: filterRowProv
                    Layout.fillWidth: true
                    label: "省份"
                    comboModel: travelListPage.provinces
                    comboCurrentIndex: travelListPage._provIndex
                    onComboActivated: (i, v) => {
                        travelListPage._provIndex = i
                        travelListPage.filterProvince = v
                    }
                }
                FilterRow {
                    id: filterRowDays
                    Layout.fillWidth: true
                    label: "天数"
                    comboModel: ["全部", "1-2 天", "3-5 天", "6-10 天", "10+ 天"]
                    comboCurrentIndex: travelListPage._daysIndex
                    onComboActivated: (i, v) => {
                        travelListPage._daysIndex = i
                        if (v === "1-2 天") { travelListPage.filterMinDays = 1; travelListPage.filterMaxDays = 2 }
                        else if (v === "3-5 天") { travelListPage.filterMinDays = 3; travelListPage.filterMaxDays = 5 }
                        else if (v === "6-10 天") { travelListPage.filterMinDays = 6; travelListPage.filterMaxDays = 10 }
                        else if (v === "10+ 天") { travelListPage.filterMinDays = 11; travelListPage.filterMaxDays = 99 }
                        else { travelListPage.filterMinDays = 0; travelListPage.filterMaxDays = 0 }
                    }
                }
                FilterRow {
                    id: filterRowDist
                    Layout.fillWidth: true
                    label: "距离"
                    comboModel: ["全部", "<500km", "500-1000km", "1000-2000km", "2000km+"]
                    comboCurrentIndex: travelListPage._distIndex
                    onComboActivated: (i, v) => {
                        travelListPage._distIndex = i
                        if (v === "<500km") { travelListPage.filterMinKm = 0; travelListPage.filterMaxKm = 500 }
                        else if (v === "500-1000km") { travelListPage.filterMinKm = 500; travelListPage.filterMaxKm = 1000 }
                        else if (v === "1000-2000km") { travelListPage.filterMinKm = 1000; travelListPage.filterMaxKm = 2000 }
                        else if (v === "2000km+") { travelListPage.filterMinKm = 2000; travelListPage.filterMaxKm = 99999 }
                        else { travelListPage.filterMinKm = 0; travelListPage.filterMaxKm = 0 }
                    }
                }
                FilterRow {
                    id: filterRowMonth
                    Layout.fillWidth: true
                    label: "月份"
                    comboModel: travelListPage.months
                    comboCurrentIndex: travelListPage._monthIndex
                    onComboActivated: (i, v) => {
                        travelListPage._monthIndex = i
                        if (v === "全部") travelListPage.filterMonth = 0
                        else travelListPage.filterMonth = parseInt(String(v).replace(/[^0-9]/g, "")) || 0
                    }
                }

                // 计数 + 重置
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: styles.spXs
                    spacing: 4
                    IconLabel {
                        name: "car"
                        size: 13
                        tintColor: CommonOptions.colorTextMuted
                    }
                    Text {
                        id: resultLabel
                        // 2026-09-28: 声明式绑定 routeModel.count (NOTIFYable),
                        //   refresh() 完成后自动更新, 修复"共 0 条路线"恒定 bug.
                        // 2026-09-29: 图标已拆到左侧 IconLabel, 此处只放中文/数字,
                        //   去掉硬编码 font.family "Material Icons" (中文会落回系统
                        //   字体导致混排).
                        text: "共 " + (routeModel.count || 0) + " 条路线"
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                        Layout.fillWidth: true
                    }
                    // 2026-09-29: 重置按钮拆成 [图标][文字] 两个元素, 文字独立
                    //   用默认字体; MouseArea 铺在整行上, 点击区域不变.
                    RowLayout {
                        spacing: 4
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                travelListPage.filterProvince = "全部"
                                travelListPage.filterMinDays = 0
                                travelListPage.filterMaxDays = 0
                                travelListPage.filterMinKm = 0
                                travelListPage.filterMaxKm = 0
                                travelListPage.filterMonth = 0
                                // 2026-09-21: 之前用 provCombo.currentIndex = 0 等,
                                //   导致 "provCombo is not defined" 因为 ComboBox 藏在
                                //   FilterRow 的 Loader 里. 改操作 page 自身的 _xxIndex
                                //   + 内部 ComboBox 实例.
                                travelListPage._provIndex = 0
                                travelListPage._daysIndex = 0
                                travelListPage._distIndex = 0
                                travelListPage._monthIndex = 0
                                if (filterRowProv.comboBoxInstance) filterRowProv.comboBoxInstance.currentIndex = 0
                                if (filterRowDays.comboBoxInstance) filterRowDays.comboBoxInstance.currentIndex = 0
                                if (filterRowDist.comboBoxInstance) filterRowDist.comboBoxInstance.currentIndex = 0
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
                service: travelService
                method: "getFiltered"
            }

            delegate: Rectangle {
                width: ListView.view.width
                height: 132
                radius: styles.rMd
                color: CommonOptions.colorSurface
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                // 2026-09-29: bestSeason 经 ListModel 存储后可能是 JS 数组 /
                //   QStringList 包装对象 / 纯字符串; 统一安全格式化成 "5月、6月".
                //   不做防护时, 非数组对象会被字符串化成 "QQmlListModel(...)"
                //   之类脏数据直接渲染到界面 (用户报"下方QQ 什么的信息").
                readonly property string _seasonText: {
                    var s = model.bestSeason
                    if (s === undefined || s === null || s === "") return "全年"
                    if (Array.isArray(s)) return s.length ? s.join("、") : "全年"
                    if (typeof s === "object") {
                        var out = []
                        var n = (s.length !== undefined) ? s.length : 0
                        for (var i = 0; i < n; i++) out.push(s[i])
                        return out.length ? out.join("、") : "全年"
                    }
                    return String(s)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        ApplicationWindow.window.navBus.navigateTo("TravelDetailPage", { travelId: model.id })
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spSm
                    spacing: styles.spSm

                    // 左侧色条 (蓝色主题)
                    Rectangle {
                        width: 6
                        Layout.fillHeight: true
                        radius: 3
                        color: CommonOptions.colorAccent
                    }

                    // 2026-09-29: 之前 4 行信息全塞进单个 Text 且硬编码
                    //   font.family "Material Icons", 但内容里 PUA 图标码位
                    //   (\ue531 等) 与中文/拉丁混排 → 因该 TTF 只含图标字形,
                    //   中文回退系统字体 → 排版散乱; "   ·   " 三连空格又制造
                    //   "大量空格". 现改为: 每行 = IconLabel(纯图标字形) +
                    //   Text(默认字体, 中文/数字), 分隔符统一 " · "(单空格).
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
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            IconLabel {
                                name: "car"
                                size: 14
                                tintColor: CommonOptions.colorAccent
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (model.startName || model.startCity || "起点") +
                                      " → " + (model.endName || model.endCity || "终点") +
                                      " · " + model.distanceKm + " km" +
                                      " · " + model.days + " 天"
                                color: CommonOptions.colorAccent
                                font.pixelSize: styles.fsSm
                                elide: Text.ElideRight
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            IconLabel {
                                name: "calendar"
                                size: 13
                                tintColor: CommonOptions.colorTextMuted
                            }
                            Text {
                                Layout.fillWidth: true
                                text: _seasonText + " · " + (model.province || "")
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: styles.fsXs
                                elide: Text.ElideRight
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            IconLabel {
                                name: "terrain"
                                size: 13
                                tintColor: CommonOptions.colorTextMuted
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "最高 " + (model.maxAltitude || 0) + " m · " +
                                      (model.roadType || "—")
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

    onFilterProvinceChanged: refresh()
    onFilterMinDaysChanged: refresh()
    onFilterMaxDaysChanged: refresh()
    onFilterMonthChanged: refresh()
    onFilterMinKmChanged: refresh()
    onFilterMaxKmChanged: refresh()
}
