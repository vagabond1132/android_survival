/**
 * @file MapBottomSheet.qml
 * @brief 地图底部 BottomSheet (Drawer 模拟, 4 Tab 容器 + 「标注这里」主按钮)
 *
 * Qt 6.7 Material 无原生 BottomSheet, 用 edge: Qt.BottomEdge 的 Drawer 模拟.
 * 内部 TabBar + StackLayout 切换 4 个 Tab: 目标 / 记录 / 轨迹 / 查找.
 *
 * 2026-10-16 整体改版:
 *   ① 修 NearbyTab 拿不到实时坐标. 之前这里写
 *        currentLat: (typeof mapPage !== "undefined" && mapPage) ? mapPage.currentLat : 0
 *      看着有守卫很安全, 实际 QML 的 id 不跨文件可见 — MapBottomSheet.qml 里根本
 *      没有 mapPage 这个作用域, typeof 恒为 "undefined", 表达式恒等于 0.
 *      正确做法: 本组件自己声明 currentLat/currentLon 属性, 由 MapPage.qml
 *      (mapPage 这个 id 在它自己文件里可见) 绑定下来.
 *   ② TabButton 之前把图标码位和中文拼进同一个 text 再强挂图标字体,
 *      中文只能靠字形回退 → 现已拆成 IconLabel + Text 两个节点.
 *   ③ 尺寸/颜色走 styles.* + CommonOptions.*.
 * 2026-10-19 对比度复核:
 *   - Drawer 之前没设 background 与 padding, 靠 Material 默认弹层底色, 圆角与
 *     描边缺失且各 tab 内边距由 Material padding 隐式给 → 统一改成
 *     padding: 0 + colorSurface 圆角底 + colorDivider 描边, 内边距由各 Tab 自己管.
 *   - 顶部把手宽度写死 36 → styles.icBox; 加 SectionTitle 作 sheet 标题.
 *   - TabBar 的 Text/IconLabel 之前没显式配色, 靠 Material.Dark 前景继承,
 *     在 colorRouteLine 深靛底上未选中项几乎看不出差别 → 选中 colorAccentSoft
 *     (对 colorSurface 底 7.4:1), 未选中 colorTextDim (4.9:1), 表头底色从
 *     colorRouteLine 换成 colorSurface 以免与 sheet 底色断层.
 * 2026-10-20 #61 改版 (④地图 丁骨架):
 *   ① Tab 顺序改成 目标 / 记录 / 轨迹 / 查找. 「记录」原来是第 0 格, 但地图页最高频
 *      的动作是"看这附近有什么", 不是"开始录轨迹"; 而且叠层上的搜索钮固定 openTab(3),
 *      查找必须留在最后一格.
 *   ② 4 个 TabButton 逐字复制 (只有图标名和两个汉字不同) → 内联组件 SheetTab.
 *      注意内联组件看不到外层 id (EquipmentPage 的 EnvChipRow 注释里已经踩过),
 *      所以它自带一份 Styles.
 *   ③ 底部加「标注这里」主按钮: 原来这个动作在右侧 6 枚浮动圆钮里, 圆钮整体被
 *      MapInstrumentOverlay 替掉后功能不能丢. 上抛 annotateRequested → MapPage
 *      mapPage.annotateHere() 写地图中心.
 *   ④ 删掉 nearbyRefreshRequested: 它唯一接收方是 MapPage.refreshNearby() 一个空函数
 *      ("保留扩展位"), 而 NearbyTab 早就跟着坐标变化自动重查了.
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0
// 2026-09-20: 删 tabs/qmldir, RecordTab/NavigationTab/NearbyTab/SearchTab 全在 QML_FILES,
// qt_add_qml_module 自动注册到 OutdoorSurvival 1.0, 上面的 import 已能解析.

Drawer {
    id: root

    Styles { id: styles; visible: false }

    edge: Qt.BottomEdge
    width: parent ? parent.width : 360
    height: Math.min(parent ? parent.height * 0.6 : 480, 480)
    dragMargin: styles.bottomSheetPeek   // 顶部 80px 区域可下拉
    interactive: true
    modal: false
    dim: false
    position: 0.0    // 默认关闭

    // 自己给底 (Material 默认弹层底 + 隐式 padding 会让各 Tab 内边距不可控)
    padding: 0
    background: Rectangle {
        color: CommonOptions.colorSurface
        radius: styles.rXl
        border.color: CommonOptions.colorDivider
        border.width: styles.lineHair
    }

    property int currentTab: 0

    // 由 MapPage 绑定的实时定位 (= 地图可视中心), 透传给「目标」Tab
    property real currentLat: 0
    property real currentLon: 0
    // 由 MapPage 绑定的多选状态, 透传给各 Tab (同理: Tab 内不能直接读 mapPage 的 id)
    property var selectedRouteIds: []
    property var selectedTrackIds: []
    // 盘上目标行 (mapPage.mapTargets), 「目标」Tab 与罗盘共用同一份数据
    property var targets: []

    // Tab 内容上抛给 MapPage
    signal captureRequested()
    signal annotateRequested()
    signal routeSelected(string routeId, var route)
    signal targetClicked(var target)
    signal trackSelected(string trackId, var track)
    signal trackAnalyzeRequested(string trackId)  // 2026-09-14: P1
    signal trackImportRequested()                 // 2026-10-09: 导入 GPX/KML/CSV

    onCurrentTabChanged: stack.currentIndex = currentTab

    function openTab(index) {
        currentTab = index
        if (!root.opened) root.open()
    }

    // 一格 Tab: 图标 + 汉字两个节点, 选中态读 TabButton.checked
    // (TabBar 内部用 exclusive group 驱动, 比手写 tabBar.currentIndex === 0 稳)
    component SheetTab: TabButton {
        id: btn
        Styles { id: tabStyles; visible: false }
        property string iconName: ""
        property string label: ""
        // 2026-10-19 真机: 内联组件看不到外层 styles id, 只能用自带的那一份
        implicitHeight: tabStyles.rowHSm

        contentItem: RowLayout {
            spacing: tabStyles.spXs
            IconLabel {
                name: btn.iconName
                size: tabStyles.icSm
                tintColor: btn.checked ? CommonOptions.colorAccentSoft
                                       : CommonOptions.colorTextDim
            }
            Text {
                text: btn.label
                font.pixelSize: tabStyles.fsSm
                color: btn.checked ? CommonOptions.colorAccentSoft
                                   : CommonOptions.colorTextDim
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        // 拖把 + sheet 标题 + Tab 切换 (高度交给内容, 不写死 headerHeight - 8)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: headerCol.implicitHeight + styles.spXs
            color: CommonOptions.colorSurface

            ColumnLayout {
                id: headerCol
                anchors.fill: parent
                spacing: styles.spXs

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: styles.spXs
                    Layout.preferredWidth: styles.icBox
                    Layout.preferredHeight: styles.lineAccent
                    radius: styles.lineAccent / 2
                    color: CommonOptions.colorSurfaceAlt
                }

                SectionTitle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    icon: "layers"
                    text: "地图工作台"
                    titleColor: CommonOptions.colorText
                    iconColor: CommonOptions.colorAccentSoft
                    pixelSize: styles.fsMd
                }

                TabBar {
                    id: tabBar
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.spSm
                    Layout.rightMargin: styles.spSm
                    Layout.preferredHeight: styles.rowHSm
                    currentIndex: root.currentTab
                    onCurrentIndexChanged: root.currentTab = currentIndex
                    background: Rectangle { color: "transparent" }

                    SheetTab { iconName: "explore";  label: "目标" }
                    SheetTab { iconName: "note_add"; label: "记录" }
                    SheetTab { iconName: "timeline"; label: "轨迹" }
                    SheetTab { iconName: "search";   label: "查找" }
                }
            }
        }

        // 1px 分隔线 (表头与 Tab 内容之间)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: styles.lineHair
            color: CommonOptions.colorDivider
        }

        // 4 个 Tab 内容 (StackLayout 切换)
        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTab

            NearbyTab {
                id: nearbyTab
                currentLat: root.currentLat
                currentLon: root.currentLon
                targets: root.targets
                selectedRouteIds: root.selectedRouteIds
                onRouteSelected: function(routeId, route) {
                    root.routeSelected(routeId, route)
                }
                onTargetClicked: function(target) { root.targetClicked(target) }
            }
            RecordTab {
                id: recordTab
                onCaptureRequested: root.captureRequested()
            }
            NavigationTab {
                id: navigationTab
                selectedTrackIds: root.selectedTrackIds
                onTrackSelected: function(trackId, track) {
                    root.trackSelected(trackId, track)
                }
                // 2026-09-14: P1 上抛分析请求
                onTrackAnalyzeRequested: function(trackId) {
                    root.trackAnalyzeRequested(trackId)
                }
                // 2026-10-09: 上抛导入请求
                onTrackImportRequested: root.trackImportRequested()
            }
            SearchTab {
                id: searchTab
                selectedRouteIds: root.selectedRouteIds
                onRouteSelected: function(routeId, route) {
                    root.routeSelected(routeId, route)
                }
            }
        }

        // 底部主按钮: 把"标注当前地图中心"从被删掉的浮动圆钮里接回来
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: styles.lineHair
            color: CommonOptions.colorDivider
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            Layout.bottomMargin: styles.spSm
            spacing: styles.spSm

            PrimaryButton {
                Layout.fillWidth: true
                Layout.preferredHeight: styles.btnHSm
                text: "标注这里"
                iconName: "pin_drop"
                textSize: styles.fsSm
                onClicked: root.annotateRequested()
            }
        }
    }
}
