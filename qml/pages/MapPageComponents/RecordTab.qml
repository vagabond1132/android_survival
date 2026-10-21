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

    // 拍照请求 (外层 MapPage 接 signal 调 androidPlatform.takePhoto)
    signal captureRequested()

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

    function _resetStats() {
        recordedPoints = 0
        recordedDistanceKm = 0
        recordedDurationSec = 0
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
            var r = mapService.startTrack(
                "轨迹 " + new Date().toISOString().slice(0, 19),
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
        anchors.fill: parent
        anchors.margins: styles.spMd
        spacing: styles.spMd

        // === 状态 + 实时统计 ===
        Card {
            Layout.fillWidth: true
            spacing: styles.spSm

            RowLayout {
                Layout.fillWidth: true
                spacing: styles.spSm

                // 录制状态点 - 脉冲动画
                Rectangle {
                    id: statusDot
                    Layout.alignment: Qt.AlignVCenter
                    // 2026-10-20: RowLayout 的子项不认 width/height ([Quick.layout-positioning])
                    Layout.preferredWidth: styles.icSm
                    Layout.preferredHeight: styles.icSm
                    radius: styles.rPill
                    // 2026-10-20: 原来是 colorRedBright —— 和 SOS 的危险红同一个值,
                    //   而"正在记录"不是危险. 换 blaze 橙 (REC 需要跳出来, 但不借危险色).
                    color: root.isRecording ? CommonOptions.colorBlaze
                                             : CommonOptions.colorTextDisabled
                    SequentialAnimation on opacity {
                        running: root.isRecording
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.35; duration: 700 }
                        NumberAnimation { from: 0.35; to: 1.0; duration: 700 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: styles.spXs
                    Text {
                        Layout.fillWidth: true
                        text: root.isRecording ? "正在记录轨迹" : "未开始记录"
                        // 卡片底是 colorSurface: 白字 token 只允许出现在饱和填充上
                        color: root.isRecording ? CommonOptions.colorBlaze
                                                : CommonOptions.colorText
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    // 数字交给下面 StatTile 三格, 这一行只说一句人话
                    Text {
                        Layout.fillWidth: true
                        text: root.isRecording
                              ? "移动中即在下一个采样点记录, 点下方停止保存"
                              : "选择频率后点击下方开始记录"
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: styles.spSm
                StatTile {
                    Layout.fillWidth: true
                    label: "时长"
                    value: root._fmtDuration(root.recordedDurationSec)
                    iconName: "clock"
                }
                StatTile {
                    Layout.fillWidth: true
                    label: "距离"
                    value: CommonOptions.formatDistance(root.recordedDistanceKm)
                    iconName: "route"
                }
                StatTile {
                    Layout.fillWidth: true
                    label: "点数"
                    value: root.recordedPoints + " 点"
                    iconName: "place"
                }
            }
        }

        // === 频率选择 ===
        SectionTitle {
            Layout.fillWidth: true
            icon: "clock"
            text: "采样频率"
            titleColor: CommonOptions.colorTextMuted
            iconColor: CommonOptions.colorAccentSoft
            pixelSize: styles.fsSm
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: styles.spXs
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
                    onClicked: root.selectedFreq = modelData.seconds
                }
            }
        }

        // === 主按钮行 ===
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: styles.spXs
            spacing: styles.spSm

            // 主按钮 - 开始/停止 (图标用 play / stop 语义名, 不再拿几何符号凑)
            PrimaryButton {
                Layout.fillWidth: true
                text: root.isRecording ? "停止记录" : "开始记录"
                iconName: root.isRecording ? "stop" : "play"
                tone: root.isRecording ? CommonOptions.colorDanger
                                       : CommonOptions.colorSuccess
                textSize: styles.fsLg
                enabled: !!mapService
                onClicked: root._toggleRecord()
            }

            // 拍照按钮 - 方形辅助按钮
            Rectangle {
                Layout.preferredWidth: styles.btnH
                Layout.preferredHeight: styles.btnH
                radius: styles.rMd
                color: CommonOptions.colorAccent
                IconLabel {
                    anchors.centerIn: parent
                    name: "photo"
                    size: styles.icLg
                    tintColor: CommonOptions.colorTextOnAccent
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.captureRequested()
                }
            }
        }

        // === 底部提示 ===
        Text {
            visible: root.isRecording
            text: "提示: 记录中改变频率将在下一个采样点生效"
            color: CommonOptions.colorTextDim
            font.pixelSize: styles.fsXs
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
