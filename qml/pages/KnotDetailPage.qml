/**
 * @file KnotDetailPage.qml
 * @brief 绳结详情
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: detailPage
    property string knotId: ""
    property var entity: ({})

    title: entity.nameCn || "绳结详情"

    // 2026-09-20: 修 Bug 15 (与 Travel/RouteDetailPage 一致). 之前 Component.onCompleted
    //   + onKnotIdChanged 双触发, 但 onCompleted 时 knotId 还是空, 实际只跑一次
    //   (onCompleted 的 if(knotId) 兜底) + 一次 (onKnotIdChanged 有效 id). 删掉 onCompleted
    //   只留 onKnotIdChanged 单一触发点, 避免 visit count 跳 2 等副作用.
    onKnotIdChanged: {
        if (knotId) entity = knotService.getById(knotId)
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
                Layout.preferredHeight: 120
                color: {
                    if (entity.difficulty >= 3) return "#D32F2F"
                    if (entity.difficulty >= 2) return "#F57C00"
                    return "#388E3C"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 4

                    Text {
                        text: entity.nameCn || ""
                        color: "white"
                        font.pixelSize: 26
                        font.bold: true
                    }
                    Text {
                        text: entity.nameEn || ""
                        color: "white"
                        font.pixelSize: 14
                        font.italic: true
                    }
                    Text {
                        text: "分类: " + (entity.category || "") +
                              "  ·  难度: " + "★".repeat(entity.difficulty || 0)
                        color: "white"
                        font.pixelSize: 12
                    }
                }
            }

            // 用途
            Section {
                titleIcon: "\ue1db"  // gps_fixed (target)
                title: "用途"
                items: entity.useCases || []
                textColor: CommonOptions.colorWarn
                prefix: "• "
            }

            // 描述
            Section {
                titleIcon: "\ue873"  // description
                title: "描述"
                items: entity.description ? [entity.description] : []
                asInline: true
            }

            // 步骤
            Section {
                titleIcon: "\ue153"  // fact_check
                title: "打结步骤"
                items: entity.steps || []
            }

            // 常见错误
            Section {
                titleIcon: "\ue5cd"  // close
                title: "常见错误"
                items: entity.commonMistakes || []
                textColor: CommonOptions.colorDanger
            }

            // 练习提示
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.preferredHeight: 80
                color: "#1B5E20"
                radius: 4

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 4
                    Text {
                        text: "\ue0e0 练习提示"  // Material Icons: lightbulb
                        font.family: "Material Icons"
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                    }
                    Text {
                        text: entity.practiceTip || "多练习，形成肌肉记忆"
                        color: "white"
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }
            }

            // 标记已学会
            Button {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.preferredHeight: 56
                text: entity.learned ? "\ue5ca 已学会" : "\ue1db 标记为已学会"  // check / gps_fixed
                font.family: "Material Icons"
                Material.background: entity.learned ? "#388E3C" : "#1976D2"
                font.pixelSize: 16
                onClicked: {
                    if (knotService.markLearned(detailPage.knotId)) {
                        entity = knotService.getById(detailPage.knotId)
                    }
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 24 }
        }
    }
}
