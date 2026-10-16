/**
 * @file FirstAidDetailPage.qml
 * @brief 急救详情 (2026-09-14 UI 改版)
 *
 * 改进: token 化 + 卡片化 + 紧急度色 hero
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: detailPage
    property string entryId: ""
    property var entity: ({})

    title: entity.title || "急救详情"

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    // 2026-09-17: 改用 onEntryIdChanged (Qt 6.x StackView.push 先 create 后 set props)
    onEntryIdChanged: {
        if (entryId) entity = firstAidService.getById(entryId)
    }
    Component.onCompleted: {
        if (entryId) {
            entity = firstAidService.getById(entryId)
        }
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

            // === 紧急度 hero ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 96
                color: {
                    if (entity.urgency >= 5) return "#B71C1C"
                    if (entity.urgency >= 4) return CommonOptions.colorDanger
                    if (entity.urgency >= 3) return CommonOptions.colorWarn
                    return CommonOptions.colorSuccess
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spLg
                    spacing: styles.spMd

                    Text {
                        text: entity.urgency >= 4 ? "\ue002" : "\ue88e"  // warning / info
                        font.family: "Material Icons"
                        font.pixelSize: 32
                        color: "white"
                    }
                    Column {
                        Layout.fillWidth: true
                        Text {
                            text: entity.title || ""
                            color: "white"
                            font.pixelSize: styles.fs2xl
                            font.bold: true
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }
                        Text {
                            text: "紧急度: " + (entity.urgencyName || "")
                            color: "white"
                            opacity: 0.9
                            font.pixelSize: styles.fsSm
                        }
                    }
                    Button {
                        text: "\ue0cd 120"  // Material Icons: phone
                        font.family: "Material Icons"
                        Material.background: "white"
                        Material.foreground: CommonOptions.colorDanger
                        font.bold: true
                        onClicked: emergencyService.call120()
                    }
                }
            }

            Section { titleIcon: "\ue0e7"; title: "关键步骤 (必做)"; items: entity.criticalActions || []; textColor: CommonOptions.colorDanger }
            Section { titleIcon: "\ue153"; title: "详细操作"; items: entity.steps || [] }
            Section { titleIcon: "\ue5cd"; title: "不要做"; items: entity.donts || []; textColor: CommonOptions.colorDanger; prefix: "✗ " }
            Section { titleIcon: "\ue1db"; title: "关联危险物种"; items: entity.relatedSpecies || []; visible: !!(entity.relatedSpecies && entity.relatedSpecies.length > 0) }

            // 来源
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                Layout.margins: styles.spLg

                Column {
                    anchors.left: parent.left
                    spacing: 2
                    Text {
                        text: "来源: " + (entity.source || "未知")
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                    }
                    Text {
                        text: "审核: " + (entity.reviewer || "未知")
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                    }
                }
            }

            // 决策树按钮
            Button {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 56
                text: "\ue1db 启动交互式决策"  // Material Icons: gps_fixed (target)
                font.family: "Material Icons"
                Material.background: CommonOptions.colorAccent
                Material.foreground: "white"
                font.pixelSize: styles.fsLg
                font.bold: true
                // 2026-09-14: 只有当该 entry 有决策树 (decisionNodeExists) 时启用
                property bool hasDecisionTree: detailPage.entity && detailPage.entity.decisionNodeExists === true
                visible: hasDecisionTree
                onClicked: {
                    // 2026-09-14: signal 上抛, 避免在 Page 内隐式依赖外层 stackView
                    detailPage.ApplicationWindow.window.navBus.decision(detailPage.entryId)
                }
            }

            // 2026-09-14: 没决策树的提示 (替代之前的硬显示 "启动交互式决策" 按钮)
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 48
                color: CommonOptions.colorSurface
                radius: styles.rMd
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1
                visible: !detailPage.entity || detailPage.entity.decisionNodeExists !== true
                Text {
                    anchors.centerIn: parent
                    text: "该条目暂无交互决策树，请参考上方步骤"
                    color: CommonOptions.colorTextMuted
                    font.pixelSize: styles.fsSm
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spLg }
        }
    }
}
