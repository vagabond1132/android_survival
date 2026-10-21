/**
 * @file TrackDetailPage.qml
 * @brief 轨迹分析 (2026-10-21 v9 F2 同款, 丁骨架二级页)
 *
 * 入口只有一个: ④地图 → 导航 Tab 轨迹行右侧那枚 32px 方块 (NavigationTab
 *   .trackAnalyzeRequested → MapPage.openTrackDetail → navBus.trackDetail →
 *   Main.qml 把本页压进 stackView). 别的页都不跳这里, 所以底栏左键就叫「回地图」.
 *
 * 版式 (F2 详情母版, 与路线详情 / 时节装备推荐同一套骨架):
 *   图版头 150px: --paper-sunk 底 + 1px 墨线压底; 左上"来源"chip (本机记录 / 导入 GPX),
 *           右上 26px 方角返回; 中间是里程 + 时长/配速两行读数; 底下 编号 + 起点时间 +
 *           名称 (21px 800). 本页没有配图 (库里没有轨迹截图), 这一带就放读数不放假图.
 *   读数带  4 格 (里程 / 时长 / 累计爬升 / 配速), 格子里只放裸数字, 单位在栏头说一次.
 *   正文    失败话术 → 海拔曲线 → 速度曲线 → 6 项统计 → 卡路里 → 每公里分段 → 休息点.
 *   底栏    1px 墨线 + --card-2 底; 左 88px 空心「回地图」, 右实心「删除这条轨迹」.
 *
 * 四条不能破的规则:
 *   ① 不编读数. 图版头/读数带/统计/分段/休息点全部来自 mapService 的三个接口
 *      (getTrackById / getTrackStats / getTrackProfile), 页面自己不现算任何"评分子".
 *      唯一的例外是卡路里: getTrackStats(trackId, 65.0) 的体重是本页给死的常数,
 *      库里没有用户体重 → 那句话就写在数字旁边, 不糊"约消耗"两个字过关.
 *   ② 曲线只画真实采样. profile.distances/elevations/speeds 有几对点就画几对,
 *      不插值、不平滑、不补首尾. 没取到 profile 时图表直接不给看 (整块不出现),
 *      而不是画一张空坐标系骗版面.
 *   ③ 失败要留得下. 旧版三处统计加载失败靠 Card 里一行红底白字, 滚过就看不见;
 *      现在统一落到正文顶部的 note (与 ①②③ 页同一枚琥珀色), 一直在.
 *   ④ 汉字不进等宽. 编号/坐标/时间/数字走 monoFont, 名称·单位·说明走默认字体
 *      (见 [[qml-monofont-no-cjk]]). 坐标 5 位小数是 GPS 原生精度, 不四舍五入成 2 位.
 *
 * 2026-10-21 顺带修掉的两处:
 *   - 两张曲线只在 ChartView 自己的 Component.onCompleted 画一次. 同一条轨迹重新
 *     记录或重新导入 (mapService 发 dataChanged → refresh() 重取 profile) 之后,
 *     数字条会变、图还是旧的. 现在连 profile 变化一起重画.
 *   - 全站没有任何地方能删轨迹: mapService.deleteTrack 是能用的 C++ 接口 (删
 *     track_<id>.json + track_<id>_points.json 并 emit dataChanged), 但 QML 里零引用
 *     —— 导错的 GPX 只能一直躺在列表里. 底栏给出入口, 不可逆的动作先过确认对话框.
 */

// delegate 里要读 trackDetail 的属性与方法, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtCharts
import OutdoorSurvival 1.0

