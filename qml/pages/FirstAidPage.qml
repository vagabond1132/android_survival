/**
 * @file FirstAidPage.qml
 * @brief 急救手册列表 (2026-09-14 UI 改版)
 *
 * 改进:
 *   - 顶部 hero 渐变 (医疗红主题)
 *   - 分类按 section 分组显示
 *   - 列表项: 紧急度色条 + 标题 + 等级 + 右箭头
 *   - 全部用 CommonOptions + Styles 设计 token
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: firstAidPage
    title: "急救手册"

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    ListView {
        id: listView
        anchors.fill: parent
        spacing: 0
        clip: true

        section.property: "category"
        section.delegate: Rectangle {
            width: listView.width
            height: 36
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: styles.spLg
                anchors.rightMargin: styles.spLg
                spacing: styles.spSm

                Rectangle {
                    Layout.preferredWidth: 3
                    Layout.fillHeight: true
                    Layout.topMargin: 6
                    Layout.bottomMargin: 6
                    color: CommonOptions.colorDanger
                    radius: 2
                }
                Text {
                    text: section
                    color: CommonOptions.colorText
                    font.pixelSize: styles.fsMd
                    font.bold: true
                    Layout.fillWidth: true
                }
            }
        }

        model: ListModel {}

        Component.onCompleted: loadData()

        function loadData() {
            model.clear()

            // 2026-09-19: 分类前缀用 Material Icons codepoint + 中文, 避免 emoji 渲染 X
            var critical = firstAidService.getByCategory(FirstAidService.Critical)
            for (var i = 0; i < critical.length; i++) {
                model.append({
                    "category": "\ue548 急症优先",
                    "id": critical[i].id,
                    "title": critical[i].title,
                    "urgency": critical[i].urgency
                })
            }

            var trauma = firstAidService.getByCategory(FirstAidService.Trauma)
            for (var j = 0; j < trauma.length; j++) {
                model.append({
                    "category": "\ue43c 创伤处理",
                    "id": trauma[j].id,
                    "title": trauma[j].title,
                    "urgency": trauma[j].urgency
                })
            }

            var env = firstAidService.getByCategory(FirstAidService.Environment)
            for (var k = 0; k < env.length; k++) {
                model.append({
                    "category": "\ue1b5 环境急症",
                    "id": env[k].id,
                    "title": env[k].title,
                    "urgency": env[k].urgency
                })
            }

            var poison = firstAidService.getByCategory(FirstAidService.Poison)
            for (var l = 0; l < poison.length; l++) {
                model.append({
                    "category": "\ue1db 中毒急救",
                    "id": poison[l].id,
                    "title": poison[l].title,
                    "urgency": poison[l].urgency
                })
            }

            // 2026-09-30: 补 Emergency(应急功能) 分组. 之前 loadData() 只拼 4 类
            //   (Critical/Trauma/Environment/Poison), category=4 的条目在列表里
            //   完全不可见 — 数据侧补充中暑/腹泻/皮炎等条目后暴露该缺口.
            var emergency = firstAidService.getByCategory(FirstAidService.Emergency)
            for (var m = 0; m < emergency.length; m++) {
                model.append({
                    "category": "\ue85a 应急功能",
                    "id": emergency[m].id,
                    "title": emergency[m].title,
                    "urgency": emergency[m].urgency
                })
            }
        }

        delegate: Item {
            width: ListView.view.width
            height: 76

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: styles.spLg
                anchors.rightMargin: styles.spLg
                anchors.topMargin: styles.spXs
                anchors.bottomMargin: styles.spXs
                radius: styles.rMd
                color: CommonOptions.colorSurface
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: styles.spLg
                anchors.rightMargin: styles.spLg
                anchors.topMargin: styles.spXs
                anchors.bottomMargin: styles.spXs
                spacing: styles.spSm

                // 紧急度色条
                Rectangle {
                    width: 6
                    Layout.fillHeight: true
                    radius: 3
                    color: {
                        if (model.urgency >= 5) return "#B71C1C"
                        if (model.urgency >= 4) return CommonOptions.colorDanger
                        if (model.urgency >= 3) return CommonOptions.colorWarn
                        return CommonOptions.colorSuccess
                    }
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: model.title
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsLg
                        font.bold: model.urgency >= 4
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: {
                            if (model.urgency >= 5) return "\ue002 危急 - 立即处理"
                            if (model.urgency >= 4) return "\ue002 紧急"
                            if (model.urgency >= 3) return "中等紧急"
                            return "一般"
                        }
                        font.family: "Material Icons"
                        color: model.urgency >= 4 ? CommonOptions.colorDanger : CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                    }
                }

                Text {
                    text: "›"
                    color: "#607D8B"
                    font.pixelSize: 22
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    ApplicationWindow.window.navBus.navigateTo("FirstAidDetailPage", {entryId: model.id})
                }
            }
        }

        // 顶部 hero (统一深青绿)
        header: Rectangle {
            width: listView.width
            height: 100
            color: "#00695C"  // 深青绿
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00695C" }
                GradientStop { position: 1.0; color: "#00897B" }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: styles.spLg
                spacing: styles.spMd

                Text { text: "\ue548"; font.family: "Material Icons"; font.pixelSize: 32 }  // local_hospital
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "急救手册"
                        color: "white"
                        font.pixelSize: styles.fs2xl
                        font.bold: true
                    }
                    Text {
                        text: firstAidService.totalEntries + " 条急救知识 · 按紧急度排序"
                        color: "#FFCDD2"
                        font.pixelSize: styles.fsSm
                    }
                }
            }
        }

        // 底部间隔
        footer: Item { width: listView.width; height: styles.spLg }
    }
}
