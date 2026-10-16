/**
 * @file RecordTab.qml
 * @brief 记录 Tab: track 启动/暂停/停止 + 拍照
 *
 * 2026-09-20 改版: 紧凑 GPS app 风格
 *   - 顶部状态行: 脉冲红点 + 状态文字 + 时长
 *   - 中部统计: 距离 + 点数 + 当前频率 (单行, 不再 ComboBox 单独一行)
 *   - 频率 chip 横排 (替代下拉框, 一眼看到所有选项)
 *   - 主按钮 (开始/停止) 占主, 拍照为右侧方形辅助按钮
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: root

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
        freqOptions = mapService.getFrequencyOptions()
        selectedFreq = mapService.getDefaultFrequency()
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
        if (!currentTrackId) return
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
        anchors.margins: 12
        spacing: 10

        // === 状态行 ===
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // 录制状态点 - 脉冲动画
            Rectangle {
                id: statusDot
                width: 14; height: 14; radius: 7
                color: root.isRecording ? "#F44336" : "#607D8B"
                SequentialAnimation on opacity {
                    running: root.isRecording
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.35; duration: 700 }
                    NumberAnimation { from: 0.35; to: 1.0; duration: 700 }
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: root.isRecording ? "正在记录轨迹" : "未开始记录"
                    color: root.isRecording ? "#F44336" : "white"
                    font.pixelSize: 16
                    font.bold: true
                }
                // 2026-09-20: 录制中显示时长, 否则显示当前频率
                Text {
                    text: root.isRecording
                          ? root._fmtDuration(root.recordedDurationSec) + " · " +
                            root.recordedDistanceKm.toFixed(2) + " km · " +
                            root.recordedPoints + " 点"
                          : "选择频率后点击下方开始记录"
                    color: "#90A4AE"
                    font.pixelSize: 11
                }
            }
        }

        // === 频率选择 ===
        Text {
            text: "采样频率"
            color: "#90A4AE"
            font.pixelSize: 11
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.freqOptions
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 6
                    color: root.selectedFreq === modelData.seconds
                           ? "#1976D2" : "#263238"
                    border.color: root.selectedFreq === modelData.seconds
                                  ? "#1976D2" : "#37474F"
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: root.selectedFreq === modelData.seconds
                               ? "white" : "#B0BEC5"
                        font.pixelSize: 12
                        font.bold: root.selectedFreq === modelData.seconds
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedFreq = modelData.seconds
                    }
                }
            }
        }

        // === 主按钮行 ===
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            // 主按钮 - 开始/停止 (大)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                radius: 8
                color: root.isRecording ? "#D32F2F" : "#388E3C"

                // 按下反馈
                SequentialAnimation on scale {
                    running: false
                    NumberAnimation { from: 1.0; to: 0.97; duration: 80 }
                    NumberAnimation { from: 0.97; to: 1.0; duration: 120 }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: root.isRecording ? "■" : "●"
                        color: "white"
                        font.pixelSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.isRecording ? "停止记录" : "开始记录"
                        color: "white"
                        font.pixelSize: 16
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: parent.scale = 0.97
                    onReleased: parent.scale = 1.0
                    onClicked: root._toggleRecord()
                }
            }

            // 拍照按钮 - 方形辅助按钮
            Rectangle {
                Layout.preferredWidth: 56
                Layout.preferredHeight: 50
                radius: 8
                color: "#1976D2"
                Text {
                    anchors.centerIn: parent
                    text: "\ue412"  // Material Icons: photo_camera
                    font.family: "Material Icons"
                    color: "white"
                    font.pixelSize: 22
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
            color: "#607D8B"
            font.pixelSize: 10
            Layout.alignment: Qt.AlignHCenter
        }
    }
}