/**
 * @file MapBottomSheet.qml
 * @brief 地图底部 BottomSheet (Drawer 模拟, 4 Tab 容器)
 *
 * Qt 6.7 Material 无原生 BottomSheet, 用 edge: Qt.BottomEdge 的 Drawer 模拟.
 * 内部 TabBar + StackLayout 切换 4 个 Tab.
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0
// 2026-09-20: 删 tabs/qmldir, RecordTab/NavigationTab/NearbyTab/SearchTab 全在 QML_FILES,
// qt_add_qml_module 自动注册到 OutdoorSurvival 1.0, 上面的 import 已能解析.

Drawer {
    id: root
    edge: Qt.BottomEdge
    width: parent ? parent.width : 360
    height: Math.min(parent ? parent.height * 0.6 : 480, 480)
    dragMargin: 80   // 顶部 80px 区域可下拉
    interactive: true
    modal: false
    dim: false
    position: 0.0    // 默认关闭

    property int currentTab: 0

    // 4 个 Tab 透传到外层
    signal captureRequested()
    signal routeSelected(string routeId, var route)
    signal trackSelected(string trackId, var track)
    signal trackAnalyzeRequested(string trackId)  // 2026-09-14: P1
    signal trackImportRequested()                  // 2026-10-09: 导入 GPX/KML/CSV
    signal nearbyRefreshRequested()

    onCurrentTabChanged: stack.currentIndex = currentTab

    function openTab(index) {
        currentTab = index
        if (!root.opened) root.open()
    }

    contentItem: ColumnLayout {
        spacing: 0

        // 拖把 + Tab 标题
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            color: "#1A237E"

            ColumnLayout {
                anchors.fill: parent
                spacing: 4

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    width: 36
                    height: 4
                    radius: 2
                    color: "#90CAF9"
                }

                TabBar {
                    id: tabBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    currentIndex: root.currentTab
                    onCurrentIndexChanged: root.currentTab = currentIndex

                    TabButton { text: "\ue0c8 记录"; font.family: "Material Icons" }  // place
                    TabButton { text: "\ue1b7 导航"; font.family: "Material Icons" }  // exploration
                    TabButton { text: "\ue55b 周边"; font.family: "Material Icons" }  // map
                    TabButton { text: "\ue8b6 查找"; font.family: "Material Icons" }  // search
                }
            }
        }

        // 4 个 Tab 内容 (StackLayout 切换)
        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTab

            RecordTab {
                id: recordTab
                onCaptureRequested: root.captureRequested()
            }
            NavigationTab {
                id: navigationTab
                onTrackSelected: function(trackId, track) {
                    root.trackSelected(trackId, track)
                }
                // 2026-09-14: P1 上抛分析请求
                onTrackAnalyzeRequested: function(trackId) {
                    root.trackAnalyzeRequested(trackId)
                }
                // 2026-10-09: 上抛导入请求
                onTrackImportRequested: root.trackImportRequested()
            }
            NearbyTab {
                id: nearbyTab
                // 2026-09-19: 把外层 mapPage 的实时坐标喂进 NearbyTab, GPS 修了之后
                //   这里能跟着变. 旧版没绑, 用户每次都要手动按"刷新"才有数据
                currentLat: (typeof mapPage !== "undefined" && mapPage) ? mapPage.currentLat : 0
                currentLon: (typeof mapPage !== "undefined" && mapPage) ? mapPage.currentLon : 0
                onRouteSelected: function(routeId, route) {
                    root.routeSelected(routeId, route)
                }
            }
            SearchTab {
                id: searchTab
                onRouteSelected: function(routeId, route) {
                    root.routeSelected(routeId, route)
                }
            }
        }
    }
}
