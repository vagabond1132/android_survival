/**
 * @file RouteSummaryPanel.qml
 * @brief 路线/轨迹 概览面板 (海拔/速度/距离分析) 2026-09-15
 *
 * 数据源:
 *   - 路线: routeService.getById(id) + getWaypoints(id) (海拔)
 *   - 轨迹: mapService.getTrackStats(id) + getTrackProfile(id)
 *
 * 内容:
 *   - 基础统计: 距离/爬升/下降/最高最低海拔/估算时长
 *   - 海拔剖面图 (Canvas 自绘)
 *   - 速度分析: 平均速度/最大速度 (轨迹模式)
 *   - 分段配速表 (轨迹模式, 每 1 km)
 *   - 难度评分 (基于爬升/距离/海拔, 仅路线)
 *
 * 入口:
 *   - kind: "route" | "travel" | "track"
 *   - id:   routeId / travelId / trackId
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: root

    // 入口参数
    property string kind: "route"     // route | travel | track
    // 2026-09-15: 改名为 itemId - QML 'id' 是关键字, 避免冲突
    property string itemId: ""
    property string name: ""

    // === 公共数据 (由 load() 填充) ===
    // 2026-09-15: 用 property var + Behavior onChanged emit signal
    // qmlcachegen 静态分析需要显式 signal 才能在 Connections 里挂 onProfileChanged
    property var stats: ({})
    property var profile: ({})
    property string loadError: ""

    // 显式 signal - 通知 Canvas 重绘
    // 2026-09-16: 不能用 profileChanged - QML 自动给 property var profile 生成同名 change signal
    signal profileReloaded()

    // 路线: 距离/海拔
    property real distM: 0
    property real gainM: 0
    property real lossM: 0
    property real maxAlt: 0
    property real minAlt: 0
    property real avgSpeed: 0         // m/s (轨迹)
    property real maxSpeed: 0         // m/s (轨迹)
    property real avgPace: 0          // min/km (轨迹)
    property int durationS: 0         // s (轨迹)
    property int pointCount: 0

    // 估算时长 (路线用) - 5 km/h 平地 + 爬升 0.5 km/h
    function _estimateDurationFromRoute(distKm, gain) {
        if (distKm <= 0) return 0
        var flatHours = distKm / 5.0
        var climbHours = gain / 500.0  // 每 500m 爬升 1h
        return (flatHours + climbHours) * 3600
    }

    // 难度评估
    function _difficultyLabel() {
        if (kind === "route") {
            // 用路线综合评分 (data.score) 优先
            var s = stats.score
            if (!s && s !== 0) return ""
            if (s >= 90) return "高度推荐"
            if (s >= 80) return "推荐"
            if (s >= 70) return "良好"
            if (s >= 60) return "较难"
            return "高难"
        } else if (kind === "travel") {
            return "自驾"
        } else {
            return "轨迹"
        }
    }

    Component.onCompleted: load()

    function load() {
        loadError = ""
        if (!itemId) {
            loadError = "缺少 ID"
            return
        }
        if (kind === "route") {
            try {
                var r = routeService.getById(itemId)
                if (!r || !r.id) {
                    loadError = "未找到路线"
                    return
                }
                name = r.name || ""
                distM = (r.distanceKm || 0) * 1000
                gainM = r.elevationGainM || 0
                lossM = r.elevationLossM || 0
                maxAlt = r.maxAltitudeM || 0
                minAlt = r.minAltitudeM || 0
                durationS = _estimateDurationFromRoute(r.distanceKm || 0, gainM)
                // 海拔剖面用 waypoints
                var wps = routeService.getWaypoints(itemId)
                pointCount = wps.length
                var dists = [], elevs = []
                if (wps && wps.length > 0) {
                    var cumDist = 0
                    var prevLat = null, prevLon = null
                    for (var i = 0; i < wps.length; i++) {
                        var w = wps[i]
                        var lat = (w.lat !== undefined) ? w.lat : w.latitude
                        var lon = (w.lon !== undefined) ? w.lon : w.longitude
                        var alt = w.elevation || 0
                        if (i > 0) {
                            cumDist += haversineM(prevLat, prevLon, lat, lon)
                        }
                        dists.push(cumDist)
                        elevs.push(alt)
                        prevLat = lat
                        prevLon = lon
                    }
                }
                profile = { distances: dists, elevations: elevs, speeds: [], timestamps: [] }
                profileReloaded()
                stats = {
                    score: r.score, distanceKm: r.distanceKm, daysNeeded: r.daysNeeded,
                    routeNature: r.routeNature, isWild: r.isWild,
                    difficulty: r.difficulty, notRecommended: r.notRecommended,
                    notRecommendedReason: r.notRecommendedReason,
                    trailheadName: r.trailheadName, trailendName: r.trailendName
                }
            } catch (e) { loadError = "路线加载失败: " + e }
        } else if (kind === "travel") {
            try {
                var t = travelService.getById(itemId)
                if (!t || !t.id) {
                    loadError = "未找到自驾游"
                    return
                }
                name = t.name || ""
                distM = (t.distanceKm || 0) * 1000
                gainM = t.maxAltitude || 0  // 自驾无 gain, 用 maxAlt
                lossM = 0
                maxAlt = t.maxAltitude || 0
                minAlt = 0
                durationS = (t.driveHours || 0) * 3600
                pointCount = 2
                // 自驾只有起终点, 画不出剖面
                var dists2 = [0, distM]
                var elevs2 = [0, gainM]
                profile = { distances: dists2, elevations: elevs2, speeds: [], timestamps: [] }
                profileReloaded()
                stats = {
                    startName: t.startName, endName: t.endName,
                    startCity: t.startCity, endCity: t.endCity,
                    roadType: t.roadType, days: t.days, fuelCostCNY: t.fuelCostCNY,
                    supply: t.supply
                }
            } catch (e) { loadError = "自驾加载失败: " + e }
        } else if (kind === "track") {
            try {
                var s = mapService.getTrackStats(itemId)
                if (!s.ok) {
                    loadError = "轨迹统计失败: " + (s.error || "未知")
                    return
                }
                var r = mapService.getTrackById(itemId)  // 2026-10-09: 契约切 Result, 读 .value
                var trackInfo = (r && r.ok) ? r.value : ({})
                name = (trackInfo && trackInfo.name) || "(轨迹)"
                distM = s.distanceM || 0
                gainM = s.elevationGainM || 0
                lossM = s.elevationLossM || 0
                maxAlt = s.maxAlt || 0
                minAlt = s.minAlt || 0
                avgSpeed = s.avgSpeed || 0
                maxSpeed = s.maxSpeed || 0
                avgPace = s.avgPace || 0
                durationS = s.durationS || 0
                pointCount = s.pointCount || 0
                stats = {
                    calorieKcal: s.calorieKcal || 0,
                    weightKg: s.weightKg || 65,
                    splits: s.splits || [],
                    restPoints: s.restPoints || []
                }
                // 加载剖面
                var prof = mapService.getTrackProfile(itemId)
                if (prof.ok) {
                    profile = {
                        distances: prof.distances,
                        elevations: prof.elevations,
                        speeds: prof.speeds,
                        timestamps: prof.timestamps
                    }
                    profileReloaded()
                }
            } catch (e) { loadError = "轨迹加载失败: " + e }
        }
    }

    // === 辅助 ===
    function formatPace(minPerKm) {
        if (!minPerKm || minPerKm <= 0) return "-"
        var m = Math.floor(minPerKm)
        var s = Math.round((minPerKm - m) * 60)
        return m + "'" + (s < 10 ? "0" : "") + s + '"'
    }
    function formatSpeed(ms) {
        if (!ms) return "-"
        return (ms * 3.6).toFixed(1) + " km/h"
    }

    // === 布局 ===
    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 12

            // 加载错误
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 12
                visible: loadError.length > 0
                Layout.preferredHeight: 60
                color: "#D32F2F"
                radius: 4
                Text {
                    anchors.centerIn: parent
                    text: loadError
                    color: "white"
                    font.pixelSize: 13
                }
            }

            // === 头部 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 12
                Layout.preferredHeight: 80
                radius: 8
                color: kind === "route" ? "#1A237E" : kind === "travel" ? "#00695C" : "#37474F"
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: name || "(未命名)"
                            color: "white"
                            font.pixelSize: 18
                            font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: _difficultyLabel()
                            color: "white"
                            font.pixelSize: 12
                        }
                    }
                    Text {
                        text: kind === "route" ? "\ue536 徒步路线" :
                              kind === "travel" ? "\ue531 自驾游" : "\ue1db 轨迹记录"
                        font.family: "Material Icons"
                        color: "#B0BEC5"
                        font.pixelSize: 12
                    }
                }
            }

            // === 基础统计卡 ===
            GridLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                columns: 3
                rowSpacing: 8
                columnSpacing: 8

                // 距离
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    radius: 6
                    color: "#263238"
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        Text { text: "距离"; color: "#90A4AE"; font.pixelSize: 10 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: (distM / 1000).toFixed(2)
                                color: "#1976D2"
                                font.pixelSize: 20
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Text { text: "km"; color: "#78909C"; font.pixelSize: 11 }
                        }
                    }
                }
                // 爬升
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    radius: 6
                    color: "#263238"
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        Text { text: "累计爬升"; color: "#90A4AE"; font.pixelSize: 10 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: Math.round(gainM).toString()
                                color: "#388E3C"
                                font.pixelSize: 20
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Text { text: "m"; color: "#78909C"; font.pixelSize: 11 }
                        }
                    }
                }
                // 下降
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    radius: 6
                    color: "#263238"
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        Text { text: "累计下降"; color: "#90A4AE"; font.pixelSize: 10 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: Math.round(lossM).toString()
                                color: "#F57C00"
                                font.pixelSize: 20
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Text { text: "m"; color: "#78909C"; font.pixelSize: 11 }
                        }
                    }
                }
                // 最高
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    radius: 6
                    color: "#263238"
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        Text { text: "最高海拔"; color: "#90A4AE"; font.pixelSize: 10 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: Math.round(maxAlt).toString()
                                color: "#7B1FA2"
                                font.pixelSize: 20
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Text { text: "m"; color: "#78909C"; font.pixelSize: 11 }
                        }
                    }
                }
                // 最低
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    radius: 6
                    color: "#263238"
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        Text { text: "最低海拔"; color: "#90A4AE"; font.pixelSize: 10 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: Math.round(minAlt).toString()
                                color: "#0097A7"
                                font.pixelSize: 20
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Text { text: "m"; color: "#78909C"; font.pixelSize: 11 }
                        }
                    }
                }
                // 时长
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    radius: 6
                    color: "#263238"
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        Text {
                            text: kind === "track" ? "实际时长" : "估算时长"
                            color: "#90A4AE"
                            font.pixelSize: 10
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: mapService.formatDuration(durationS)
                                color: "#5D4037"
                                font.pixelSize: 20
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Text { text: ""; color: "#78909C"; font.pixelSize: 11 }
                        }
                    }
                }
            }

            // === 海拔剖面 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.preferredHeight: 160
                radius: 8
                color: "#1A237E"
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    Text {
                        text: "\ue564 海拔剖面"  // Material Icons: terrain (2026-09-19: 之前 \ue52f 是 bicycle)
                        font.family: "Material Icons"
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    // 2026-09-15: Canvas 移到 ColumnLayout 内部 (与 id 引用同 scope)
                    Canvas {
                        id: profileCanvas
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120
                        antialiasing: true

                        property real padding: 8
                        property real chartW: width - 2 * padding
                        property real chartH: height - 2 * padding

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.fillStyle = "#1A237E"
                            ctx.fillRect(0, 0, width, height)

                            if (!profile || !profile.distances || profile.distances.length < 2) {
                                ctx.fillStyle = "#90A4AE"
                                ctx.font = "12px sans-serif"
                                ctx.textAlign = "center"
                                ctx.fillText("无海拔数据", width / 2, height / 2)
                                return
                            }
                            var dists = profile.distances
                            var elevs = profile.elevations
                            var maxD = dists[dists.length - 1]
                            var minE = elevs[0], maxE = elevs[0]
                            for (var i = 1; i < elevs.length; i++) {
                                if (elevs[i] < minE) minE = elevs[i]
                                if (elevs[i] > maxE) maxE = elevs[i]
                            }
                            if (maxE === minE) maxE = minE + 1
                            var rangeE = maxE - minE

                            // 填充区域
                            ctx.beginPath()
                            ctx.moveTo(padding, height - padding)
                            for (var j = 0; j < dists.length; j++) {
                                var x = padding + (dists[j] / maxD) * chartW
                                var y = padding + (1 - (elevs[j] - minE) / rangeE) * chartH
                                ctx.lineTo(x, y)
                            }
                            ctx.lineTo(padding + chartW, height - padding)
                            ctx.closePath()
                            var grad = ctx.createLinearGradient(0, padding, 0, height - padding)
                            grad.addColorStop(0, "rgba(76, 175, 80, 0.8)")
                            grad.addColorStop(1, "rgba(76, 175, 80, 0.1)")
                            ctx.fillStyle = grad
                            ctx.fill()

                            // 线
                            ctx.beginPath()
                            for (var k = 0; k < dists.length; k++) {
                                var x2 = padding + (dists[k] / maxD) * chartW
                                var y2 = padding + (1 - (elevs[k] - minE) / rangeE) * chartH
                                if (k === 0) ctx.moveTo(x2, y2)
                                else ctx.lineTo(x2, y2)
                            }
                            ctx.strokeStyle = "#4CAF50"
                            ctx.lineWidth = 2
                            ctx.stroke()

                            // 标注最大/最低
                            ctx.fillStyle = "white"
                            ctx.font = "10px sans-serif"
                            ctx.textAlign = "left"
                            ctx.fillText("最高 " + Math.round(maxE) + "m", padding + 4, padding + 12)
                            ctx.fillText("最低 " + Math.round(minE) + "m", padding + 4, height - padding - 4)
                        }

                        Connections {
                            target: root
                            function onProfileReloaded() { profileCanvas.requestPaint() }
                        }
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                    }
                }
            }

            // === 速度分析 (轨迹模式) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.preferredHeight: kind === "track" ? 110 : 0
                visible: kind === "track"
                radius: 8
                color: "#263238"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    Text {
                        text: "⏱ 速度分析"
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        rowSpacing: 4
                        columnSpacing: 6

                        Text { text: "平均"; color: "#B0BEC5"; font.pixelSize: 11 }
                        Text {
                            text: formatSpeed(avgSpeed)
                            color: "white"
                            font.pixelSize: 13
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "配速 " + formatPace(avgPace)
                            color: "#B0BEC5"
                            font.pixelSize: 11
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                        }

                        Text { text: "最快"; color: "#B0BEC5"; font.pixelSize: 11 }
                        Text {
                            text: formatSpeed(maxSpeed)
                            color: "white"
                            font.pixelSize: 13
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "热量 " + Math.round(stats.calorieKcal || 0) + " kcal"
                            color: "#B0BEC5"
                            font.pixelSize: 11
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }

            // === 路线属性 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                visible: kind === "route" || kind === "travel"
                Layout.preferredHeight: routeOrTravelInfoCol.implicitHeight + 24
                radius: 8
                color: "#263238"

                ColumnLayout {
                    id: routeOrTravelInfoCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 4

                    Text {
                        text: "\ue153 基本信息"  // Material Icons: fact_check
                        font.family: "Material Icons"
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                    }
                    // 路线
                    Text {
                        visible: kind === "route"
                        text: "起点: " + (stats.trailheadName || "(未提供)")
                        color: "white"
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: kind === "route"
                        text: "终点: " + (stats.trailendName || "(未提供)")
                        color: "white"
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: kind === "route" && (stats.notRecommended || false)
                        text: "\ue002 " + (stats.notRecommendedReason || "需要特别注意")  // Material Icons: warning
                        font.family: "Material Icons"
                        color: "#FF8A65"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    // 自驾
                    Text {
                        visible: kind === "travel"
                        text: "起点: " + (stats.startName || "") + " (" + (stats.startCity || "") + ")"
                        color: "white"
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: kind === "travel"
                        text: "终点: " + (stats.endName || "") + " (" + (stats.endCity || "") + ")"
                        color: "white"
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: kind === "travel"
                        text: "\ue922 " + (stats.roadType || "未提供") + "  ·  \ue989 ≈¥" + (stats.fuelCostCNY || 0)  // Material Icons: route / local_gas_station
                        font.family: "Material Icons"
                        color: "#B0BEC5"
                        font.pixelSize: 11
                    }
                }
            }

            // === 分段配速表 (轨迹) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.preferredHeight: splitsCol.implicitHeight + 24
                radius: 8
                color: "#263238"
                visible: kind === "track" && stats.splits && stats.splits.length > 0

                ColumnLayout {
                    id: splitsCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 4

                    Text {
                        text: "\ue01d 分段配速 (每公里)"  // Material Icons: equalizer
                        font.family: "Material Icons"
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: "km"; color: "#B0BEC5"; font.pixelSize: 11; Layout.preferredWidth: 30 }
                        Text { text: "用时"; color: "#B0BEC5"; font.pixelSize: 11; Layout.preferredWidth: 60 }
                        Text { text: "配速"; color: "#B0BEC5"; font.pixelSize: 11; Layout.fillWidth: true }
                    }

                    Repeater {
                        model: stats.splits || []
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: modelData.km
                                color: "white"
                                font.pixelSize: 12
                                Layout.preferredWidth: 30
                            }
                            Text {
                                text: mapService.formatDuration(modelData.durationS)
                                color: "white"
                                font.pixelSize: 12
                                Layout.preferredWidth: 60
                            }
                            Text {
                                text: formatPace(modelData.avgPace)
                                color: "#80CBC4"
                                font.pixelSize: 12
                                font.bold: true
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 16 }
        }
    }
}
