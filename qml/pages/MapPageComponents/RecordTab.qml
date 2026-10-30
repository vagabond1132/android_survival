/**
 * @file RecordTab.qml
 * @brief 记录 Tab: track 启动/暂停/停止 + 拍照
 *
 * 2026-09-20 改版: 紧凑 GPS app 风格
 *   - 顶部状态行: 脉冲红点 + 状态文字 + 时长
 *   - 中部统计: 距离 + 点数 + 当前频率 (单行, 不再 ComboBox 单独一行)
 *   - 频率 chip 横排 (替代下拉框, 一眼看到所有选项)
 *   - 主按钮 (开始/停止) 占主, 拍照为右侧方形辅助按钮
 * 2026-10-19 整体改版 (props / signal / 函数一律不动):
 *   - 裸尺寸换 Styles token (原来 12/10/6/4/8/50/56/14/7/22 一堆裸数字,
 *     16/11/12/10 裸字号).
 *   - 状态+统计收进 Card + StatTile; 频率 chip 换共享 Chip; 主按钮换
 *     PrimaryButton; 拍照图标换 IconLabel 语义名 photo (之前是裸码位 Text
 *     自挂图标字族).
 *   - "■"/"●" 几何符号 (本图标字体无此字形, 依赖系统回退) → play / stop 语义图标.
 *   - 对比度修复: 未录制状态标题原用 colorTextOnAccent 白字画在 sheet 的
 *     colorSurface 深灰底上 (白字只该出现在饱和色填充上) → colorText;
 *     底部提示原 colorTextDisabled (对 colorSurface 仅 3.0:1) → colorTextDim
 *     (4.9:1).
 *   - mapService 是上下文属性, 拆解构前可能为 null → 全部加守卫.
 * 2026-10-23 #109: 新轨迹名从 UTC 原始 ISO ("轨迹 2026-10-22T01:31:46") 改成本地
 *   MM-DD HH:MM —— 这名字落盘进 track_<id>.json 当「轨迹」Tab 行标题, 原来和
 *   C++ 侧本地时间 startTime 差 8 小时, 同一行标题/副标题自相矛盾.
 * 2026-10-28 #156 按两步路工作台改版 (props / signal / 采样链路一律不动):
 *   - 标题行 → SheetPanelHead (标题 + "正在记录 · 每 N 秒" + ✕ 收起 一行).
 *   - 三颗 StatTile → 一张卡里的 hero 读数 (公里, fs2xl) + 2×2 ReadoutCell
 *     (时长/点数/均速/最后一点精度), 每个读数各自带实测时刻, 未知整格不出现.
 *   - 通栏「开始记录」+ 右侧方形拍照钮 → 底部 SheetActionBand 四格
 *     (开始记录 / 拍照 / 标注这里 / 收起). 「标注这里」原来常驻在抽屉底部通栏,
 *     现在归本面板, 动作经 annotateRequested 上抛.
 *   - 面板向抽屉报 preferredSheetHeight (本面没有列表, 撑满 409 就是中部死白).
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

// delegate 里读外层 id (styles / root): qmlcachegen 静态编译下没有 Bound 语义
// 会在真机静默 ReferenceError —— 地图「记录」Tab 中部空白 (#30) 的候选真因.
pragma ComponentBehavior: Bound

Item {
    id: root

    // 2026-10-16 整体改版: 尺寸/间距 token 实例 (Wave 3 逐页替换用)
    Styles { id: styles; visible: false }

    property bool isRecording: false
    property string currentTrackId: ""
    property var freqOptions: []
    property int selectedFreq: 5

    // 录制中实时统计
    property int recordedPoints: 0
    property real recordedDistanceKm: 0
    property int recordedDurationSec: 0

    // 2026-10-26「轨迹/标注点精度到 1 m」: 上一个**已落盘**采样点的状态.
    //   NaN = 还没有点. _lastAccM 用来决定下一个点值不值得写 (静止抖动过滤).
    property real _lastLat: Number.NaN
    property real _lastLon: Number.NaN
    property real _lastAccM: Number.NaN
    // 2026-10-28 #156: 最后一个**已落盘**点的本地时刻 (HH:MM:SS). 空串 = 还没有点.
    //   数据卡右上那句"最后一点 ±3.2 m · 14:22:07" 的采样时刻 —— 旧读数必须带时刻
    //   是 [[no-fake-readout-rule]] 的另一半: 只显示 ± 而不说它是几点测的, 停十分钟
    //   再看就成了"现在还很准".
    property string _lastSampleAt: ""
    // 采样被跳过的两类原因分开数, 屏幕上说得出"为什么 5 分钟只录了 3 个点"
    property int _skippedNoFix: 0
    property int _skippedStill: 0

    // 拍照请求 (外层 MapPage 接 signal 调 androidPlatform.takePhoto)
    signal captureRequested()
    // 2026-10-28 #156: 「标注这里」原来是抽屉底部那颗通栏按钮, 现在收进本面板的
    //   动作带 —— 抽屉里那顆常驻按钮整个删掉, 动作改由这里上抛, MapBottomSheet 转给 MapPage.
    signal annotateRequested()
    signal foldRequested()

    // 抽屉展开态想要多高. 记录是四面里唯一**没有列表**的面板, 硬撑到 409 就是
    // pass9 ④ 那片中部死白的成因; 所以本面板按自己的内容高度报, 由抽屉取 min.
    // 不录的时候卡片区整块不占位 (见 [[no-fake-readout-rule]]), 面板跟着缩到一行
    // 频率 chips + 动作带的高度 —— 这一下缩也是"你没在录"的可见反馈.
    readonly property int preferredSheetHeight:
        Math.min(styles.sheetExpH, contentCol.implicitHeight + styles.spLg)

    // 动作带四格 = 从前那颗通栏按钮 + 方形拍照钮 + 抽屉底部通栏「标注这里」+ 收起.
    // 一格都没少; tone 只有一格是 prime (实心), 因为一屏只有一个主操作.
    readonly property var _bandActions: [
        {
            key: "toggle",
            icon: root.isRecording ? "stop" : "play",
            label: root.isRecording ? "停止记录" : "开始记录",
            tone: root.isRecording ? "danger" : "prime",
            enabled: !!mapService
        },
        { key: "photo", icon: "photo", label: "拍照" },
        { key: "annotate", icon: "pin_drop", label: "标注这里" },
        { key: "fold", icon: "expand_more", label: "收起" }
    ]

    function _onBandAction(key) {
        if (key === "toggle") root._toggleRecord()
        else if (key === "photo") root.captureRequested()
        else if (key === "annotate") root.annotateRequested()
        else if (key === "fold") root.foldRequested()
    }

    // 数据卡 2×2 里的一格: 等宽读数在上, 汉字标签在下.
    // 内联组件看不到外层 styles id (MapBottomSheet 的 SheetTab 注释里踩过), 自带一份.
    component ReadoutCell: ColumnLayout {
        id: cell
        Styles { id: cellStyles; visible: false }
        property string label: ""
        property string value: ""
        spacing: 1
        Text {
            // 只装 ASCII 读数 ("00:41:20" / "412" / "±3.2 m" / "1.8 km/h")
            text: cell.value
            font.family: cellStyles.monoFont
            font.pixelSize: cellStyles.fsMd
            font.bold: true
            color: CommonOptions.colorText
        }
        Text {
            text: cell.label
            font.pixelSize: cellStyles.fsXs
            color: CommonOptions.colorTextDim
        }
    }

    /**
     * 2026-10-29: 选档不只是改本页的数 —— 落进 QSettings (mapService.setFrequencySeconds),
     *   重启后 Component.onCompleted 那句 getDefaultFrequency() 读回来的就是它,
     *   不用每次进「记录」Tab 重选一遍. 录制中改档当前这条立刻生效
     *   (下面 sampleTimer 的 interval 就绑在这个属性上), 但 track 记录里的档位
     *   是 startTrack 那一刻存进去的, 回看历史轨迹仍显示当时那一档.
     */
    function _pickFreq(sec) {
        root.selectedFreq = sec
        if (mapService) mapService.setFrequencySeconds(sec)
    }

    Component.onCompleted: {
        if (mapService) {
            freqOptions = mapService.getFrequencyOptions()
            selectedFreq = mapService.getDefaultFrequency()
        }
        isRecording = false
        _resetStats()
    }

    // 2026-09-20: track 新增点时刷新统计. MapService 的 trackPointAdded
    //   带 trackId 参数, 用 Connections + JS 函数过滤只处理当前录制中的轨迹
    Connections {
        target: mapService
        function onTrackPointAdded(trackId, lat, lon) {
            if (trackId === root.currentTrackId) {
                root._refreshStats()
            }
        }
    }

    // 录制中每秒刷一次, 不然时长数字不动
    Timer {
        id: tickTimer
        interval: 1000
        repeat: true
        running: root.isRecording
        onTriggered: root._refreshStats()
    }

    // 2026-10-26「轨迹/标注点精度到 1 m」: **这一条才是"记录"Tab 的真采样器**.
    //   原来这个 Tab 只有 startTrack/stopTrack, 全程一次 addTrackPoint 都没调过 ——
    //   录完的轨迹是 0 个点, 屏幕上"移动中即在下一个采样点记录"描述的是一个不存在的
    //   行为, 「轨迹」Tab 叠不出线 (A22) 与"精度无从谈起"都是这一个坑.
    //   triggeredOnStart: 点下开始记录先落一个起点, 不必等一个采样周期.
    Timer {
        id: sampleTimer
        interval: Math.max(1000, root.selectedFreq * 1000)
        repeat: true
        running: root.isRecording && root.currentTrackId.length > 0
        triggeredOnStart: true
        onTriggered: root._sampleNow()
    }

    function _resetStats() {
        recordedPoints = 0
        recordedDistanceKm = 0
        recordedDurationSec = 0
        _lastLat = Number.NaN
        _lastLon = Number.NaN
        _lastAccM = Number.NaN
        _lastSampleAt = ""
        _skippedNoFix = 0
        _skippedStill = 0
    }

    // 采一个点. 位置只从 emergencyService 读 (全站唯一来源, 见 MapPage #98 注释),
    // 精度/高程是它的 currentAccuracy/currentAltitude —— NaN 原样带进 C++, 那一键
    // 整条不写, 不拿 0 凑数.
    function _sampleNow() {
        if (!mapService || !currentTrackId) return
        var es = emergencyService
        if (!es || !es.hasLocation) {
            root._skippedNoFix++
            console.log("[RecordTab] 跳过采样: 没有定位读数 (累计 " + root._skippedNoFix + " 次)")
            return
        }
        var la = es.currentLatitude
        var lo = es.currentLongitude
        var acc = es.currentAccuracy
        var alt = es.currentAltitude

        // 静止抖动过滤: 与上一个已落点比, 距离小于 max(3 m, 那一点的 ±) 就不重复写.
        // 不拦这一手, 站着不动也会每周期攒一个点, 轨迹画成一团毛线、"距离"全是抖出来的。
        // 判据用的是**那一点的实测 ±**, 不是拍的阈值 —— 精度变差时过滤自动变松。
        if (isFinite(root._lastLat) && isFinite(root._lastLon)) {
            // 全站同一个距离口径 (CommonOptions.distanceMeters), 不在页面里再抄一份
            // haversine —— MapPage 里那两套公式各算各的正是"跳 200km"没人发现的原因.
            var d = CommonOptions.distanceMeters(root._lastLat, root._lastLon, la, lo)
            var minGap = Math.max(3.0, isFinite(root._lastAccM) ? root._lastAccM : 3.0)
            if (d < minGap) {
                root._skippedStill++
                return
            }
        }

        var r = mapService.addTrackPoint(currentTrackId, la, lo, alt, acc)
        if (r && r.ok) {
            root._lastLat = la
            root._lastLon = lo
            root._lastAccM = acc
            // 采样时刻 (本地, 与「轨迹」Tab 的 _startLabel 同口径, 不用 UTC)
            var ts = new Date()
            var p2 = function (n) { return n < 10 ? "0" + n : "" + n }
            root._lastSampleAt = p2(ts.getHours()) + ":" + p2(ts.getMinutes())
                                        + ":" + p2(ts.getSeconds())
            root._refreshStats()
            console.log("[RecordTab] 采样点 " + root.recordedPoints
                        + ": ±" + (isFinite(acc) ? acc.toFixed(1) : "未知")
                        + " m, 高程 " + (isFinite(alt) ? alt.toFixed(0) : "未知") + " m")
        } else {
            console.warn("[RecordTab] addTrackPoint 失败:",
                         r && r.error ? r.error.message : "unknown")
        }
    }

    function _refreshStats() {
        if (!mapService || !currentTrackId) return
        try {
            // 2026-09-20: getTrackStats 实际字段 - distanceM (米), durationS (秒),
            //   pointCount (不是 points). 距离这里转 km 显示.
            var stats = mapService.getTrackStats(currentTrackId)
            if (stats && stats.ok) {
                root.recordedPoints = stats.pointCount || 0
                root.recordedDistanceKm = (stats.distanceM || 0) / 1000.0
                root.recordedDurationSec = stats.durationS || 0
            }
        } catch (e) { /* ignore */ }
    }

    function _fmtDuration(sec) {
        sec = Math.max(0, Math.floor(sec))
        var h = Math.floor(sec / 3600)
        var m = Math.floor((sec % 3600) / 60)
        var s = sec % 60
        var pad = function(n) { return n < 10 ? "0" + n : "" + n }
        return h > 0 ? (h + ":" + pad(m) + ":" + pad(s)) : (pad(m) + ":" + pad(s))
    }

    function _toggleRecord() {
        if (!mapService) return
        if (root.isRecording) {
            if (root.currentTrackId) {
                mapService.stopTrack(root.currentTrackId)
            }
            root.currentTrackId = ""
            root.isRecording = false
            root._resetStats()
        } else {
            // 2026-09-21: Phase 5 - startTrack 返回 Result {ok, value=trackId, error}.
            // 2026-10-23 #109: 原来用 toISOString() —— 那是 UTC 且带 T+秒, 而 C++ 侧
            //   startTrack 存的 startTime 是 QDateTime::currentDateTime() 本地时间,
            //   这个名字会原样落进 track_<id>.json 并当「轨迹」Tab 的行标题: 同一行
            //   标题 01:31 / 副标题 09:31 差 8 小时自相矛盾. 改本地时间 MM-DD HH:MM,
            //   与 Tab 副标题 (_startLabel) 同口径.
            var now = new Date()
            var p2 = function(n) { return n < 10 ? "0" + n : "" + n }
            var r = mapService.startTrack(
                "轨迹 " + p2(now.getMonth() + 1) + "-" + p2(now.getDate())
                        + " " + p2(now.getHours()) + ":" + p2(now.getMinutes()),
                root.selectedFreq)
            if (r && r.ok) {
                root.currentTrackId = r.value
                root.isRecording = true
                root._refreshStats()
            } else {
                root.isRecording = false
                console.warn("[RecordTab] startTrack failed:", r ? r.error.message : "unknown")
            }
        }
    }

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.leftMargin: styles.pageMargin
        anchors.rightMargin: styles.pageMargin
        anchors.topMargin: styles.spXs
        // 底部不留边距: 动作带就是这一档的收边, 与两步路那条带贴屏幕底同形
        anchors.bottomMargin: 0
        spacing: styles.spSm

        // === 面板头 (2026-10-28 #156): 标题 + 状态读数 + ✕ 收起, 一行装完 ===
        SheetPanelHead {
            Layout.fillWidth: true
            iconName: "note_add"
            title: "记录"
            // 状态读数进 head.trailing: 录制中给 blaze, 不录时是次要色
            trailing: root.isRecording
                    ? "正在记录 · 每 " + root.selectedFreq + " 秒"
                    : "未开始记录"
            trailingTone: root.isRecording ? "warn" : ""
            onFoldRequested: root.foldRequested()
        }

        // === 数据卡: 只有真在录时才占位 ===
        // 2026-10-23 真机 (A8): 原来未开始时写死 00:00 / 0 m / 0 点 —— 00:00 看着像"刚停",
        //   0 m 看着像"精度坏了". 未开始整块不出现 (见 [[no-fake-readout-rule]]).
        Card {
            visible: root.isRecording
            Layout.fillWidth: true
            spacing: styles.cardGap

            // 数据来源 + 最后一个点的实测精度与采样时刻
            RowLayout {
                Layout.fillWidth: true
                spacing: styles.spSm

                // 录制状态点 - 脉冲动画 (blaze: REC 要跳出来, 但不借 SOS 的危险红)
                Rectangle {
                    id: statusDot
                    Layout.alignment: Qt.AlignVCenter
                    // RowLayout 的子项不认 width/height ([Quick.layout-positioning])
                    Layout.preferredWidth: styles.icSm
                    Layout.preferredHeight: styles.icSm
                    radius: styles.rPill
                    color: CommonOptions.colorBlaze
                    SequentialAnimation on opacity {
                        running: root.isRecording
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.35; duration: 700 }
                        NumberAnimation { from: 0.35; to: 1.0; duration: 700 }
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: "本机 GPS"
                    color: CommonOptions.colorTextMuted
                    font.pixelSize: styles.fsSm
                }
                // 弹簧 (2026-10-28 用户定的弹窗按钮口径同理: 左侧撑开, 读数按内容宽靠右)
                Item { Layout.fillWidth: true }
                Text {
                    visible: root._lastSampleAt.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    text: "最后一点 "
                    color: CommonOptions.colorTextDim
                    font.pixelSize: styles.fsXs
                }
                Text {
                    // 只装 ASCII ("±3.2 m · 14:22:07") → 允许进 monoFont
                    visible: root._lastSampleAt.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    text: (isFinite(root._lastAccM) ? "±" + root._lastAccM.toFixed(1) + " m · " : "")
                          + root._lastSampleAt
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorTextMuted
                }
            }

            // === 主读数 + 2×2 ===
            RowLayout {
                Layout.fillWidth: true
                spacing: styles.spMd

                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0
                    RowLayout {
                        spacing: styles.spXs
                        Text {
                            Layout.alignment: Qt.AlignBottom
                            text: root.recordedDistanceKm.toFixed(2)
                            font.family: styles.monoFont
                            font.pixelSize: styles.fs2xl
                            font.bold: true
                            color: CommonOptions.colorBlaze
                        }
                        // 单位是汉字, 不能并进上面那颗等宽读数 (见 [[qml-monofont-no-cjk]])
                        Text {
                            Layout.alignment: Qt.AlignBottom
                            text: "公里"
                            font.pixelSize: styles.fsSm
                            color: CommonOptions.colorTextMuted
                        }
                    }
                    Text {
                        // 点数与起点同源一行: 一个点都还没有时整行不出现, 不写 "0 点"
                        visible: root.recordedPoints > 0
                        text: root.recordedPoints + " 点"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextDim
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: styles.spSm
                    columnSpacing: styles.spMd

                    ReadoutCell {
                        label: "时长"
                        value: root._fmtDuration(root.recordedDurationSec)
                    }
                    ReadoutCell {
                        label: "点数"
                        value: String(root.recordedPoints)
                    }
                    // 均速 = 距离 ÷ 时长. 本轮唯一新增读数, 纯算术、不新增采集;
                    // 时长还没走满 1 分钟时算出来的数没意义 → 整格不出现.
                    ReadoutCell {
                        visible: root.recordedDurationSec >= 60 && root.recordedDistanceKm > 0
                        label: "均速"
                        value: (root.recordedDistanceKm / (root.recordedDurationSec / 3600.0))
                               .toFixed(1) + " km/h"
                    }
                    // 精度: 这一帧没有精度读数时整格不出现 (不写 "±0 m").
                    // 四格都是 1 列宽 —— 上一版让精度独占 columnSpan: 2, 于是它下面
                    // 那一行的均速右侧永远空着一格, 卡片右下角出个洞.
                    ReadoutCell {
                        visible: isFinite(root._lastAccM)
                        label: "最后一点精度"
                        value: "±" + root._lastAccM.toFixed(1) + " m"
                    }
                }
            }
        }

        // === 频率 chips: 标签由服务给 ("5 秒/10 秒/15 秒/30 秒"), 四枚等宽一排 ===
        RowLayout {
            Layout.fillWidth: true
            spacing: styles.spXs

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "采样频率"
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsSm
            }
            Repeater {
                model: root.freqOptions
                delegate: Chip {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: styles.chipH
                    text: modelData.label
                    checked: root.selectedFreq === modelData.seconds
                    accent: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: root._pickFreq(modelData.seconds)
                }
            }
        }

        // === 底部提示 (贴着动作带上方, 说清"为什么不落点") ===
        Text {
            visible: root.isRecording
            text: root.recordedPoints === 0 && root._skippedNoFix > 0
                    ? "还没定上位，已跳过 " + root._skippedNoFix + " 次采样"
                    : "换频率立即生效；站着不动（位移小于该点 ±精度）不重复落点"
            color: CommonOptions.colorTextDim
            font.pixelSize: styles.fsXs
            Layout.alignment: Qt.AlignHCenter
        }

        // === 动作带 (2026-10-28 #156): 原来这颗通栏 PrimaryButton + 右侧方形拍照钮 ===
        //   换成底排四格. 通栏按钮的问题不是"不好看", 是它把一次动作和整块内容抢同一
        //   列宽 (pass9 ② 查找那颗的图标压文案就是同一个形状). 动作带自己占一行 60,
        //   每格一个动作, 抽屉底部的 1px 描边就是它的上沿.
        SheetActionBand {
            Layout.fillWidth: true
            actions: root._bandActions
            onTriggered: root._onBandAction(key)
        }
    }
}
