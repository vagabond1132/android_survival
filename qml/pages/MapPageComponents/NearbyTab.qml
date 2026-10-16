/**
 * @file NearbyTab.qml
 * @brief 周边 Tab: 路线按距离 + 类型/难度/时长 筛选
 *
 * 数据源: RouteService.getNearby(lat, lon, radiusKm) 已有
 *         RouteService.getFiltered(province, minDifficulty, maxDifficulty, month) 已有
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: root

    property real currentLat: 0
    property real currentLon: 0
    property int radiusKm: 50
    property int minDifficulty: 1
    property int maxDifficulty: 5
    property int maxDays: 99
    property var results: []

    signal routeSelected(string routeId, var route)

    function refresh(lat, lon) {
        if (lat !== undefined) currentLat = lat
        if (lon !== undefined) currentLon = lon
        if (currentLat === 0 && currentLon === 0) return

        // getNearby 返回 {id, name, lat, lon, ...} 列表
        results = routeService.getNearby(currentLat, currentLon, radiusKm)
    }

    // 2026-09-19: 拉数据 - 之前必须用户手动按"刷新"才能拿到数据, 首次进入 tab
    //   (MapPage.Component.onCompleted → openTab(2)) 显示 "(无数据)", 用户
    //   看不到定位点的周边路线. 这里监听坐标变化自动刷新.
    onCurrentLatChanged: if (currentLat !== 0 || currentLon !== 0) refresh()
    onCurrentLonChanged: if (currentLat !== 0 || currentLon !== 0) refresh()
    Component.onCompleted: refresh()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Text {
            text: "周边路线 (半径 " + root.radiusKm + " km, 共 " + root.results.length + " 条)"
            color: "white"
            font.pixelSize: 16
            font.bold: true
        }

        // 2026-09-20: 改用 FilterRow 组件, 跟 RouteListPage / TravelListPage 风格统一.
        //   难度用 chip, 半径用 stepper
        FilterRow {
            Layout.fillWidth: true
            label: "半径"
            labelWidth: 36
            stepperValue: root.radiusKm + " km"
            stepperMinusEnabled: root.radiusKm > 10
            stepperPlusEnabled: root.radiusKm < 500
            onStepperMinus: root.radiusKm = Math.max(10, root.radiusKm - 10)
            onStepperPlus: root.radiusKm = Math.min(500, root.radiusKm + 10)
        }
        FilterRow {
            Layout.fillWidth: true
            label: "难度"
            labelWidth: 36
            chipCount: 5
            chipSelected: root.minDifficulty
            onChipClicked: (n) => root.minDifficulty = n
        }

        // 刷新按钮居中, 不拉满
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Item { Layout.fillWidth: true }
            Button {
                text: "\ue028 刷新"
                font.family: "Material Icons"
                Layout.preferredWidth: 120
                Material.background: CommonOptions.colorAccent
                Material.foreground: "white"
                onClicked: root.refresh()
            }
            Item { Layout.fillWidth: true }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            clip: true
            model: root.results

            delegate: Rectangle {
                width: list.width
                height: 56
                // 2026-09-15: 选中的路线高亮 — 从 mapPage.selectedRouteIds 反查
                color: mapPage.selectedRouteIds.indexOf(modelData.id) >= 0 ? "#37474F" : (mArea.containsMouse ? "#37474F" : "#263238")
                border.color: mapPage.selectedRouteIds.indexOf(modelData.id) >= 0 ? "#1976D2" : "transparent"
                border.width: 2
                radius: 4

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    Text {
                        text: modelData.name || "(未命名)"
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text {
                        text: (modelData.province || "") + " · " +
                              (modelData.difficulty || 1) + "★ · " +
                              (modelData.distance || modelData.distanceKm || 0).toFixed(1) + " km"
                        color: "#B0BEC5"
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: mArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.routeSelected(modelData.id, modelData)
                }
            }
        }
    }
}