Page {
    id: trackDetail

    Styles { id: styles; visible: false }

    title: track.name || "轨迹分析"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 状态 ==============================================================
    property string trackId: ""
    property var track: ({})
    property var stats: ({})
    property var profile: ({})
    // 失败 / 提醒话术 (规则 ③: 看得见, 不闪)
    property string note: ""

    readonly property bool hasTrack: (track.id || "").length > 0
    readonly property bool hasStats: stats.ok === true
    readonly property real _km: Number(stats.distanceM || 0) / 1000.0
    readonly property int _gain: Math.round(Number(stats.elevationGainM || 0))
    readonly property int _loss: Math.round(Number(stats.elevationLossM || 0))
    readonly property int _maxAlt: Math.round(Number(stats.maxAlt || 0))
    readonly property int _minAlt: Math.round(Number(stats.minAlt || 0))
    readonly property int _pts: Number(stats.pointCount || 0)
    readonly property int _kcal: Math.round(Number(stats.calorieKcal || 0))
    readonly property var _splits: _toArr(stats.splits)
    readonly property var _rests: _toArr(stats.restPoints)

    // 来源: 本机记录 vs 导入 (导入时把原始格式带上, 数据里有 originalFormat)
    readonly property string sourceLine: {
        if (track.source === "imported") {
            var fmt = String(track.originalFormat || "").toUpperCase()
            return fmt.length > 0 ? ("导入 " + fmt) : "外部导入"
        }
        if (track.source === "recorded") return "本机记录"
        return ""
    }

    function _toArr(v) { return (v && v.length !== undefined) ? v : [] }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    // 2026-09-20 修 Bug 20 的三条守卫原样保留: 单次加载 + Connections.enabled 跟
    //   visible 绑 + ignoreNext 标志 (refresh 自己触发的 dataChanged 不再回环一次).
    property bool _ignoreNextDataChanged: false
    onTrackIdChanged: {
        if (trackId) {
            _ignoreNextDataChanged = true
            refresh()
        }
    }
    Connections {
        target: mapService
        enabled: trackDetail.visible
        function onDataChanged() {
            if (trackDetail._ignoreNextDataChanged) {
                trackDetail._ignoreNextDataChanged = false
                return
            }
            refresh()
        }
    }

    function refresh() {
        if (!trackId) return
        // 上下文服务在页面销毁过程中可能已为 null
        if (!mapService) {
            console.warn("[track detail] mapService 不可用, trackId=" + trackId)
            return
        }
        var r = mapService.getTrackById(trackId)   // 契约是 Result, 读 .value
        trackDetail.note = ""
        track = (r && r.ok) ? r.value : {}
        if (r && !r.ok) {
            trackDetail.note = "这条轨迹没取到: " + ((r.error && r.error.message) || "未知错误")
        }
        stats = mapService.getTrackStats(trackId, 65.0)
        profile = mapService.getTrackProfile(trackId)
        if (stats.ok === false) {
            trackDetail.note = "统计没算出来: " + (stats.error || "未知错误")
        }
    }

    // 删除 (底栏 → 确认对话框). 成功后直接退页, 失败留在 note 里.
    function doDelete() {
        if (!mapService) {
            trackDetail.note = "地图服务还没就绪, 删不了。"
            return
        }
        var r = mapService.deleteTrack(trackId)
        if (r && r.ok) {
            trackDetail.goBack()
            return
        }
        trackDetail.note = "删除失败: " + ((r && r.error && r.error.message)
                                          || "轨迹文件没删掉")
    }

    // === 格式化 ============================================================
    // 配速 (min/km → "8'12\"/km")
    function formatPace(pace) {
        if (!pace || pace <= 0 || pace > 99) return "--"
        var m = Math.floor(pace)
        var s = Math.round((pace - m) * 60)
        if (s === 60) { m++; s = 0 }
        return m + "'" + (s < 10 ? "0" + s : s) + "\"/km"
    }
    // 时长 (s → "H:MM:SS" 或 "MM:SS")
    function formatDuration(sec) {
        if (!sec || sec <= 0) return "--"
        var h = Math.floor(sec / 3600)
        var m = Math.floor((sec % 3600) / 60)
        var s = sec % 60
        if (h > 0) return h + ":" + (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s)
        return m + ":" + (s < 10 ? "0" + s : s)
    }
    // 速度 (m/s → km/h 一位小数)
    function formatSpeed(ms) {
        if (!ms || ms <= 0) return "0.0"
        return (ms * 3.6).toFixed(1)
    }
    // MapService 写的是 Qt::ISODate ("2026-10-20T12:34:56"). 直接切字符串比 new Date()
    // 解析稳 —— 导入的 GPX 时间戳格式五花八门, 解析失败会得到 NaN (与导航 Tab 同一口径).
    function _stampLabel(s) {
        var t = String(s || "")
        if (t.length >= 16 && t.charAt(10) === "T") {
            return t.substring(5, 10) + " " + t.substring(11, 16)
        }
        return t
    }

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- ① 图版头 (150px) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            color: CommonOptions.colorSurfaceDim

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            // 中间: 里程 + (时长 / 配速). 本页没有难度概念, 这一行不放 Ladder.
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: styles.spLg
                spacing: 5

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4
                    Text {
                        anchors.bottom: parent.bottom
                        text: trackDetail._km > 0 ? trackDetail._km.toFixed(2) : "—"
                        font.family: styles.monoFont
                        font.pixelSize: 34
                        color: CommonOptions.colorText
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        visible: trackDetail._km > 0
                        text: "km"
                        font.pixelSize: styles.fsMd
                        color: CommonOptions.colorTextMuted
                    }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: styles.spMd
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: trackDetail.formatDuration(Number(trackDetail.stats.durationS || 0))
                              + " / " + trackDetail.formatPace(trackDetail.stats.avgPace)
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsSm
                        color: CommonOptions.colorInk3
                    }
                }
            }

            // 左上: 来源 (本机记录 / 导入 GPX); 数据里没有就整枚不显示
            Chip {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: styles.pageMargin
                anchors.topMargin: styles.spSm
                visible: text.length > 0
                text: trackDetail.sourceLine
                accent: CommonOptions.colorInk3
                checked: true
                textSize: styles.fsXs
            }

            // 右上: 返回方角 26px, 热区向外扩 9px 到 44 (戴手套)
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: styles.pageMargin
                anchors.topMargin: styles.spSm
                width: 26
                height: 26
                color: CommonOptions.colorSurface
                border.color: CommonOptions.colorText
                border.width: styles.lineHair
                IconLabel {
                    anchors.centerIn: parent
                    name: "back"
                    size: styles.icSm
                    tintColor: CommonOptions.colorText
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -9
                    cursorShape: Qt.PointingHandCursor
                    onClicked: trackDetail.goBack()
                }
            }

            // 底部: 编号 + 起点时间 (左/右) / 名称
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                anchors.bottomMargin: styles.spSm
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Plate {
                        Layout.alignment: Qt.AlignVCenter
                        code: "PLATE " + CommonOptions.plateCode("TR", trackDetail.trackId)
                        tone: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        visible: trackDetail._stampLabel(track.startTime).length > 0
                        text: "起点 " + trackDetail._stampLabel(track.startTime)
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: track.name || "未命名轨迹"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
            }
        }

        // --- ② 四格读数带 ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: readoutCol.implicitHeight + 2 * styles.spSm
            color: CommonOptions.colorSurface
            visible: trackDetail.hasStats

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: styles.lineHair
                color: CommonOptions.colorRule
            }

            ColumnLayout {
                id: readoutCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                spacing: styles.spSm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "TRACK READOUT"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        font.letterSpacing: 1.4
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    // 单位只在这里说一次: 格子里全是裸数字, 汉字不许挤进等宽栏
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "单位 km / 时:分:秒 / 米 / 每公里"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: [
                            { k: "DIST", v: trackDetail._km > 0 ? trackDetail._km.toFixed(2) : "—" },
                            { k: "TIME", v: trackDetail.formatDuration(Number(trackDetail.stats.durationS || 0)) },
                            { k: "GAIN", v: trackDetail._gain > 0 ? ("+" + trackDetail._gain) : "0" },
                            { k: "PACE", v: trackDetail.formatPace(trackDetail.stats.avgPace) }
                        ]
                        delegate: RowLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 0
                            Rectangle {
                                visible: index > 0
                                Layout.preferredWidth: styles.lineHair
                                Layout.fillHeight: true
                                color: CommonOptions.colorRuleSoft
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.k
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsXs
                                    font.letterSpacing: 1.2
                                    color: CommonOptions.colorInk3
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.v
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsLg
                                    color: CommonOptions.colorText
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // 采样点数: 读数带只给四格, 这一项跟在栏下说完 (它决定曲线精度)
                Text {
                    Layout.fillWidth: true
                    text: trackDetail._pts + " 个采样点"
                          + (trackDetail._pts < 50 ? " · 点太少, 曲线只能看出大概起伏" : "")
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                }
            }
        }

        // --- ③ 正文 ---
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: styles.spLg

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    Layout.topMargin: styles.spMd
                    visible: trackDetail.note.length > 0
                    text: trackDetail.note
                    font.pixelSize: styles.fsSm
                    color: CommonOptions.colorLegendAmber
                    wrapMode: Text.WordWrap
                }

                // 海拔 / 速度 —— 两张图都要真取到 profile 才出现 (规则 ②)
                Repeater {
                    model: [
                        { kick: "ELEVATION", name: "海拔曲线", unit: "海拔 m",
                          tone: CommonOptions.colorForest, series: "alt" },
                        { kick: "SPEED", name: "速度曲线", unit: "速度 km/h",
                          tone: CommonOptions.colorWater, series: "spd" }
                    ]
                    delegate: ColumnLayout {
                        id: chartBlock
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        spacing: styles.spSm
                        // distances/elevations/speeds 三样都来自同一个 profile
                        visible: trackDetail.profile.ok === true
                                 && trackDetail._toArr(trackDetail.profile.distances).length > 1

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spSm
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: styles.lineAccent
                                Layout.preferredHeight: styles.fsLg
                                color: chartBlock.modelData.tone
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: chartBlock.modelData.name
                                font.pixelSize: styles.fsLg
                                font.bold: true
                                color: CommonOptions.colorText
                            }
                            Item { Layout.fillWidth: true }
                            // 汉字与码位分开两个节点: monoFont 里没有 CJK 字形
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "横轴 距离 km"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: chartBlock.modelData.kick
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsXs
                                font.letterSpacing: 1.2
                                color: CommonOptions.colorInk3
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: styles.chartH
                            color: CommonOptions.colorSurface
                            border.color: CommonOptions.colorRule
                            border.width: styles.lineHair

                            ChartView {
                                id: chart
                                anchors.fill: parent
                                anchors.margins: styles.spXs
                                antialiasing: true
                                legend.visible: false
                                title: ""
                                backgroundColor: CommonOptions.colorSurface
                                plotAreaColor: CommonOptions.colorSurface

                                property bool isAlt: chartBlock.modelData.series === "alt"

                                ValueAxis {
                                    id: axisX
                                    titleText: "距离 (km)"
                                    labelFormat: "%.1f"
                                    min: 0
                                    max: Number(trackDetail.stats.distanceM || 0) > 0
                                         ? trackDetail._km : 1
                                }
                                ValueAxis {
                                    id: axisY
                                    titleText: chartBlock.modelData.unit
                                    labelFormat: chart.isAlt ? "%.0f" : "%.1f"
                                    min: 0
                                    max: 1
                                }
                                LineSeries {
                                    id: series
                                    name: chartBlock.modelData.name
                                    axisX: axisX
                                    axisY: axisY
                                    color: chartBlock.modelData.tone
                                    width: 2
                                }

                                // 规则 ②: 只画 profile 里真实存在的点, 不插值不平滑不补首尾.
                                // 距离与数值两组数组长度可能不一致 (导入的 GPX 缺 ele),
                                // 按短的截 —— 多出来的点没有配对值, 画出来就是编的.
                                function redraw() {
                                    series.clear()
                                    var d = trackDetail._toArr(trackDetail.profile.distances)
                                    if (d.length < 2) return
                                    var vals = trackDetail._toArr(chart.isAlt
                                                                   ? trackDetail.profile.elevations
                                                                   : trackDetail.profile.speeds)
                                    var n = Math.min(d.length, vals.length)
                                    var i
                                    if (chart.isAlt) {
                                        var hi = -1e9, lo = 1e9
                                        for (i = 0; i < n; ++i) {
                                            if (vals[i] > hi) hi = vals[i]
                                            if (vals[i] < lo) lo = vals[i]
                                        }
                                        if (hi === lo) { hi += 100; lo = Math.max(0, lo - 100) }
                                        axisY.min = Math.floor(lo / 100) * 100
                                        axisY.max = Math.ceil(hi / 100) * 100
                                    } else {
                                        var mx = 0
                                        for (i = 0; i < n; ++i) {
                                            if (vals[i] > mx) mx = vals[i]
                                        }
                                        if (mx < 0.1) mx = 1
                                        axisY.min = 0
                                        axisY.max = Math.ceil((mx * 3.6) / 2) * 2
                                    }
                                    for (i = 0; i < n; ++i) {
                                        series.append(d[i] / 1000.0,
                                                      chart.isAlt ? vals[i] : vals[i] * 3.6)
                                    }
                                }

                                Component.onCompleted: redraw()
                                // profile 每次 refresh 是整体重新赋值 → 变化信号必须重画.
                                // 旧版只在 onCompleted 画一次, 重新记录/导入之后数字条变了
                                // 曲线还是旧的.
                                Connections {
                                    target: trackDetail
                                    function onProfileChanged() { chart.redraw() }
                                }
                            }
                        }
                    }
                }

                // 其余 6 项统计 (读数带那 4 项不重复列)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    visible: trackDetail.hasStats

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: styles.lineAccent
                            Layout.preferredHeight: styles.fsLg
                            color: CommonOptions.colorText
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "其余统计"
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            color: CommonOptions.colorText
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "READOUT 6"
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsXs
                            font.letterSpacing: 1.2
                            color: CommonOptions.colorInk3
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: styles.spSm
                        columnSpacing: styles.spLg

                        Repeater {
                            model: [
                                { k: "平均速度", v: trackDetail.formatSpeed(trackDetail.stats.avgSpeed) + " km/h" },
                                { k: "最大速度", v: trackDetail.formatSpeed(trackDetail.stats.maxSpeed) + " km/h" },
                                { k: "累计下降", v: trackDetail._loss + " m" },
                                { k: "最高海拔", v: trackDetail._maxAlt + " m" },
                                { k: "最低海拔", v: trackDetail._minAlt + " m" },
                                { k: "卡路里", v: trackDetail._kcal + " kcal" }
                            ]
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: styles.spSm
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData.k
                                    font.pixelSize: styles.fsSm
                                    color: CommonOptions.colorTextMuted
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: styles.lineHair
                                    color: CommonOptions.colorRuleSoft
                                }
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData.v
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsSm
                                    color: CommonOptions.colorText
                                }
                            }
                        }
                    }

                    // 卡路里的体重是本页给死的常数, 写在数字旁边 (规则 ①)
                    Text {
                        Layout.fillWidth: true
                        text: "卡路里按 65 kg 体重折算 —— 这是本页写死的常数, 不是你的体重; "
                              + "轨迹库里没有体重, 这个数只能当量级看。"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                        wrapMode: Text.WordWrap
                    }
                }

                // 每公里分段
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spXs
                    visible: trackDetail.hasStats

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: styles.lineAccent
                            Layout.preferredHeight: styles.fsLg
                            color: CommonOptions.colorText
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "分段配速"
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            color: CommonOptions.colorText
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: trackDetail._splits.length + " SPLIT"
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsXs
                            font.letterSpacing: 1.2
                            color: CommonOptions.colorInk3
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: trackDetail._splits.length === 0
                        text: "不足一公里, 引擎没有分段可切。"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }

                    Repeater {
                        model: trackDetail._splits
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: styles.spSm
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 34
                                text: String(modelData.km || 0)
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsSm
                                color: CommonOptions.colorText
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "km"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (Number(modelData.distanceKm || 0)).toFixed(2) + " km 段长"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: trackDetail.formatDuration(Number(modelData.durationS || 0))
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsSm
                                color: CommonOptions.colorTextMuted
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 84
                                horizontalAlignment: Text.AlignRight
                                text: trackDetail.formatPace(modelData.avgPace)
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsSm
                                font.bold: true
                                color: CommonOptions.colorText
                            }
                        }
                    }
                }

                // 休息点 (引擎阈值 3 分钟)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spXs
                    visible: trackDetail.hasStats

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: styles.lineAccent
                            Layout.preferredHeight: styles.fsLg
                            color: CommonOptions.colorLegendAmber
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "休息点"
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            color: CommonOptions.colorText
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "3 MIN+ · " + trackDetail._rests.length
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsXs
                            font.letterSpacing: 1.2
                            color: CommonOptions.colorInk3
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: trackDetail._rests.length === 0
                        text: "全程没有停下超过 3 分钟。"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }

                    Repeater {
                        model: trackDetail._rests
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: styles.spSm
                            Text {
                                Layout.fillWidth: true
                                text: Number(modelData.lat || 0).toFixed(5) + ", "
                                      + Number(modelData.lon || 0).toFixed(5)
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorTextMuted
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: trackDetail.formatDuration(Number(modelData.durationS || 0))
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsSm
                                color: CommonOptions.colorLegendAmber
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spXl }
            }
        }

        // --- ④ 底栏 ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: bottomRow.implicitHeight + 2 * styles.spSm
            color: CommonOptions.colorSurfaceAlt

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            RowLayout {
                id: bottomRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: styles.spLg
                anchors.rightMargin: styles.spLg
                spacing: styles.spMd

                OutlineButton {
                    Layout.preferredWidth: 88
                    Layout.alignment: Qt.AlignVCenter
                    text: "回地图"
                    tone: CommonOptions.colorTextMuted
                    textSize: styles.fsSm
                    onClicked: trackDetail.goBack()
                }
                Item { Layout.fillWidth: true }
                PrimaryButton {
                    Layout.alignment: Qt.AlignVCenter
                    text: "删除这条轨迹"
                    iconName: "delete"
                    tone: CommonOptions.colorText
                    textSize: styles.fsSm
                    enabled: trackDetail.hasTrack
                    onClicked: deleteDialog.open()
                }
            }
        }
    }

    // 不可逆动作先过确认 —— 按钮文案走中文 footer (#41 母版)
    Dialog {
        id: deleteDialog
        title: "删除这条轨迹?"
        anchors.centerIn: parent
        width: Math.min(360, trackDetail.width - 2 * styles.pageMargin)
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        padding: styles.spMd

        Text {
            text: "要删的是 " + (track.name || "未命名轨迹")
                  + " —— 轨迹本体和 " + trackDetail._pts
                  + " 个采样点一起从存储里去掉, 删完找不回来。"
            color: CommonOptions.colorText
            font.pixelSize: styles.fsMd
            wrapMode: Text.WordWrap
        }

        footer: RowLayout {
            spacing: styles.spSm
            Item { Layout.fillWidth: true }
            OutlineButton {
                text: "留着"
                tone: CommonOptions.colorTextMuted
                onClicked: deleteDialog.close()
            }
            PrimaryButton {
                text: "删除"
                tone: CommonOptions.colorDanger
                textSize: styles.fsMd
                onClicked: {
                    deleteDialog.close()
                    trackDetail.doDelete()
                }
            }
        }
    }
}
