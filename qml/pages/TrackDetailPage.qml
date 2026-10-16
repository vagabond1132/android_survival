/**
 * @file TrackDetailPage.qml
 * @brief 轨迹分析详情 (2026-09-14 P1)
 *
 * 仿两步路风格:
 *   - 顶部 4 项核心统计 (距离/时长/累计爬升/平均配速)
 *   - 海拔曲线 (QtCharts, LineSeries, 绿色, 渐变填充)
 *   - 速度曲线 (QtCharts, LineSeries, 蓝色, 同步海拔 X 轴)
 *   - 8 项基础指标 (GridLayout, InfoItem)
 *   - 分段配速表 (每 1km)
 *   - 休息点列表
 *   - 卡路里估算
 *
 * 入参: trackId
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtCharts
import OutdoorSurvival 1.0

Page {
    id: detailPage
    property string trackId: ""
    property var track: ({})
    property var stats: ({})
    property var profile: ({})

    title: track.name || "轨迹详情"
    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    // 2026-09-20: 修 Bug 20. 之前 Connections 没 enabled/visible 守卫,
    //   mapService.onDataChanged 是全局信号 (任何 track/photo/GPX 变更都触发),
    //   在 TrackDetailPage 后台 (pop 到其他页) 时仍会刷新, 浪费 + 偶发 stale 数据.
    //   1) onTrackIdChanged 单次加载, Component.onCompleted 删掉
    //   2) Connections.enabled = visible, 离开页面立即停响应
    //   3) 加 ignoreNext 标志, 让 onTrackIdChanged 触发的 refresh 不会因 dataChanged 立即又跑一次
    property bool _ignoreNextDataChanged: false
    onTrackIdChanged: {
        if (trackId) {
            _ignoreNextDataChanged = true
            refresh()
        }
    }
    Connections {
        target: mapService
        // 关键: enabled 跟 visible 绑定, 页面不可见时停止响应 mapService 全局信号
        enabled: detailPage.visible
        function onDataChanged() {
            if (detailPage._ignoreNextDataChanged) {
                detailPage._ignoreNextDataChanged = false
                return
            }
            refresh()
        }
    }

    function refresh() {
        if (!trackId) return
        var r = mapService.getTrackById(trackId)  // 2026-10-09: 契约切 Result, 读 .value
        track = (r && r.ok) ? r.value : {}
        stats = mapService.getTrackStats(trackId, 65.0)
        profile = mapService.getTrackProfile(trackId)
    }

    // 配速格式化 (min/km → "M'S"/km)
    function formatPace(pace) {
        if (!pace || pace <= 0 || pace > 99) return "--"
        var m = Math.floor(pace)
        var s = Math.round((pace - m) * 60)
        if (s === 60) { m++; s = 0 }
        return m + "'" + (s < 10 ? "0" + s : s) + '"/km'
    }
    // 时长格式化 (s → "H:MM" 或 "MM:SS")
    function formatDuration(sec) {
        if (!sec || sec <= 0) return "--"
        var h = Math.floor(sec / 3600)
        var m = Math.floor((sec % 3600) / 60)
        var s = sec % 60
        if (h > 0) return h + ":" + (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s)
        return m + ":" + (s < 10 ? "0" + s : s)
    }
    // 速度 (m/s → km/h)
    function formatSpeed(ms) {
        if (!ms || ms <= 0) return "0.0"
        return (ms * 3.6).toFixed(1)
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

            // === 顶部工具栏 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: CommonOptions.colorSurface
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    ToolButton {
                        text: "← 返回"
                        onClicked: detailPage.ApplicationWindow.window.navBus.back()
                    }
                    Text {
                        Layout.fillWidth: true
                        text: track.name || "(未命名)"
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }
            }

            // === 顶部 4 项核心统计 (大数字) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 100
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: 0

                    Repeater {
                        model: [
                            { label: "距离", value: (stats.distanceM ? (stats.distanceM/1000).toFixed(2) : "0") + " km", color: CommonOptions.colorAccent },
                            { label: "时长", value: formatDuration(stats.durationS), color: CommonOptions.colorWarn },
                            { label: "累计↑", value: (stats.elevationGainM || 0).toFixed(0) + " m", color: CommonOptions.colorSuccess },
                            { label: "配速", value: formatPace(stats.avgPace), color: CommonOptions.colorDanger }
                        ]
                        delegate: ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.value
                                color: modelData.color
                                font.pixelSize: styles.fsXl
                                font.bold: true
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.label
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: styles.fsSm
                            }
                        }
                    }
                }
            }

            // === 海拔曲线 ===
            Section {
                titleIcon: "\ue1b1"  // report_problem (海拔警示)
                title: "海拔曲线"
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 200
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                ChartView {
                    id: altChart
                    anchors.fill: parent
                    anchors.margins: 4
                    antialiasing: true
                    legend.visible: false
                    backgroundColor: CommonOptions.colorSurface
                    plotAreaColor: CommonOptions.colorSurface
                    title: ""

                    ValueAxis {
                        id: altXAxis
                        titleText: "距离 (km)"
                        labelFormat: "%.1f"
                        min: 0
                        max: stats.distanceM ? stats.distanceM / 1000 : 1
                    }
                    ValueAxis {
                        id: altYAxis
                        titleText: "海拔 (m)"
                        labelFormat: "%.0f"
                        min: 0
                        max: 1
                    }

                    LineSeries {
                        id: altLine
                        name: "海拔"
                        axisX: altXAxis
                        axisY: altYAxis
                        color: CommonOptions.colorSuccess
                        width: 2
                    }

                    Component.onCompleted: refreshAltChart()
                    function refreshAltChart() {
                        altLine.clear()
                        if (!profile.ok || !profile.distances) return
                        var dists = profile.distances
                        var eles = profile.elevations
                        var maxE = -1e9, minE = 1e9
                        for (var i = 0; i < eles.length; ++i) {
                            if (eles[i] > maxE) maxE = eles[i]
                            if (eles[i] < minE) minE = eles[i]
                        }
                        if (maxE === minE) { maxE += 100; minE = Math.max(0, minE - 100) }
                        altYAxis.max = Math.ceil(maxE / 100) * 100
                        altYAxis.min = Math.floor(minE / 100) * 100
                        for (var j = 0; j < dists.length; ++j) {
                            altLine.append(dists[j] / 1000.0, eles[j])
                        }
                    }
                }
            }

            // === 速度曲线 ===
            Section {
                titleIcon: "\ue566"  // directions_run
                title: "速度曲线"
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 200
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                ChartView {
                    id: speedChart
                    anchors.fill: parent
                    anchors.margins: 4
                    antialiasing: true
                    legend.visible: false
                    backgroundColor: CommonOptions.colorSurface
                    plotAreaColor: CommonOptions.colorSurface

                    ValueAxis {
                        id: spdXAxis
                        titleText: "距离 (km)"
                        labelFormat: "%.1f"
                        min: 0
                        max: stats.distanceM ? stats.distanceM / 1000 : 1
                    }
                    ValueAxis {
                        id: spdYAxis
                        titleText: "速度 (km/h)"
                        labelFormat: "%.1f"
                        min: 0
                        max: 1
                    }

                    LineSeries {
                        id: spdLine
                        name: "速度"
                        axisX: spdXAxis
                        axisY: spdYAxis
                        color: CommonOptions.colorAccent
                        width: 2
                    }

                    Component.onCompleted: refreshSpdChart()
                    function refreshSpdChart() {
                        spdLine.clear()
                        if (!profile.ok || !profile.distances) return
                        var dists = profile.distances
                        var speeds = profile.speeds
                        var maxS = 0
                        for (var i = 0; i < speeds.length; ++i) {
                            if (speeds[i] > maxS) maxS = speeds[i]
                        }
                        if (maxS < 0.1) maxS = 1
                        spdYAxis.max = Math.ceil((maxS * 3.6) / 2) * 2
                        for (var j = 0; j < dists.length; ++j) {
                            spdLine.append(dists[j] / 1000.0, speeds[j] * 3.6)
                        }
                    }
                }
            }

            // === 8 项基础指标 ===
            Section {
                titleIcon: "\ue01d"  // equalizer
                title: "详细统计"
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 240
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

                    InfoItem { label: "总距离"; value: ((stats.distanceM || 0) / 1000).toFixed(2) + " km" }
                    InfoItem { label: "总时长"; value: formatDuration(stats.durationS) }
                    InfoItem { label: "平均配速"; value: formatPace(stats.avgPace) }
                    InfoItem { label: "平均速度"; value: formatSpeed(stats.avgSpeed) + " km/h" }
                    InfoItem { label: "最大速度"; value: formatSpeed(stats.maxSpeed) + " km/h" }
                    InfoItem { label: "累计爬升"; value: (stats.elevationGainM || 0).toFixed(0) + " m" }
                    InfoItem { label: "累计下降"; value: (stats.elevationLossM || 0).toFixed(0) + " m" }
                    InfoItem { label: "最高海拔"; value: (stats.maxAlt || 0).toFixed(0) + " m" }
                    InfoItem { label: "最低海拔"; value: (stats.minAlt || 0).toFixed(0) + " m" }
                    InfoItem { label: "采样点"; value: (stats.pointCount || 0) + " 个" }
                }
            }

            // === 卡路里 ===
            Section {
                titleIcon: "\ue25e"  // whatshot (卡路里)
                title: "卡路里"
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 60
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: CommonOptions.colorWarn
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    Text {
                        text: "约消耗"
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsMd
                    }
                    Text {
                        Layout.fillWidth: true
                        text: (stats.calorieKcal || 0).toFixed(0) + " kcal"
                        color: CommonOptions.colorWarn
                        font.pixelSize: styles.fsXl
                        font.bold: true
                    }
                    Text {
                        text: "(按 " + (stats.weightKg || 65) + " kg)"
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                    }
                }
            }

            // === 分段配速 ===
            Section {
                titleIcon: "\ue3b8"  // straighten
                title: "分段配速 (每公里)"
                visible: stats.splits && stats.splits.length > 0
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: splitsCol.implicitHeight + 24
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1
                visible: stats.splits && stats.splits.length > 0

                ColumnLayout {
                    id: splitsCol
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: 4

                    Repeater {
                        model: stats.splits || []
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: modelData.km + " km"
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsMd
                                Layout.preferredWidth: 60
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "距离 " + (modelData.distanceKm || 0).toFixed(2) + " km"
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: styles.fsSm
                            }
                            Text {
                                text: formatDuration(modelData.durationS)
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsSm
                                Layout.preferredWidth: 70
                            }
                            Text {
                                text: detailPage.formatPace(modelData.avgPace)
                                color: CommonOptions.colorAccent
                                font.pixelSize: styles.fsSm
                                font.bold: true
                                Layout.preferredWidth: 90
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }

            // === 休息点 ===
            Section {
                titleIcon: "\ue1bd"  // hotel
                title: "休息点 (≥ 3 分钟)"
                visible: stats.restPoints && stats.restPoints.length > 0
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: restsCol.implicitHeight + 24
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1
                visible: stats.restPoints && stats.restPoints.length > 0

                ColumnLayout {
                    id: restsCol
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: 4

                    Repeater {
                        model: stats.restPoints || []
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                width: 6; Layout.fillHeight: true
                                color: CommonOptions.colorWarn
                                radius: 3
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "\ue0c8 " + (modelData.lat || 0).toFixed(5) + ", " +
                                      (modelData.lon || 0).toFixed(5)
                                font.family: "Material Icons"
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsSm
                            }
                            Text {
                                text: formatDuration(modelData.durationS)
                                color: CommonOptions.colorWarn
                                font.pixelSize: styles.fsSm
                                font.bold: true
                            }
                        }
                    }
                }
            }

            // 错误提示
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 48
                color: CommonOptions.colorDanger
                radius: styles.rMd
                visible: stats.ok === false
                Text {
                    anchors.centerIn: parent
                    text: "\ue002 " + (stats.error || "加载失败")  // Material Icons: warning
                    font.family: "Material Icons"
                    color: "white"
                    font.pixelSize: styles.fsSm
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spLg }
        }
    }
}
