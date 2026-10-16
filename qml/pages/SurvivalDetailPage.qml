/**
 * @file SurvivalDetailPage.qml
 * @brief 避险详情
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: detailPage
    property string itemId: ""
    property var entity: ({})

    title: entity.name || "详情"

    // 2026-09-17: 改用 onItemIdChanged (Qt 6.x StackView.push 先 create 后 set props)
    onItemIdChanged: {
        if (itemId) entity = survivalService.getById(itemId)
    }
    Component.onCompleted: {
        if (itemId) entity = survivalService.getById(itemId)
    }

    Flickable {
        anchors.fill: parent
        contentWidth: parent.width
        contentHeight: contentColumn.height
        clip: true

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: 0

            // 顶部信息
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                color: {
                    if (entity.difficulty >= 4) return "#D32F2F"
                    if (entity.difficulty >= 3) return "#F57C00"
                    if (entity.difficulty >= 2) return "#FBC02D"
                    return "#388E3C"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 4

                    Text {
                        text: entity.name || ""
                        color: "white"
                        font.pixelSize: 22
                        font.bold: true
                    }
                    Text {
                        text: "难度: " + "★".repeat(entity.difficulty || 0) +
                              "  ·  预计: " + (entity.estimatedTimeMin || 0) + " 分钟"
                        color: "white"
                        font.pixelSize: 14
                    }
                }
            }

            // 描述
            Section {
                titleIcon: "\ue873"  // description
                title: "概述"
                items: entity.description ? [entity.description] : []
                asInline: true
            }

            // 所需材料
            Section {
                titleIcon: "\ue1bd"  // work (材料)
                title: "所需材料"
                items: entity.materials || []
                textColor: CommonOptions.colorWarn
                prefix: "• "
            }

            // 详细步骤
            Section {
                titleIcon: "\ue153"  // fact_check (步骤)
                title: "操作步骤"
                items: entity.steps || []
            }

            // 警告
            Section {
                titleIcon: "\ue002"  // warning
                title: "安全警告"
                items: entity.warnings || []
                textColor: CommonOptions.colorDanger
            }

            // 小贴士
            Section {
                titleIcon: "\ue0e0"  // lightbulb (tips)
                title: "小贴士"
                items: entity.tips || []
                textColor: CommonOptions.colorSuccess
            }

            // 来源
            Item {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.preferredHeight: 30
                Text {
                    text: "来源: " + (entity.source || "未知")
                    color: "#78909C"
                    font.pixelSize: 12
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 24 }
        }
    }
}
