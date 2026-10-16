/**
 * @file NavigationTab.qml
 * @brief 导航 Tab: 历史轨迹列表, 点击加载到地图 / 长按分析
 *
 * 2026-09-14: P1 增加 "分析" 按钮, 点击 push 到 TrackDetailPage 看详细统计/曲线
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: root

    property var tracks: []

    signal trackSelected(string trackId, var track)
    signal trackAnalyzeRequested(string trackId)  // 2026-09-14: P1 新增
    signal trackImportRequested()                 // 2026-10-09: 导入 GPX/KML/CSV 入口

    Component.onCompleted: refresh()

    // 2026-10-09: 监听全局 dataChanged (导入/删除轨迹后 MapService 已 emit) → 自查刷新.
    //   修复旧写法「导入后调 mapPage.refreshData()」未定义函数 TypeError 的问题.
    Connections {
        target: mapService
        function onDataChanged() { root.refresh() }
    }

    function refresh() {
        tracks = mapService.getAllTracks()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "历史轨迹 (" + root.tracks.length + ")"
                color: "white"
                font.pixelSize: 16
                font.bold: true
                Layout.fillWidth: true
            }
            // 2026-10-09: 导入入口 (此前 importDialog 无任何 .open() 触发点 → 死功能).
            //   上抛 → MapBottomSheet 透传 → MapPage onTrackImportRequested: importDialog.open()
            Button {
                text: "\ue2c6 导入"  // Material Icons: file_download
                font.family: "Material Icons"
                Material.background: CommonOptions.colorAccent
                Material.foreground: "white"
                onClicked: root.trackImportRequested()
            }
            Button {
                text: "刷新"
                onClicked: root.refresh()
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            clip: true
            model: root.tracks

            delegate: Rectangle {
                width: ListView.view ? ListView.view.width : 0
                height: 64
                // 2026-09-15: 选中的轨迹高亮 — 从 mapPage.selectedTrackIds 反查
                color: mapPage.selectedTrackIds.indexOf(modelData.id) >= 0 ? "#37474F" : "#263238"
                border.color: mapPage.selectedTrackIds.indexOf(modelData.id) >= 0 ? "#1976D2" : "transparent"
                border.width: 2
                radius: 4

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: modelData.name || "(未命名轨迹)"
                            color: "white"
                            font.pixelSize: 14
                            font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: "起点: " + new Date(modelData.startTime).toLocaleString() +
                                  "  ·  距离: " + mapService.formatDistance(modelData.totalDistanceM)
                            color: "#B0BEC5"
                            font.pixelSize: 11
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    // 2026-09-14: P1 分析按钮 - 点击 push 到 TrackDetailPage
                    Button {
                        text: "\ue01d"  // Material Icons: equalizer
                        font.family: "Material Icons"
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Material.background: CommonOptions.colorAccent
                        Material.foreground: "white"
                        onClicked: {
                            root.trackAnalyzeRequested(modelData.id)
                        }
                    }
                }

                MouseArea {
                    id: mArea
                    anchors.fill: parent
                    hoverEnabled: true
                    // 2026-09-15: 移除 selectedTrackId 内部状态, MapPage 端 toggle
                    onClicked: {
                        root.trackSelected(modelData.id, modelData)
                    }
                }
            }
        }
    }
}

