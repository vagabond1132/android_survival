/**
 * @file SpeciesDetailPage.qml
 * @brief 危险物种详情 (2026-09-19 重设计)
 *
 * 改进:
 *   - hero 区按危险度着色 (统一色阶)
 *   - 所有字段走 CommonOptions token, 不再硬编码 white/#xxx
 *   - 卡片化布局, Section 修好后字段自动填充
 *   - 海拔范围 / 活跃时段改为 2x2 网格信息卡
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: detailPage
    property string speciesId: ""
    // 2026-09-19: 改名 entity, 避开 Item 内置 data property (默认属性),
    // qmlcachegen 静态编译下 `data` 被绑到 children list (non-NOTIFYable),
    // 导致 data 后续赋值时, 所有 binding 不重新求值, 页面所有字段无信息.
    property var entity: ({})

    title: entity.commonName || "物种详情"

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    // 2026-09-17: StackView.push(url, props) 在 Qt 6.x 顺序是先 create 实例,
    // 触发 Component.onCompleted, 然后才 set properties. 所以 onCompleted 时
    // speciesId 还是空. 改用 speciesIdChanged 信号触发加载.
    onSpeciesIdChanged: {
        if (speciesId) entity = speciesService.getById(speciesId)
    }
    Component.onCompleted: {
        if (speciesId) entity = speciesService.getById(speciesId)
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

            // === 危险度 hero (色阶统一) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                color: {
                    if (entity.dangerLevel >= 5) return "#B71C1C"
                    if (entity.dangerLevel >= 4) return "#D32F2F"
                    if (entity.dangerLevel >= 3) return "#F57C00"
                    if (entity.dangerLevel >= 2) return "#FFA000"
                    return "#FBC02D"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spLg
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: "\ue002"  // Material Icons: warning
                            font.family: "Material Icons"
                            color: "white"
                            font.pixelSize: 28
                        }
                        // 2026-09-20: 危险等级 chip 统一 (5 阶段架构重构 Phase 3 接入)
                        DangerChip {
                            level: entity.dangerLevel || 0
                            Layout.fillWidth: true
                        }
                        // 危险度数字徽章
                        Rectangle {
                            id: dangerBadge
                            width: 36; height: 36
                            radius: 18
                            color: "white"
                            Text {
                                anchors.centerIn: parent
                                text: entity.dangerLevel || "?"
                                // 2026-09-19: 之前写 parent.parent.color, parent.parent
                                //   是 ColumnLayout 没定义 color, 触发 "Unable to assign
                                //   [undefined] to QColor" 让 SpeciesDetailPage 加载失败
                                color: "#B71C1C"
                                font.pixelSize: 18
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        text: entity.commonName || ""
                        color: "white"
                        font.pixelSize: styles.fsXl
                        font.bold: true
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        text: entity.scientificName || ""
                        color: "#FFCDD2"
                        font.italic: true
                        font.pixelSize: styles.fsMd
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        visible: entity.alias && entity.alias.length > 0
                        text: "又名: " + (entity.alias || []).join(" · ")
                        color: "#FFE0B2"
                        font.pixelSize: styles.fsSm
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // === 急救决策按钮 (剧毒才有) ===
            Item {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: visible ? 64 : 0
                visible: entity.firstAidId !== undefined && entity.firstAidId !== ""
                Button {
                    anchors.fill: parent
                    text: "\ue1b1 启动急救决策 (" + (entity.firstAidId || "") + ")"  // Material Icons: sos
                    font.family: "Material Icons"
                    Material.background: "#D32F2F"
                    Material.foreground: "white"
                    font.pixelSize: styles.fsLg
                    font.bold: true
                    onClicked: {
                        if (entity.firstAidId) {
                            ApplicationWindow.window.navBus.navigateTo(
                                "FirstAidDetailPage", {entryId: entity.firstAidId})
                        }
                    }
                }
            }

            // === 关键信息卡 (海拔 + 活跃月份) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 90
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    columns: 2
                    rowSpacing: styles.spSm
                    columnSpacing: styles.spMd

                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Text {
                            text: "\ue3b8 海拔范围"  // Material Icons: straighten
                            font.family: "Material Icons"
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsSm
                        }
                        Text {
                            text: entity.elevationRange || "—"
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsMd
                            font.bold: true
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Text {
                            text: "\ue878 活跃月份"  // Material Icons: event
                            font.family: "Material Icons"
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsSm
                        }
                        Text {
                            text: {
                                if (entity.activeMonths && entity.activeMonths.length > 0)
                                    return entity.activeMonths.join("·") + " 月"
                                return "—"
                            }
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsMd
                            font.bold: true
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // === 识别特征 (卡片) ===
            Section {
                titleIcon: "\ue8b6"  // search
                title: "识别特征"
                items: entity.features || []
                textColor: CommonOptions.colorText
            }

            // === 分布 (内联, 浅色) ===
            Section {
                titleIcon: "\ue0c8"  // place
                title: "分布地区"
                items: entity.distribution || []
                asInline: true
                textColor: CommonOptions.colorTextMuted
            }

            // === 栖息地 (内联, 浅色) ===
            Section {
                titleIcon: "\ue406"  // eco (leaf, 栖息地)
                title: "栖息地"
                items: entity.habitats || []
                asInline: true
                textColor: CommonOptions.colorTextMuted
            }

            // === 中毒症状 (警示色) ===
            Section {
                titleIcon: "\ue1b1"  // report_problem (中毒)
                title: "中毒症状"
                items: entity.symptoms || []
                textColor: CommonOptions.colorDanger
            }

            // === 防护装备 (成功色) ===
            Section {
                titleIcon: "\ue897"  // shield (防护)
                title: "防护装备"
                items: entity.protectiveGear || []
                textColor: CommonOptions.colorSuccess
            }

            // === 详细描述 (独立卡片) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                implicitHeight: descCol.implicitHeight + 32
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                ColumnLayout {
                    id: descCol
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: 6

                    Text {
                        text: "\ue873 详细描述"  // Material Icons: description
                        font.family: "Material Icons"
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsMd
                        font.bold: true
                    }
                    Text {
                        text: entity.description || "暂无描述"
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsSm
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // === 来源 / 审核 (灰色脚注) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.topMargin: 0
                implicitHeight: sourceCol.implicitHeight + 16
                color: "transparent"

                ColumnLayout {
                    id: sourceCol
                    anchors.fill: parent
                    spacing: 2
                    Text {
                        text: "来源: " + (entity.source || "未知")
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsXs
                    }
                    Text {
                        text: "审核: " + (entity.reviewer || "未知")
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsXs
                    }
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 24 }
        }
    }
}