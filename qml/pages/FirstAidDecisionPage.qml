/**
 * @file FirstAidDecisionPage.qml
 * @brief 急救决策树交互页
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: decisionPage
    property string entryId: ""
    property var currentNode: ({})
    property string sessionId: ""

    title: "急救决策"

    // 2026-09-20: 修 Bug 15 (与 Travel/RouteDetailPage 一致). 之前 Component.onCompleted
    //   + onEntryIdChanged 双触发, 但 onCompleted 时 entryId 还是空, 仅 onEntryIdChanged
    //   触发有效 load. 删掉 onCompleted 只留 onEntryIdChanged.
    onEntryIdChanged: {
        if (entryId) currentNode = firstAidService.getDecisionRoot(entryId)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // 紧急提醒
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: "#D32F2F"
            radius: 4

            Text {
                anchors.centerIn: parent
                text: "\ue1b1 严重情况请立即拨打 120"  // Material Icons: sos
                font.family: "Material Icons"
                color: "white"
                font.pixelSize: 14
                font.bold: true
            }
        }

        // 2026-09-14: 没决策树的兜底提示
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            visible: !currentNode || !currentNode.id
            color: CommonOptions.colorSurface
            radius: 8
            border.color: CommonOptions.colorWarn
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "\ue002 该条目暂无交互决策树\n请返回急救详情页查看操作步骤"  // Material Icons: warning
                font.family: "Material Icons"
                color: CommonOptions.colorText
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // 问题
        Text {
            text: currentNode.question || "请回答以下问题："
            font.pixelSize: 18
            font.bold: true
            color: "white"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        // 补充说明
        Text {
            text: currentNode.text || ""
            visible: !!currentNode.text
            font.pixelSize: 14
            color: "#B0BEC5"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        // 选项按钮
        Repeater {
            model: currentNode.options || []
            delegate: Button {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                text: modelData
                Material.background: "#1976D2"
                font.pixelSize: 16
                onClicked: {
                    if (currentNode.isTerminal) {
                        showTerminal(currentNode.terminalAction)
                    } else {
                        // 简化：取下一个节点
                        currentNode = firstAidService.getDecisionNode(
                            currentNode.id + "_" + (currentNode.options.indexOf(modelData) + 1))
                        if (!currentNode.id) {
                            // 没有更多节点
                            showTerminal("按关键步骤操作")
                        }
                    }
                }
            }
        }

        // 终止提示
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: terminalArea.contentHeight + 32
            visible: currentNode.isTerminal
            color: "#1B5E20"
            radius: 4

            ColumnLayout {
                id: terminalArea
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                Text {
                    text: "\ue5ca 操作总结"  // Material Icons: check
                    font.family: "Material Icons"
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    text: currentNode.terminalAction || ""
                    color: "white"
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        Item { Layout.fillHeight: true }

        // 重置按钮
        Button {
            Layout.fillWidth: true
            text: "\ue028 重新开始"  // Material Icons: refresh
            font.family: "Material Icons"
            flat: true
            onClicked: {
                currentNode = firstAidService.getDecisionRoot(entryId)
            }
        }
    }

    function showTerminal(action) {
        currentNode.isTerminal = true
        currentNode.terminalAction = action
    }
}
