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
// 2026-10-23 真机: 「我」页整页空白. stage0.log 一句到位 ——
//   StackView: push: MePage.qml:17 module "QtQuick.Controls" plugin
//   "qml_QtQuick_Controls_qtquickcontrols2plugin" not found
// 全项目 26 页只有这一行写了**裸的** `import QtQuick.Controls`: 基座模块的插件
// androiddeployqt 不会打包 (APK 里只有 Material/Basic/impl 三个 style 插件), 所以
// 这一行在真机上必然解析失败, push 不出对象 → 页体全空. 其余页只 import
// QtQuick.Controls.Material 就拿到了 Page / ScrollView / Switch (Material 的 qmldir
// 里逐个列了这些类型), 所以这里跟着删掉就行, 不为此多塞一个 12KB 插件.
// 门禁: tools/qml_checks/controls_import_check.js 守住"裸 Controls import"不再出现.
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
    // 只防"parent 还没给高度"那一档塌陷, **不兜 800 的下限**: 内容区实际只有
    //   728 逻辑 (1080x2340@440dpi 上 StackView 给的是 272..2142), 兜到 800 就让
    //   Page 比视口高 72 逻辑, 多出来的那一截正好画在底部导航条上 (12 §4.20b)。
    height: parent && parent.height > 0 ? parent.height : 800
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
        // ScrollView 的视口 (Flickable) 默认不裁剪, 末段会直接画进底部导航条 (NavBands)
        //   那一格里 —— 0.0.5 模拟器实测「显示」段头落在 y 2236-2268, 带区是 2142-2274。
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: styles.pageGap

            // === 标题条 ===
            // 2026-11-03 #42 (L3/L13): tab 页, 右上角既无返回方块也无角标 → showBack: false.
            //   原来这一条是页头家族的第 13 份复制体 (54 高 / 微标签字距 1.6), 字距统一到
            //   组件里的 1.8 (两个拉丁字母, 肉眼不可分, 但两处写死迟早变成两处不同).
            PageHeadBand {
                eyebrowText: "ME"
                eyebrowMono: true
                titleText: "我带的东西与我留的记录"
                showBack: false
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
                trailing: "记录"
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
                trailing: "常用入口"
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

            // === 显示 ===
            // 2026-10-22 用户提的「增加 夜晚/白天 颜色切换」. 开关只写
            // CommonOptions.nightMode 一个 bool: 全站颜色都是 token, 翻档靠
            // nightModeChanged 重算, 值落 QSettings 由 main.cpp 启动读回.
            SectionTitle {
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.topMargin: styles.spMd
                text: "显示"
                trailing: "夜行不刺眼"
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.minimumHeight: styles.touchMin
                spacing: styles.spMd

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: "夜晚配色"
                        font.pixelSize: styles.fsMd
                        color: CommonOptions.colorText
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "只翻纸与墨; 信号色 (橙=火 / 红=危险 / 绿=植被) 不动"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextDim
                        wrapMode: Text.WordWrap
                    }
                }
                Switch {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: styles.touchMin
                    checked: CommonOptions.nightMode
                    onToggled: CommonOptions.nightMode = checked
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
                // 汉字与码位分两个节点: Plate 是等宽+字距, "版本" 两字进去就是方框.
                // (原先写的是 Plate{ prefix:"BUILD" }, 但 code 非空时 prefix 根本不参与渲染.)
                Text {
                    text: "版本"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorTextDim
                }
                Plate {
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
