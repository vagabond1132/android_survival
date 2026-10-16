/**
 * @file SurvivalList.qml
 * @brief 避险列表
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: root
    property int topic: 0  // SurvivalService.Topic

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4
        clip: true

        model: ListModel { id: itemModel }

        Component.onCompleted: refresh()

        function refresh() {
            itemModel.clear()
            var items = survivalService.getByTopic(root.topic)
            for (var i = 0; i < items.length; i++) {
                itemModel.append({
                    "id": items[i].id,
                    "name": items[i].name,
                    "difficulty": items[i].difficulty,
                    "estimatedTimeMin": items[i].estimatedTimeMin
                })
            }
        }

        delegate: ItemDelegate {
            width: ListView.view.width
            height: 64

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                // 难度标识
                Rectangle {
                    width: 8
                    Layout.fillHeight: true
                    radius: 4
                    color: {
                        if (model.difficulty >= 4) return "#D32F2F"
                        if (model.difficulty >= 3) return "#F57C00"
                        if (model.difficulty >= 2) return "#FBC02D"
                        return "#388E3C"
                    }
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: model.name
                        color: "white"
                        font.pixelSize: 16
                    }
                    Text {
                        text: "难度: " + "★".repeat(model.difficulty) +
                              "☆".repeat(5 - model.difficulty) +
                              "  ·  预计: " + model.estimatedTimeMin + " 分钟"
                        color: "#90A4AE"
                        font.pixelSize: 12
                    }
                }

                Text {
                    text: "›"
                    color: "#607D8B"
                    font.pixelSize: 24
                }
            }

            onClicked: {
                // 2026-09-11: 同 Main.qml 修复, 用 Qt.resolvedUrl 显式 qrc 路径
                stackView.push(Qt.resolvedUrl("qrc:/qt/qml/OutdoorSurvival/qml/pages/SurvivalDetailPage.qml"), {itemId: model.id})
            }
        }
    }
}
