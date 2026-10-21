/**
 * @file MePage.qml
 * @brief 第 5 格「我」— 装备 / 清单 / 我的记录 / 联系人 / 版本 (2026-10-20 丁骨架)
 *
 * 为什么要有这一页: 丁原本只有 BASE/RES/ROUTE/SOS 四个方位格, 「装备清单」和
 * 「我的记录」没有一级入口 (见 2026-10-20 评审稿 §03 Q1). 用户拍板补第 5 格,
 * 所以这一页的存在就是把丁缺的那两个入口收回来, 而不是新做功能.
 * 2026-10-20 Q3 又拍了一次: ①营地 那整块 手册 band 撤掉, 入口挪到本页第一行 ——
 * 营地是方位页, 手册没有方位, 挤在那里只是抢罗盘与面前列表的高度.
 *
 * 版式跟着①营地: 标题条 + DuoRule + 「我的记录」三格等宽读数 + ListRow 入口.
 * 计数全部来自 service 动态属性, 页面不写死数字 (改版前首页写死过 "100+ 路线",
 * 数据扩充后永远显示旧数).
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

// 「我」页
// Repeater delegate 里引用外层 id (mePage.navigateTo), qmlcachegen 静态编译下
// 必须 Bound 语义, 否则真机静默 ReferenceError (2026-10-19 同类 bug 一批).
pragma ComponentBehavior: Bound

Page {
    id: mePage

    Styles { id: styles; visible: false }

    title: "我"
    height: Math.max(parent ? parent.height : 800, 800)
    width: parent ? parent.width : 360

    background: Rectangle { color: CommonOptions.colorBg }

    function navigateTo(page, props) {
        ApplicationWindow.window.navBus.navigateTo(page, props || {})
    }

    // service 可能在退出时先于绑定销毁, 全部走空值退化
    readonly property int historyCount: fieldGuideHistory ? fieldGuideHistory.totalCount : 0
    readonly property int favoriteCount: fieldGuideHistory ? fieldGuideHistory.getFavorites().length : 0
    readonly property int trackCount: mapService ? mapService.trackCount : 0
    readonly property int photoCount: mapService ? mapService.photoCount : 0

    // 手册条目数 (2026-10-20 入口从 ①营地 挪到这一页, 数字仍然全部来自 service)
    readonly property int knotCount: knotService ? knotService.totalCount : 0
    readonly property int survivalCount: survivalService ? survivalService.totalCount : 0
    readonly property int firstAidCount: firstAidService ? firstAidService.totalEntries : 0

    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width

        ColumnLayout {
            width: parent.width
            spacing: styles.pageGap

            // === 标题条 ===
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: styles.pageMargin
                    anchors.rightMargin: styles.pageMargin
                    spacing: 3
                    Text {
                        text: "ME"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        font.letterSpacing: 1.6
                        color: CommonOptions.colorInk3
                    }
                    Text {
                        text: "我带的东西与我留的记录"
                        font.pixelSize: styles.fs2xl
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.preferredHeight: 1
                Rectangle { anchors.fill: parent; color: CommonOptions.colorRuleSoft }
            }

            // === 我的记录 (三格等宽读数, 与①营地同源) ===
            SectionTitle {
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.topMargin: 2
                text: "我的记录"
                trailing: "RECORDS"
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                spacing: styles.spSm
                Repeater {
                    model: [
                        { v: mePage.historyCount, k: "浏览条目", tap: "FieldGuidePage" },
                        { v: mePage.favoriteCount, k: "收藏", tap: "FieldGuidePage" },
                        { v: mePage.trackCount, k: "轨迹", tap: "MapPage" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        color: CommonOptions.colorSurface
                        border.color: CommonOptions.colorRule
                        border.width: styles.lineHair
                        Column {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.v
                                font.family: styles.monoFont
                                font.pixelSize: styles.fs2xl
                                color: CommonOptions.colorText
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.k
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorTextDim
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: mePage.navigateTo(modelData.tap, {})
                        }
                    }
                }
            }

            // === 入口 ===
            SectionTitle {
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.topMargin: styles.spSm
                text: "会点进去的"
                trailing: "ENTRIES"
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                spacing: styles.spSm

                // 手册三本各给一行. 原来是一行"手册"写着三个名字却只跳绳结 ——
                // 副标题承诺了急救与野外生活, 点进去却不是, 属于假入口. 三行同紫:
                // 颜色在这里说的是"同一族", 区分交给标题.
                ListRow {
                    Layout.fillWidth: true
                    title: "手册 · 急救"
                    subtitle: mePage.firstAidCount + " 条 · 按紧急度分组, 危急排最前"
                    iconName: "firstaid"
                    accent: CommonOptions.colorPlum
                    onClicked: mePage.navigateTo("FirstAidPage", {})
                }
                ListRow {
                    Layout.fillWidth: true
                    title: "手册 · 野外生活"
                    subtitle: mePage.survivalCount + " 项 · 取火 / 庇护 / 净水 / 工具"
                    iconName: "shelter"
                    accent: CommonOptions.colorPlum
                    onClicked: mePage.navigateTo("SurvivalPage", {})
                }
                ListRow {
                    Layout.fillWidth: true
                    title: "手册 · 绳结"
                    subtitle: mePage.knotCount + " 个 · 按用途分类, 可标记已学会"
                    iconName: "knot"
                    accent: CommonOptions.colorPlum
                    onClicked: mePage.navigateTo("KnotPage", {})
                }
                ListRow {
                    Layout.fillWidth: true
                    title: "装备清单"
                    subtitle: "打包核对 · 路线推荐装备"
                    iconName: "backpack"
                    // 紫留给手册, 这一行按 v9 改成 blaze (两行同紫分不出主次)
                    accent: CommonOptions.colorBlaze
                    onClicked: mePage.navigateTo("EquipmentPage", {})
                }
                ListRow {
                    Layout.fillWidth: true
                    title: "应急储备清单"
                    subtitle: "家中常备与出发前核对"
                    iconName: "build"
                    accent: CommonOptions.colorLegendAmber
                    onClicked: mePage.navigateTo("ChecklistPage", {})
                }
                ListRow {
                    Layout.fillWidth: true
                    title: "紧急联系人"
                    subtitle: "求助页长按卡片会用到的号码"
                    iconName: "call_add"
                    accent: CommonOptions.colorHazard
                    onClicked: mePage.navigateTo("EmergencyContactsPage", {})
                }
                ListRow {
                    Layout.fillWidth: true
                    title: "地图标注与照片"
                    subtitle: mePage.photoCount + " 张实地照片 · 离线包与图层在地图页里"
                    iconName: "pin_drop"
                    accent: CommonOptions.colorWater
                    onClicked: mePage.navigateTo("MapPage", {})
                }
            }

            // === 版本条 (等宽, 现场排错时用户能直接念出来) ===
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                spacing: styles.spSm
                DuoRule { Layout.fillWidth: true }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.bottomMargin: styles.spLg
                spacing: styles.spSm
                Plate {
                    prefix: "BUILD"
                    code: App.version
                }
                Text {
                    Layout.fillWidth: true
                    text: "离线数据已入库 · 无网络可用"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorTextDim
                }
            }
        }
    }
}
