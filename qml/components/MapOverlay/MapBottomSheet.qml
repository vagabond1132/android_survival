/**
 * @file MapBottomSheet.qml
 * @brief 地图底部工作台 (两档 BottomSheet): 折叠态四格入口 / 展开态面板
 *
 * 2026-10-28 #156 改两档. 语法照用户提供的 5 张两步路工作台真机截图 (pass9/ref/lbw1..5,
 * 与本应用测试机同一台机器、density 3.0, 尺寸是 lum_scan.js 逐行量出来的):
 *   ① 默认**折叠**: 只露 130 逻辑 (拖把 + 一排四个入口), 地图面积从 44% 涨到 79%.
 *      原来这张抽屉是常驻 480 高不关的, 于是"工作台"三个字实际上是"地图下半屏永远是
 *      一块面板"; 而面板中部还有一片死白 (pass9 ④) —— 480 比两步路的 409 还高 71,
 *      死白不是高度不够, 是内容没铺满. 两档一起把这两件事都收掉.
 *   ② TabBar (4 枚 36 高胶囊) → 折叠态的四个大图标入口: 同一份 currentTab, 一格不丢,
 *      但入口从"切换器"变成"进哪一面"的动作, 语义更直白.
 *   ③ 通栏「标注这里」→ 收进「记录」面板的动作带. 常驻通栏是 pass9 ②③ 那一类
 *      "动作挤进内容行"的起点, SearchTab 为它让出来的那条底边距也一并消失.
 *
 * 为什么根类型是 Item 而不是 Drawer (2026-11-02 反馈①, 两版修法的完整经过):
 *   现象: 地图页底部那排「盘上目标/记录/轨迹/查找」和吸底导航条
 *   「BASE/RES/MAP/SOS/ME」叠在一起, 用户说的"导航栏看不到标注的排序/信息"是这一条.
 *   第一版 (只让视觉让位) : height += navBandH 再用 bottomPadding 把内容抬回条上方.
 *     卡片确实抬上去了 (tmp_reg/005_sheetfix/band_sos.png), 但导航条在地图页**彻底点不动**
 *     (tmp_reg/005_p_track/: BASE/SOS/ME 各点一次, 帧一直在变 11:43→11:44, 页面始终是
 *     地图页; 对照 band_res/band_map 在别的格上是会切的)。
 *   真因 (Qt Quick Controls 2 的两条机制叠起来):
 *     1) 底部 edge 的 Drawer 落点是 C++ 按 `popupParent.height - height` 硬算的, 而
 *        popupParent 恒为**全窗口** Overlay。容器内 offscreen 实测
 *        (tmp_reg/drawer_probe.qml, 窗口 800 高 / 吸底条顶 752):
 *          A 裸抽屉                 y=600 → 卡片 600..800 压条
 *          B bottomMargin: 48       y=600 → 对落点无效
 *          C parent: 内容区(752 高)  y=600 → 只改绘制父级, 落点仍按 Overlay 算
 *        → 抽屉矩形永远铺到窗口底, 也就是永远盖住 footer 那 48 逻辑。
 *     2) Overlay 是窗口最上层子项, hit-test 先问它。只要有一个开着的 Popup 的矩形
 *        覆盖到某块区域, 那块区域的点击就归这个 Popup, 底下的 footer 收不到 ——
 *        跟模态无关, 跟 Popup 里有没有 MouseArea 也无关。
 *     所以"让卡片停在导航条上方"这件事, 用底部 Drawer 做出来必然是"看得见、点不动":
 *     矩形让不开, 事件就让不开。
 *   第二版 (本文件): 根类型换 Item, 由 MapPage 用 anchors 贴在**内容区**底部 ——
 *     ApplicationWindow 的 contentData 本来就排在 header/footer 之间, 内容区下沿正好
 *     是导航条上沿, 于是卡片和它的点击区一起天然让开导航条, 不再需要 _bandInset /
 *     bottomPadding 那一档, MapPage 读 bottomSheet.height 的三处也就又是真高度了。
 *   代价 (都补了): 没有 Popup 的进出场动画; 没有 dragMargin 边缘上拉 —— 关掉的入口
 *     是拖把那一行的下拉手势 (grabTap), 重新打开的入口是 MapPage 那颗常驻把手
 *     (sheetHandle, 只在 !bottomSheet.visible 时露出), 两条都还在。
 *
 * 历史包袱 (保留说明, 别改回去):
 *   - 实时坐标必须由 MapPage 绑进来. 之前这里写 mapPage.currentLat: QML 的 id 不跨文件
 *     可见, typeof 恒为 "undefined" → 「目标」Tab 永远按 (0,0) 查.
 *   - 根类型是 Item 之后, `y` 才允许由宿主 anchors 管. 回到 Drawer 的话别再在实例上写
 *     `y:` —— 那是 QQuickPopup 关闭过渡要动的属性, 声明式绑定优先级高于动画 →
 *     close() 只把 position 归零、卡片纹丝不动 (真机两次取证).
 *   - 别在卡片里再铺一块"通吃"的 MouseArea: 内容 ColumnLayout 与它同层且后声明,
 *     childAt 永远先命中内容, 那块 MouseArea 收不到任何 press (旧 sheetShield 就是这么
 *     当了半年死代码的). 手势要挂在真正的小热区上 (拖把 grabTap).
 *   - 地图手势让位归 MapPage 的 mapGestureLayer, 本组件不拦.
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0
// 2026-09-20: 删 tabs/qmldir, RecordTab/NavigationTab/NearbyTab/SearchTab 全在 QML_FILES,
// qt_add_qml_module 自动注册到 OutdoorSurvival 1.0, 上面的 import 已能解析.

// delegate 里读外层 id (root / styles): qmlcachegen 静态编译下没有 Bound 语义
// 会在真机静默 ReferenceError (见 [[qml-delegate-outer-id-pragma]]).
pragma ComponentBehavior: Bound

Item {
    id: root

    Styles { id: styles; visible: false }

    // 两档高度 (数字来源见 Styles.qml 的 sheetFoldH/sheetExpH 注释).
    // 折叠态那 0.25 是给矮屏机兜底: 896 逻辑高的屏算出来 224 > 130, 取 130;
    // 万一将来有 480 高的屏, 也不至于让入口条吃掉一半.
    // 展开态按"当前这一面自己报的内容高"来: 列表面报 409 (要滚动空间),
    // 「记录」面报它自己的 implicitHeight (≈250)。写死 409 就是 pass9 ④ 那片
    // 中间死白 —— 面板比内容高 150, 空的是面板中部, 不是内容不够.
    height: (root.folded
            ? Math.min(parent ? parent.height * 0.25 : styles.sheetFoldH, styles.sheetFoldH)
            : Math.min(parent ? parent.height * 0.6 : _expandedHeight, _expandedHeight))

    // === 对外状态 ===========================================================
    // 折叠 = 只露四格入口; 展开 = 面板 (head + chips + 列表).
    // 默认折叠: 打开地图页不该先被一块面板占住下半屏.
    property bool folded: true
    property int currentTab: 0

    // 原 Drawer.opened 的替身: MapPage 有两处读 opened、三处读 visible, 让它们同源。
    property bool opened: true
    visible: root.opened

    function open() { root.opened = true }
    function close() { root.opened = false }

    // === 卡片本体 (原 Drawer 的 background) =================================
    Rectangle {
        id: sheetCard
        anchors.fill: parent
        color: CommonOptions.colorSurface
        radius: styles.rXl
        border.color: CommonOptions.colorDivider
        border.width: styles.lineHair
    }

    // 当前这一面想要多高. 每面都声明 preferredSheetHeight (列表面 = sheetExpH,
    // 记录面 = 内容高); 抽屉没打开过 / 取不到就退回 409, 不让高度停在 0.
    //
    // 为什么是"信号驱动写进 _tabHeight"而不是一条绑定表达式: 绑定里隔着
    // 一层 `var cur = …` 再读 cur.preferredSheetHeight 属于动态属性读, 不进依赖表
    // —— 「记录」面点下开始录制后 Card 出现、内容变高, 抽屉高度却不动,
    // 底部动作带被裁 (2026-10-28 #156 线程 C 静态取证). 换页与内容变化各有信号,
    // 就这两个信号各调一次 _syncTabHeight, 不靠绑定猜.
    property int _tabHeight: 0
    readonly property int _expandedHeight:
            _tabHeight > 0 ? _tabHeight : styles.sheetExpH

    // Qt 6.7 的 StackLayout 没有 currentItem (容器内 offscreen 实测:
    // `"currentItem" in stack` = false, 取到 undefined). 用这个不崩、但高度永远退回
    // 409 —— 静默失效最难查, 所以按 currentIndex 从 id 表里自己取.
    // 表写在函数里而不是 property 绑定: 绑定可能在子项建成前就求值, 那时 id 还是 undefined.
    function _syncTabHeight() {
        var tabs = [nearbyTab, recordTab, navigationTab, searchTab]
        var cur = tabs[stack.currentIndex]
        var pref = cur ? cur.preferredSheetHeight : 0
        root._tabHeight = pref > 0 ? Math.min(pref, styles.sheetExpH) : 0
    }

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
    // 2026-10-27 #132: 「查找」的地点模式上抛一个端点 (含 lat/lon), 宿主只把地图
    // 挪过去, 不叠加路线 —— 抽屉不知道也不该知道地图怎么画.
    signal placeSelected(var place)
    signal targetClicked(var target)
    signal trackSelected(string trackId, var track)
    signal trackAnalyzeRequested(string trackId)  // 2026-09-14: P1
    signal trackImportRequested()                 // 2026-10-09: 导入 GPX/KML/CSV
    // 2026-10-23 #109: 「轨迹」Tab 的清空已画线, 同理只做透传 —— 抽屉不知道
    //   selectedTrackIds/trackOverlays 长什么样, 也不该知道.
    signal tracksClearRequested()

    // 折叠态四格 = 展开态 StackLayout 的四档, 同一个 currentTab, 顺序也不变.
    // 两步路的四格是 记录/导航/周边线路/查找轨迹; 我们没有工作台内的"导航"面板
    // (导航在路线页, 图4 那两段式本轮明确不仿, 会撞页), 所以四格还是我们那四面.
    readonly property var _foldCells: [
        { idx: 0, icon: "explore",  label: "盘上目标" },
        { idx: 1, icon: "note_add", label: "记录" },
        { idx: 2, icon: "timeline", label: "轨迹" },
        { idx: 3, icon: "search",   label: "查找" }
    ]

    onCurrentTabChanged: stack.currentIndex = currentTab

    function fold() { root.folded = true }
    function expand() {
        root.folded = false
        if (!root.opened) root.open()
    }
    function openTab(index) {
        root.currentTab = index
        root.expand()
    }

    // 进页就停在折叠档 (地图上露着 130 那一排入口), 不是等用户去摸一条隐藏手柄.
    Component.onCompleted: {
        root._syncTabHeight()
        root.open()
    }

    // === 内容 (原 Drawer 的 contentItem; Item 版本里就是卡片的后一层子项) ======
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // === 拖把 (两档都在) ===============================================
        // 整条 20 高都是热区, 中间那根 40×3 只是形状 —— 按 3px 的条本身点不中.
        // 点它 = 折叠展开 / 展开收起; 按住往下拖 = 收一档, 折叠态再拖 = 整个关掉.
        // 2026-11-02: 下拉手势原来挂在 background 里一块铺满卡片的 sheetShield 上, 那是
        //   死代码 —— contentItem (现在是下面那个 ColumnLayout) 与它是同层兄弟且后声明,
        //   childAt 永远先命中 ColumnLayout, shield 一次也没收到过 press (真机表现 =
        //   "往下拖抽屉不动"). 手势挪到拖把这条真热区上.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: styles.spLg

            Rectangle {
                anchors.centerIn: parent
                width: styles.icBox
                height: styles.lineAccent
                radius: styles.lineAccent / 2
                color: CommonOptions.colorSurfaceAlt
            }
            MouseArea {
                id: grabTap
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                property real pressY: 0
                property bool dragged: false
                onPressed: {
                    grabTap.pressY = mouse.y
                    grabTap.dragged = false
                }
                onReleased: (mouse) => {
                    grabTap.dragged = mouse.y - grabTap.pressY > styles.icSm
                    if (!grabTap.dragged)
                        return
                    if (root.folded)
                        root.close()
                    else
                        root.fold()
                }
                onClicked: {
                    // released 里刚拖过一档, 这一记 click 不能再把它顶回对面
                    if (grabTap.dragged) {
                        grabTap.dragged = false
                        return
                    }
                    root.folded ? root.expand() : root.fold()
                }
            }
        }

        // === 折叠态: 一排四个入口 ===========================================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // 普通 visible 就能让 ColumnLayout 收起这一格
            // (Qt6.7 的 Layout 附加属性里没有 Layout.visible, 见 [[qml-layout-visible-vs-row]])
            visible: root.folded
            spacing: 0

            Repeater {
                model: root._foldCells

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredHeight: styles.rowHTall
                    color: foldTap.pressed ? CommonOptions.colorSurfaceDim
                                           : CommonOptions.colorSurface

                    // 组线: 只画左缘, 第一格不画 (与 SheetActionBand 同一套)
                    Rectangle {
                        visible: index > 0
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: styles.lineHair
                        color: CommonOptions.colorRuleSoft
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: styles.spXs

                        Rectangle {
                            // ColumnLayout 的子项只认 Layout.*: anchors.horizontalCenter 会被
                            // positioner 静默覆盖 (qmllint Quick.layout-positioning), 而 Rectangle
                            // 的隐式尺寸是 0, 只写 width/height 会被量成 0×0 —— 一律走 preferred.
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: styles.icBox
                            Layout.preferredHeight: styles.icBox
                            radius: styles.rMd
                            color: "transparent"
                            border.color: CommonOptions.colorText
                            border.width: styles.lineHair
                            IconLabel {
                                anchors.centerIn: parent
                                name: modelData.icon
                                size: styles.icLg
                                tintColor: CommonOptions.colorText
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            font.pixelSize: styles.fsMd
                            color: CommonOptions.colorText
                        }
                    }

                    MouseArea {
                        id: foldTap
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openTab(modelData.idx)
                    }
                }
            }
        }

        // === 展开态: 四个面板 ===============================================
        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.folded
            currentIndex: root.currentTab
            onCurrentIndexChanged: root._syncTabHeight()

            NearbyTab {
                id: nearbyTab
                currentLat: root.currentLat
                currentLon: root.currentLon
                targets: root.targets
                selectedRouteIds: root.selectedRouteIds
                onPreferredSheetHeightChanged: root._syncTabHeight()
                onRouteSelected: function(routeId, route) {
                    root.routeSelected(routeId, route)
                }
                onTargetClicked: function(target) { root.targetClicked(target) }
                onFoldRequested: root.fold()
            }
            RecordTab {
                id: recordTab
                onPreferredSheetHeightChanged: root._syncTabHeight()
                onCaptureRequested: root.captureRequested()
                // 2026-10-28 #156: 「标注这里」从通栏按钮搬进本面板的动作带,
                // 所以这条动作改由 RecordTab 上抛, 再由这里转给 MapPage.
                onAnnotateRequested: root.annotateRequested()
                onFoldRequested: root.fold()
            }
            NavigationTab {
                id: navigationTab
                selectedTrackIds: root.selectedTrackIds
                onPreferredSheetHeightChanged: root._syncTabHeight()
                onTrackSelected: function(trackId, track) {
                    root.trackSelected(trackId, track)
                }
                // 2026-09-14: P1 上抛分析请求
                onTrackAnalyzeRequested: function(trackId) {
                    root.trackAnalyzeRequested(trackId)
                }
                // 2026-10-09: 上抛导入请求
                onTrackImportRequested: root.trackImportRequested()
                // 2026-10-23 #109: 上抛"清空已画轨迹"
                onTracksClearRequested: root.tracksClearRequested()
                onFoldRequested: root.fold()
            }
            SearchTab {
                id: searchTab
                selectedRouteIds: root.selectedRouteIds
                onPreferredSheetHeightChanged: root._syncTabHeight()
                onRouteSelected: function(routeId, route) {
                    root.routeSelected(routeId, route)
                }
                // 2026-10-27 #132: 地点行上抛 (模式切换与取数都在 SearchTab 里做,
                // 这里只透传 —— 与 onRouteSelected 同一口径).
                onPlaceSelected: function(place) { root.placeSelected(place) }
                onFoldRequested: root.fold()
            }
        }
    }
}
