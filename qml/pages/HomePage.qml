/**
 * @file HomePage.qml
 * @brief 主页 (2026-09-21 UI 改版)
 *
 * 改版要点:
 *   - 顶部欢迎区: 渐变背景 + 大图标 + 当前日期 + SOS 长按 3 秒提示
 *   - 救命专区: 4 个 HomeEntry 卡片 2x2 网格 (紧急救援高频)
 *   - 功能区: 9 个 FunctionEntry 按 3 类分组 (导航 / 应急 / 装备)
 *   - 全部用 CommonOptions.color* + Styles.* 设计 token
 *
 * 2026-09-28: 删除「关键统计」3 张 StatCard 整行, 欢迎区高度 180 -> 200.
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: homePage
    title: "荒野手册"

    // 2026-09-10: 修复 StackView initialItem 高度 0 导致黑屏
    height: Math.max(parent ? parent.height : 800, 800)
    width: parent ? parent.width : 360

    // 导航 signal
    function navigateTo(page, props) {
        ApplicationWindow.window.navBus.navigateTo(page, props || {})
    }
    function navigateToSimple(page) {
        ApplicationWindow.window.navBus.navigateTo(page, {})
    }

    // 当前日期 (一次性)
    property string _todayText: {
        var d = new Date()
        var weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return (d.getMonth() + 1) + "月" + d.getDate() + "日 " + weekdays[d.getDay()]
    }

    background: Rectangle { color: CommonOptions.colorBg }

    Styles { id: styles }

    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width

        ColumnLayout {
            width: parent.width
            spacing: 0

            // === 顶部欢迎区 ===
            Rectangle {
                Layout.fillWidth: true
                // 2026-09-28: 180 -> 200, 统计行删除后把空间让给欢迎区,
                //   大图标 + 安全提示有更充裕的垂直呼吸感.
                Layout.preferredHeight: 200
                color: CommonOptions.colorAccent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1A237E" }  // 深靛蓝
                    GradientStop { position: 1.0; color: "#0277BD" }  // 亮蓝
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spLg
                    spacing: styles.spSm

                    // 顶部行: 标题 + SOS
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "你好，户外人"
                                color: "white"
                                font.pixelSize: styles.fs2xl
                                font.bold: true
                            }
                            Text {
                                text: homePage._todayText + " · 今天也是安全的一天"
                                color: "#B0BEC5"
                                font.pixelSize: styles.fsSm
                                wrapMode: Text.WordWrap
                            }
                        }

                        // SOS 长按按钮 (含 tooltip)
                        ColumnLayout {
                            spacing: 4
                            Layout.alignment: Qt.AlignTop
                            SOSButton {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 64
                                onTriggered: homePage.navigateTo("SOSPage")
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "长按 3s"
                                color: "#B0BEC5"
                                font.pixelSize: 10
                            }
                        }
                    }

                    // 底部: 大图标 + 副提示
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: styles.spMd
                        spacing: styles.spMd

                        Rectangle {
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 52
                            radius: 12
                            color: Qt.rgba(1, 1, 1, 0.18)  // 半透明白

                            Text {
                                anchors.centerIn: parent
                                text: "\ue564"  // Material Icons: terrain
                                font.family: "Material Icons"
                                font.pixelSize: 28
                                color: "white"
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "200+ 急救 · 100+ 路线 · 50+ 装备\n助你安全出行"
                            color: "white"
                            font.pixelSize: styles.fsSm
                            wrapMode: Text.WordWrap
                            lineHeight: 1.4
                        }
                    }
                }
            }

            // 2026-09-28: 删除原「关键统计」3 张 StatCard 整行 (急救条目 /
            //   危险物种 / 路线). 用户报告数字行挤压救命专区, 且这三个数字
            //   在各自功能页内已有更详细的展示, 首页重复显示价值低.

            // === 救命专区 ===
            Text {
                text: "\ue548 救命专区"  // Material Icons: local_hospital
                font.family: "Material Icons"
                color: CommonOptions.colorText
                font.pixelSize: styles.fsXl
                font.bold: true
                Layout.fillWidth: true
                Layout.leftMargin: styles.spLg
                Layout.topMargin: styles.spLg
                Layout.bottomMargin: styles.spSm
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.spLg
                Layout.rightMargin: styles.spLg
                columns: 2
                rowSpacing: styles.spMd
                columnSpacing: styles.spMd

                HomeEntry {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    title: "心搏骤停\nCPR"
                    accentColor: CommonOptions.colorDanger
                    name: "cpr"
                    onClicked: homePage.navigateTo("FirstAidDetailPage", {entryId: "firstaid_cpr"})
                }
                HomeEntry {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    title: "大出血\n止血"
                    accentColor: "#C62828"
                    name: "bleeding"
                    onClicked: homePage.navigateTo("FirstAidDetailPage", {entryId: "firstaid_bleeding"})
                }
                HomeEntry {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    title: "被毒蛇\n咬伤"
                    accentColor: "#E64A19"
                    name: "snakebite"
                    onClicked: homePage.navigateTo("FirstAidDetailPage", {entryId: "firstaid_snake_bite"})
                }
                HomeEntry {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    title: "失温"
                    accentColor: CommonOptions.colorAccent
                    name: "hypothermia"
                    onClicked: homePage.navigateTo("FirstAidDetailPage", {entryId: "firstaid_hypothermia"})
                }
            }

            // === 应急功能 ===
            Text {
                text: "\ue14c 出发前必看"  // Material Icons: build
                font.family: "Material Icons"
                color: CommonOptions.colorText
                font.pixelSize: styles.fsXl
                font.bold: true
                Layout.fillWidth: true
                Layout.leftMargin: styles.spLg
                Layout.topMargin: styles.spXl
                Layout.bottomMargin: styles.spSm
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.spLg
                Layout.rightMargin: styles.spLg
                spacing: styles.spSm

                FunctionEntry {
                    Layout.fillWidth: true
                    title: "急救手册"
                    // 2026-09-30: 数字改为动态 firstAidService.totalEntries (35 条).
                    //   之前硬编码 "8 条" — 数据扩到 35 条后与实际不符.
                    // 2026-10-16: 加 null 守卫. 退出时 service 先于 QML 绑定销毁,
                    //   绑定会重算一次 (run.txt 17:28:53.648 "Cannot read property
                    //   'totalEntries' of null"), 这是整份日志里唯一的 QML warning.
                    subtitle: firstAidService
                              ? firstAidService.totalEntries + " 条急救知识 · 按类别浏览"
                              : "急救知识 · 按类别浏览"
                    name: "firstaidbook"
                    onClicked: homePage.navigateTo("FirstAidPage")
                }
                FunctionEntry {
                    Layout.fillWidth: true
                    title: "动植物图鉴"
                    // 2026-10-08: 数字改为 assets/data/*.json 实际条目数 (第四轮扩充后).
                    subtitle: "全国常见 339 植物 + 139 动物 + 114 昆虫 + 67 蘑菇 (持续扩展中)"
                    name: "fieldguide"
                    onClicked: homePage.navigateTo("FieldGuidePage")
                }
                FunctionEntry {
                    Layout.fillWidth: true
                    title: "危险物种速查"
                    subtitle: "33 种毒蛇/毒蘑菇/毒虫速查"
                    name: "dangerspecies"
                    onClicked: homePage.navigateTo("DangerSpeciesPage")
                }
            }

            // === 出行装备 ===
            Text {
                text: "\ue531 出行与装备"  // Material Icons: luggage / backback
                font.family: "Material Icons"
                color: CommonOptions.colorText
                font.pixelSize: styles.fsXl
                font.bold: true
                Layout.fillWidth: true
                Layout.leftMargin: styles.spLg
                Layout.topMargin: styles.spXl
                Layout.bottomMargin: styles.spSm
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.spLg
                Layout.rightMargin: styles.spLg
                spacing: styles.spSm

                FunctionEntry {
                    Layout.fillWidth: true
                    title: "地图与轨迹"
                    subtitle: "在线地图 + 轨迹记录 + GPX/KML/CSV 导入导出"
                    name: "map"
                    onClicked: homePage.navigateTo("MapPage")
                }
                FunctionEntry {
                    Layout.fillWidth: true
                    title: "拍照检索"
                    subtitle: "选图匹配 · 5 个候选 + 相似度"
                    name: "camera"
                    onClicked: homePage.navigateTo("FieldGuideImagePickPage")
                }
                FunctionEntry {
                    Layout.fillWidth: true
                    title: "徒步路线"
                    subtitle: "P2 已上线 · 749 条经典路线"
                    name: "hiking"
                    onClicked: homePage.navigateTo("RouteListPage")
                }
                FunctionEntry {
                    Layout.fillWidth: true
                    title: "自驾游"
                    subtitle: "P2 已上线 · 100+ 条经典路线"
                    name: "car"
                    onClicked: homePage.navigateTo("TravelListPage")
                }
                FunctionEntry {
                    Layout.fillWidth: true
                    title: "装备清单"
                    subtitle: "P2 已上线 · 43 件装备"
                    name: "backpack"
                    onClicked: homePage.navigateTo("EquipmentPage")
                }
            }

            // 底部空间
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
            }
        }
    }
}