/**
 * @file DangerSpeciesPage.qml
 * @brief 危险物种列表 (2026-09-14 P1 改进: token 化 + 强制分类)
 *
 * 之前 section 看不到是因为分类未排序 + 样式偏暗. 现在:
 *   - 按 category 排序, 4 类固定顺序 (蛇 > 蘑菇 > 虫 > 植物 > 动物)
 *   - section.delegate 改 token 配色 (深色背景 + 强调色左条)
 *   - 列表项卡片化 (圆角 8, surface 背景)
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: dangerPage
    title: "危险物种"
    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    // 4 大类固定顺序
    readonly property var categoryList: [
        { id: 0, name: "\ue92b 剧毒蛇类", color: "#D32F2F" },
        { id: 1, name: "\ue239 致命蘑菇", color: "#7B1FA2" },
        { id: 2, name: "\ue1b9 危险虫类", color: "#E65100" },
        { id: 3, name: "\ue406 毒植物", color: "#388E3C" },
        { id: 4, name: "\ue91a 危险动物", color: "#5D4037" }
    ]

    ListView {
        id: listView
        anchors.fill: parent
        anchors.margins: styles.spLg
        spacing: styles.spSm
        clip: true

        // 按 categoryName 分组
        section.property: "categoryName"
        section.criteria: ViewSection.FullString
        section.delegate: Rectangle {
            width: listView.width
            height: 44
            color: CommonOptions.colorSurface
            radius: styles.rMd

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: styles.spMd
                anchors.rightMargin: styles.spMd
                spacing: styles.spSm

                Rectangle {
                    width: 4
                    Layout.fillHeight: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    color: {
                        // 根据分类名匹配颜色
                        var n = section
                        if (n.indexOf("蛇") >= 0) return "#D32F2F"
                        if (n.indexOf("蘑菇") >= 0) return "#7B1FA2"
                        if (n.indexOf("虫") >= 0) return "#E65100"
                        if (n.indexOf("植物") >= 0) return "#388E3C"
                        if (n.indexOf("动物") >= 0) return "#5D4037"
                        return CommonOptions.colorAccent
                    }
                    radius: 2
                }
                Text {
                    Layout.fillWidth: true
                    text: section
                    font.family: "Material Icons"
                    color: CommonOptions.colorText
                    font.pixelSize: styles.fsLg
                    font.bold: true
                }
                Text {
                    text: listView.count  // 该分类计数
                    color: CommonOptions.colorTextMuted
                    font.pixelSize: styles.fsSm
                }
            }
        }

        model: ListModel { id: listModel }

        Component.onCompleted: load()

        function load() {
            listModel.clear()
            var dangerous = speciesService.getDangerous(3)
            // 2026-09-14: 调试日志 (临时)
            console.log("[DangerSpecies] getDangerous returned " + dangerous.length + " items")
            if (dangerous.length > 0) {
                console.log("[DangerSpecies] first item: " + JSON.stringify(dangerous[0]))
            }
            // 先按 category 排序, 顺序按 categoryList
            var byCategory = {}
            for (var i = 0; i < dangerous.length; i++) {
                var cat = dangerous[i].category
                if (!byCategory[cat]) byCategory[cat] = []
                byCategory[cat].push(dangerous[i])
            }
            // 按固定顺序输出
            for (var c = 0; c < dangerPage.categoryList.length; c++) {
                var arr = byCategory[dangerPage.categoryList[c].id]
                if (!arr) continue
                for (var j = 0; j < arr.length; j++) {
                    var catName = dangerPage.categoryList[c].name
                    listModel.append({
                        "categoryName": catName,
                        "categoryId": dangerPage.categoryList[c].id,
                        "id": arr[j].id,
                        "title": arr[j].commonName,
                        "dangerLevel": arr[j].dangerLevel
                    })
                }
            }
            // 兜底: 任何未知分类追加
            for (var k in byCategory) {
                if (k < 0 || k >= dangerPage.categoryList.length) {
                    for (var m = 0; m < byCategory[k].length; m++) {
                        listModel.append({
                            "categoryName": "其他危险",
                            "categoryId": -1,
                            "id": byCategory[k][m].id,
                            "title": byCategory[k][m].commonName,
                            "dangerLevel": byCategory[k][m].dangerLevel
                        })
                    }
                }
            }
        }

        delegate: Rectangle {
            width: ListView.view.width
            height: 72
            radius: styles.rMd
            color: CommonOptions.colorSurface
            border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
            border.width: 1

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: dangerPage.ApplicationWindow.window.navBus.navigateTo("SpeciesDetailPage", {speciesId: model.id})
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: styles.spSm
                spacing: styles.spSm

                // 危险度色条
                Rectangle {
                    width: 6
                    Layout.fillHeight: true
                    radius: 3
                    color: {
                        if (model.dangerLevel >= 5) return "#B71C1C"
                        if (model.dangerLevel >= 4) return CommonOptions.colorDanger
                        if (model.dangerLevel >= 3) return CommonOptions.colorWarn
                        return "#FFA000"
                    }
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: model.title
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsLg
                        font.bold: model.dangerLevel >= 4
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: "危险度: " + "★".repeat(model.dangerLevel) +
                              "☆".repeat(5 - model.dangerLevel)
                        color: CommonOptions.colorWarn
                        font.pixelSize: styles.fsSm
                    }
                }

                Text {
                    text: "›"
                    color: "#607D8B"
                    font.pixelSize: 22
                }
            }
        }
    }
}
