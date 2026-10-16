/**
 * @file SearchTab.qml
 * @brief 查找 Tab: 按城市/名称 + 类型/难度/时长 筛选 (不限位置)
 *
 * 数据源: RouteService.search(keyword) + RouteService.getByProvince + getByDifficulty
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: root

    property string keyword: ""
    property string province: ""
    property int minDifficulty: 1
    property int maxDifficulty: 5
    property int maxDays: 99
    property var results: []
    property var provinces: []

    signal routeSelected(string routeId, var route)

    Component.onCompleted: {
        provinces = routeService.getAvailableProvinces()
    }

    function doSearch() {
        if (keyword && keyword.length > 0) {
            results = routeService.search(keyword)
        } else if (province && province.length > 0) {
            results = routeService.getByProvinceAndDifficulty(
                province, minDifficulty, maxDifficulty)
        } else {
            results = routeService.getByDifficulty(minDifficulty, maxDifficulty)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Text {
            text: "查找路线"
            color: "white"
            font.pixelSize: 16
            font.bold: true
        }

        TextField {
            id: kwField
            Layout.fillWidth: true
            placeholderText: "城市/路线名/关键词"
            onAccepted: { root.keyword = text; root.doSearch() }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text { text: "省/市"; color: "#B0BEC5"; font.pixelSize: 12 }
            ComboBox {
                id: provCombo
                Layout.fillWidth: true
                // 2026-09-14 修: routeService.getAvailableProvinces() 已在
                // C++ 端 prepend "全部", 不要重复加 "(全部)"
                model: root.provinces
                onActivated: {
                    root.province = (currentIndex === 0) ? "" : (provCombo.model[currentIndex])
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text { text: "难度"; color: "#B0BEC5"; font.pixelSize: 12 }
            SpinBox {
                from: 1; to: 5; value: root.minDifficulty
                Layout.preferredWidth: 80
                onValueChanged: root.minDifficulty = value
            }
            Text { text: "—"; color: "#B0BEC5" }
            SpinBox {
                from: 1; to: 5; value: root.maxDifficulty
                Layout.preferredWidth: 80
                onValueChanged: root.maxDifficulty = value
            }
            Item { Layout.fillWidth: true }
        }

        Button {
            text: "搜索"
            Layout.fillWidth: true
            onClicked: {
                root.keyword = kwField.text
                root.doSearch()
            }
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
                // 2026-09-15: 选中路线高亮 — 从 mapPage.selectedRouteIds 反查
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
                              (modelData.city || "") + " · " +
                              (modelData.difficulty || 1) + "★"
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
