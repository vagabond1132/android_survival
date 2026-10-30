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
// 2026-10-19 真机 stage0.log: delegate 里引用外层 id (如 categorySection / searchDialog) 在 qmlcachegen
// 编译下会抛 ReferenceError, 必须 Bound 语义才能拿到外层组件作用域.
pragma ComponentBehavior: Bound
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
    // 2026-10-27 #134: 导入的 GPX/CSV 若文件里没有时间, 逐点时刻整条留空 →
    //   getTrackStats 算不出时长, 而 formatDuration(0) 是 "0小时0分钟" ——
    //   看着像"这趟只走了 0 分钟". 未知时那一格画 "—" (与高程四格同一口径:
    //   未知不出现, 不填 0). 这个标志当时只声明没接线, 2026-10-29 #168 才由
    //   load() 按 durationS 键在不在真正赋值 (见那里的注释).
    property bool durationKnown: true
    // 2026-10-29 #168: 与 durationKnown 同一族 —— 一条没有任何高程的轨迹, 剖面数据里
    //   每个点都是 C++ 填的 0, 画出来是一条贴着 0 的线还标着"最高 0m / 最低 0m"。
    //   这一族未知时剖面整块改成"无海拔数据", 不画假线。
    property bool altKnown: true
    // 2026-10-26「精度到 1 m」: 轨迹这一族才有的定位精度 (getTrackStats 只有在至少
    //   一个点带 ± 时才写这几个键). NaN = 这条轨迹没有任何精度读数 → 整格不出现,
    //   而不是画一个 "±0 m" 让人以为这趟走得极准.
    property real accAvgM: Number.NaN
    property real accBestM: Number.NaN
    property real accWorstM: Number.NaN

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
        durationKnown = true
        altKnown = true
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
                gainM = Number.NaN   // travel.json 没有爬升/下降字段, 原来拿 maxAltitude
                lossM = Number.NaN   // 冒充 gain, 读数会显示成"累计爬升 3500m"
                maxAlt = t.maxAltitude || 0
                minAlt = Number.NaN
                durationS = (t.driveHours || 0) * 3600
                // 自驾只有起终点两个坐标, 没有任何高程序列 —— 剖面留空, 画布按
                // "无海拔数据" 如实呈现. 原来这里塞 [0, gainM] 两点, 画出来的是一根
                // 从 0 直线爬到最高海拔的假剖面.
                profile = { distances: [], elevations: [], speeds: [], timestamps: [] }
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
                // 2026-10-26「精度到 1 m」: 一条全程没有高程的轨迹 (纯 2D 定位, 或
                //   导入时就没有 ele) 原来会把缺键读成 0, 四张卡同时变成
                //   "爬升 0 / 下降 0 / 最高 0 / 最低 0 m" —— 看着像实测数据.
                //   未知改写成 NaN, 由下面的 _altText 画成 "—".
                if (s.hasAltitude === true) {
                    gainM = s.elevationGainM || 0
                    lossM = s.elevationLossM || 0
                    maxAlt = s.maxAlt || 0
                    minAlt = s.minAlt || 0
                } else {
                    gainM = Number.NaN
                    lossM = Number.NaN
                    maxAlt = Number.NaN
                    minAlt = Number.NaN
                    altKnown = false
                }
                avgSpeed = s.avgSpeed || 0
                maxSpeed = s.maxSpeed || 0
                avgPace = s.avgPace || 0
                durationS = s.durationS || 0
                // 2026-10-29 #168: 这个标志之前从没被赋过值 (恒 true), 于是没有时间戳的
                //   导入轨迹在时长格上写出 "0小时0分钟"。C++ 侧现在算不出就不写 durationS
                //   这个键, 这里按"键在不在"判 —— 死接线就此接通。
                durationKnown = s.durationS !== undefined
                // 未知保持 NaN: `s.accuracyAvgM || 0` 会把"没这个键"变成"精度 0 米"
                accAvgM = Number(s.accuracyAvgM)
                accBestM = Number(s.accuracyBestM)
                accWorstM = Number(s.accuracyWorstM)
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

    // === 布局 (2026-10-16 整体改版) ===
    //   ① 6 张统计卡原先是 6 段复制粘贴的 Rectangle (~150 行), 现收为 Repeater
    //      + _statCards 模型; 加一项指标只改模型.
    //   ② 全站 hex → CommonOptions.* / CommonOptions.css() (Canvas 只认 CSS 字符串).
    //   ③ "图标 + 中文" 的 Text 拆成 IconLabel + Text. 之前整段 Text 绑
    //      font.family: "Material Icons", 中文靠 Qt 字形回退渲染, 是改版前
    //      真机"图标方框"同源隐患; 尺寸间距全部走 styles.*.

    Styles { id: styles; visible: false }

    // 统计卡数据: label / value / unit / accent
    // 2026-10-26「精度到 1 m」: 高程未知 (NaN) 时这一格写 "—" 而不是 Math.round(NaN)
    //   出来的 "NaN", 也不写会被当成实测的 "0".
    function _altNum(v) { return isFinite(v) ? Math.round(v).toString() : "—" }
    // 未知时单位也一并撤掉: 写 "— m" 那枚 m 会让这格看着像"长度单位已知的测量"
    function _altUnit(v) { return isFinite(v) ? "m" : "" }
    readonly property var _statCards: [
        { label: "距离",     value: (distM / 1000).toFixed(2), unit: "km",
          accent: CommonOptions.colorAccent },
        { label: "累计爬升", value: _altNum(gainM),  unit: _altUnit(gainM),
          accent: CommonOptions.categoryColor(4) },
        { label: "累计下降", value: _altNum(lossM),  unit: _altUnit(lossM),
          accent: CommonOptions.colorWarn },
        { label: "最高海拔", value: _altNum(maxAlt), unit: _altUnit(maxAlt),
          accent: CommonOptions.categoryColor(3) },
        { label: "最低海拔", value: _altNum(minAlt), unit: _altUnit(minAlt),
          accent: CommonOptions.categoryColor(1) },
        { label: kind === "track" ? "实际时长" : "估算时长",
          // 退出时 mapService 可能先于本绑定销毁, null 守卫防止重算炸一次
          value: durationKnown && mapService ? mapService.formatDuration(durationS) : "—",
          unit: "",
          accent: CommonOptions.colorTrack }
    ]
    // 轨迹带精度读数时多一格; 路线/自驾没有这个概念 → accAvgM 恒为 NaN, 格子不出现.
    readonly property var _cards: {
        var out = root._statCards.slice()
        if (isFinite(accAvgM) && accAvgM > 0) {
            out.push({ label: "定位精度", value: "±" + Math.round(accAvgM), unit: "m",
                       accent: CommonOptions.colorWarn })
        }
        return out
    }

    // 2026-10-29 #169「最快速度压盖热量字体」: 这一组原来不写成卡, 是 GridLayout{columns:3}
    //   里塞两行 "标签(固定 40) + 数值(fillWidth) + 副读数(固定 110)"。三列均分后一格
    //   只有 ~120px, 40+110 还没算数值就已经超了, 副读数被推出格子边界 —— Rectangle 不裁剪,
    //   于是"最快"那行的「热量 …」直接压在相邻文字上。改成与上面 6 张统计卡同一形状
    //   (标签 / 数值 / 副读数各一行), 横向不再抢宽度。
    //   副读数按 [[no-fake-readout-rule]] 只在真有读数时出现: 配速 0 是"算不出",
    //   热量 0 同理, 都不是实测值 → 那一行整行不画。
    readonly property var _speedCards: [
        { label: "平均速度", value: formatSpeed(avgSpeed),
          sub: avgPace > 0 ? "配速 " + formatPace(avgPace) : "",
          accent: CommonOptions.colorTrack },
        { label: "最快速度", value: formatSpeed(maxSpeed),
          sub: (stats.calorieKcal || 0) > 0
               ? "热量 " + Math.round(stats.calorieKcal) + " kcal" : "",
          accent: CommonOptions.colorWarn }
    ]

    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: styles.spMd

            // 加载错误
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.pageGap
                visible: loadError.length > 0
                Layout.preferredHeight: styles.rowHSm
                color: CommonOptions.colorDanger
                radius: styles.rSm
                Text {
                    anchors.centerIn: parent
                    text: loadError
                    color: CommonOptions.colorTextOnAccent
                    font.pixelSize: styles.fsMd
                }
            }

            // === 头部 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.pageGap
                Layout.preferredHeight: styles.rowHTall
                radius: styles.rMd
                color: kind === "route"  ? CommonOptions.colorRouteLine
                     : kind === "travel" ? CommonOptions.colorTeal
                     : CommonOptions.colorSurfaceDim
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: styles.cardPad
                    spacing: styles.spXs
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: name || "(未命名)"
                            color: CommonOptions.colorTextOnAccent
                            font.pixelSize: styles.fsXl
                            font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: _difficultyLabel()
                            color: CommonOptions.colorTextOnAccent
                            font.pixelSize: styles.fsSm
                        }
                    }
                    RowLayout {
                        spacing: styles.spXs
                        IconLabel {
                            name: kind === "route"  ? "hiking"
                                : kind === "travel" ? "car" : "fieldguide"
                            size: styles.icSm
                            tintColor: CommonOptions.colorTextMuted
                        }
                        Text {
                            Layout.fillWidth: true
                            text: kind === "route"  ? "徒步路线"
                                : kind === "travel" ? "自驾游" : "轨迹记录"
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsSm
                        }
                    }
                }
            }

            // === 基础统计卡 ===
            GridLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageGap
                Layout.rightMargin: styles.pageGap
                columns: 3
                rowSpacing: styles.cardGap
                columnSpacing: styles.cardGap

                Repeater {
                    model: root._cards
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: styles.rowHTall
                        radius: styles.rSm
                        color: CommonOptions.colorSurface
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: styles.spSm
                            spacing: 2
                            Text {
                                text: modelData.label
                                color: CommonOptions.colorTextDim
                                font.pixelSize: styles.fsXs
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    text: modelData.value
                                    color: modelData.accent
                                    font.pixelSize: styles.fsXl
                                    font.bold: true
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: modelData.unit
                                    color: CommonOptions.colorTextDisabled
                                    font.pixelSize: styles.fsSm
                                }
                            }
                        }
                    }
                }
            }

            // === 海拔剖面 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageGap
                Layout.rightMargin: styles.pageGap
                Layout.preferredHeight: styles.chartH
                radius: styles.rMd
                color: CommonOptions.colorRouteLine
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spSm
                    spacing: styles.spXs

                    SectionTitle {
                        Layout.fillWidth: true
                        icon: "terrain"
                        text: "海拔剖面"
                        // 海拔卡底色是 colorRouteLine (深色主色底), 标题要反白
                        titleColor: CommonOptions.colorTextOnAccent
                        iconColor: CommonOptions.colorTextOnAccent
                        pixelSize: styles.fsMd
                    }

                    // 2026-09-15: Canvas 移到 ColumnLayout 内部 (与 id 引用同 scope)
                    Canvas {
                        id: profileCanvas
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        antialiasing: true

                        property real padding: styles.spSm
                        property real chartW: width - 2 * padding
                        property real chartH: height - 2 * padding

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.fillStyle = CommonOptions.css(CommonOptions.colorRouteLine)
                            ctx.fillRect(0, 0, width, height)

                            var labelFont = styles.fsSm + "px " + Qt.application.font.family
                            var noteFont  = styles.fsXs + "px " + Qt.application.font.family

                            if (!root.altKnown
                                || !profile || !profile.distances || profile.distances.length < 2) {
                                ctx.fillStyle = CommonOptions.css(CommonOptions.colorTextDim)
                                ctx.font = labelFont
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
                            grad.addColorStop(0, CommonOptions.css(CommonOptions.colorSuccess, 0.8))
                            grad.addColorStop(1, CommonOptions.css(CommonOptions.colorSuccess, 0.1))
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
                            ctx.strokeStyle = CommonOptions.css(CommonOptions.colorSuccess)
                            ctx.lineWidth = 2
                            ctx.stroke()

                            // 标注最大/最低
                            ctx.fillStyle = CommonOptions.css(CommonOptions.colorTextOnAccent)
                            ctx.font = noteFont
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
                Layout.leftMargin: styles.pageGap
                Layout.rightMargin: styles.pageGap
                // 卡片高度跟着内容走: 原来写死 rowH*2, 副读数一换行就被裁
                Layout.preferredHeight: speedCol.implicitHeight + styles.spSm * 2
                visible: kind === "track"
                radius: styles.rMd
                color: CommonOptions.colorSurface

                ColumnLayout {
                    id: speedCol
                    anchors.fill: parent
                    anchors.margins: styles.spSm
                    spacing: styles.spXs

                    SectionTitle {
                        Layout.fillWidth: true
                        icon: "trending_up"
                        text: "速度分析"
                    }

                    // 两列: 一格 ~190px, 标签 / 数值 / 副读数各占一行, 谁也不挤谁
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: styles.cardGap
                        columnSpacing: styles.cardGap

                        Repeater {
                            model: root._speedCards
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: speedCardCol.implicitHeight
                                                       + styles.spSm * 2
                                radius: styles.rSm
                                color: CommonOptions.colorSurface
                                ColumnLayout {
                                    id: speedCardCol
                                    anchors.fill: parent
                                    anchors.margins: styles.spSm
                                    spacing: 2
                                    Text {
                                        text: modelData.label
                                        color: CommonOptions.colorTextDim
                                        font.pixelSize: styles.fsXs
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.value
                                        color: modelData.accent
                                        font.pixelSize: styles.fsXl
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: text.length > 0
                                        text: modelData.sub
                                        color: CommonOptions.colorTextMuted
                                        font.pixelSize: styles.fsXs
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // === 路线属性 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageGap
                Layout.rightMargin: styles.pageGap
                visible: kind === "route" || kind === "travel"
                Layout.preferredHeight: routeOrTravelInfoCol.implicitHeight
                                        + styles.cardPad * 2
                radius: styles.rMd
                color: CommonOptions.colorSurface

                ColumnLayout {
                    id: routeOrTravelInfoCol
                    anchors.fill: parent
                    anchors.margins: styles.cardPad
                    spacing: styles.spXs

                    SectionTitle {
                        Layout.fillWidth: true
                        icon: "flag"
                        text: "基本信息"
                        // 本卡片底色是 colorSurface, 不是主色底 → 标题用主文字色
                        pixelSize: styles.fsMd
                        titleColor: CommonOptions.colorText
                        iconColor: CommonOptions.colorAccent
                    }
                    // 路线
                    Text {
                        visible: kind === "route"
                        text: "起点: " + (stats.trailheadName || "(未提供)")
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsSm
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: kind === "route"
                        text: "终点: " + (stats.trailendName || "(未提供)")
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsSm
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        visible: kind === "route" && (stats.notRecommended || false)
                        spacing: styles.spXs
                        IconLabel {
                            name: "warning"
                            size: styles.icSm
                            tintColor: CommonOptions.colorWarn
                        }
                        Text {
                            Layout.fillWidth: true
                            text: stats.notRecommendedReason || "需要特别注意"
                            color: CommonOptions.colorWarn
                            font.pixelSize: styles.fsSm
                            wrapMode: Text.WordWrap
                        }
                    }
                    // 自驾
                    Text {
                        visible: kind === "travel"
                        text: "起点: " + (stats.startName || "") + " (" + (stats.startCity || "") + ")"
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsSm
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: kind === "travel"
                        text: "终点: " + (stats.endName || "") + " (" + (stats.endCity || "") + ")"
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsSm
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        visible: kind === "travel"
                        spacing: styles.spXs
                        IconLabel {
                            name: "route"
                            size: styles.icSm
                            tintColor: CommonOptions.colorTextDim
                        }
                        Text {
                            text: stats.roadType || "未提供"
                            color: CommonOptions.colorTextDim
                            font.pixelSize: styles.fsSm
                        }
                        Item { Layout.preferredWidth: styles.spSm }
                        IconLabel {
                            name: "fuel"
                            size: styles.icSm
                            tintColor: CommonOptions.colorTextDim
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "≈¥" + (stats.fuelCostCNY || 0)
                            color: CommonOptions.colorTextDim
                            font.pixelSize: styles.fsSm
                        }
                    }
                }
            }

            // === 分段配速表 (轨迹) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageGap
                Layout.rightMargin: styles.pageGap
                Layout.preferredHeight: splitsCol.implicitHeight + styles.cardPad * 2
                radius: styles.rMd
                color: CommonOptions.colorSurface
                visible: kind === "track" && stats.splits && stats.splits.length > 0

                ColumnLayout {
                    id: splitsCol
                    anchors.fill: parent
                    anchors.margins: styles.cardPad
                    spacing: styles.spXs

                    SectionTitle {
                        Layout.fillWidth: true
                        icon: "timeline"
                        text: "分段配速 (每公里)"
                        pixelSize: styles.fsMd
                        titleColor: CommonOptions.colorText
                        iconColor: CommonOptions.colorAccent
                    }

                    // 表头 + 数据行同用一套列宽, 避免改版后左右错位
                    readonly property int kmW: 40
                    readonly property int durW: 72

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm
                        Text {
                            text: "km"
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsSm
                            Layout.preferredWidth: splitsCol.kmW
                        }
                        Text {
                            text: "用时"
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsSm
                            Layout.preferredWidth: splitsCol.durW
                        }
                        Text {
                            text: "配速"
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsSm
                            Layout.fillWidth: true
                        }
                    }

                    Repeater {
                        model: stats.splits || []
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: styles.spSm
                            Text {
                                text: modelData.km
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsSm
                                Layout.preferredWidth: splitsCol.kmW
                            }
                            Text {
                                text: mapService.formatDuration(modelData.durationS)
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsSm
                                Layout.preferredWidth: splitsCol.durW
                            }
                            Text {
                                text: formatPace(modelData.avgPace)
                                color: CommonOptions.colorTeal
                                font.pixelSize: styles.fsSm
                                font.bold: true
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: styles.pageGap }
        }
    }
}
