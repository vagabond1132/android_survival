/**
 * @file Main.qml
 * @brief 应用主入口
 */

// 2026-10-19 真机 stage0.log: delegate 里引用外层 id (如 categorySection / searchDialog) 在 qmlcachegen
// 编译下会抛 ReferenceError, 必须 Bound 语义才能拿到外层组件作用域.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

ApplicationWindow {
    id: window
    width: 360
    height: 720

    // 2026-10-16 整体改版: 删除这里的 FontLoader (原 2026-09-17~09-23 那套).
    // 字族注册已由 main.cpp 在 QQmlApplicationEngine 构造前完成 (3 个候选路径),
    // QML 端再挂一个 FontLoader 只是对同一 TTF 第二次 addApplicationFont.
    // 更要紧的是它的 status 从未被真正读到: IconLabel 引用的 materialIconsFont
    // 是跨文件 id, QML 里不可见 → 那个"字体已就绪"判断恒为 false.
    // 现在字体状态统一走 CommonOptions.iconFontReady (main.cpp 写入).

    // 2026-09-14: 全局 navBus, 任何 Page 通过 ApplicationWindow.window.navBus 调用
    // 解决 qmlcachegen 静态编译下 Connections.target=currentItem custom signal 失效.
    property QtObject navBus: QtObject {
        signal navigateTo(string page, var props)
        signal back()
        signal trackDetail(string trackId)
        signal decision(string entryId)
    }
    minimumWidth: 320
    minimumHeight: 600
    visible: true
    title: App.version + " - 荒野手册"

    // TEMP DIAG 2026-09-21: QML 加载完成回调, 输出到 qDebug, 验证 rootObjects 创建成功
    Component.onCompleted: {
        console.log("[TEMP-DIAG] Main.qml Component.onCompleted, title=", title,
                    "visible=", visible, "App.version=", App.version)
    }
    // TEMP DIAG: 窗口显示后回调, 用于验证是否进入事件循环
    onActiveChanged: {
        if (active) {
            console.log("[TEMP-DIAG] Main.qml onActive=true, window fully shown")
        }
    }

    // 2026-10-16 整体改版: 尺寸 token. Styles 是普通 Item (非单例, 见 Styles.qml),
    // 这里实例化一份给窗口级 chrome (header / drawer / 搜索框) 用.
    // 0x0 + visible:false, 不参与布局.
    Styles {
        id: winStyles
        visible: false
    }

    // 2026-10-20 「地物图例」: Material 跟着 token 换成浅色底.
    // 上一版是 Material.Dark + accent 蓝, 而自绘组件走 CommonOptions, 同一屏两套
    // 主色 —— 那是被否的直接原因. 现在 theme=Light, accent/primary 都是墨色,
    // Switch / Slider / 焦点框和卡片描边读同一个颜色.
    Material.theme: Material.Light
    Material.accent: CommonOptions.colorAccent
    Material.primary: CommonOptions.colorAccent
    Material.background: CommonOptions.colorBg
    Material.foreground: CommonOptions.colorText

    // 2026-09-20: 统一错误反馈 Toast (5 阶段架构重构 Phase 3 接入)
    // 2026-10-20: 挂一个 alias 到 Window 上. 原先各页直接写 toast.success()/toast.error(),
    //   靠的是"QML id 顺着创建上下文链能查到别的文件的 id"这个巧合 —— 实测 (qmlcachegen
    //   编译的最小工程) 确实查得到, 所以旧调用是弹过的, 不是死代码. 但 QML 语义只保证
    //   id 在声明它的文件内可见, 这个巧合不该被 31 处调用依赖: 页面改成动态 createObject
    //   或被别的宿主嵌进去就静默变 undefined. 页面侧统一写
    //   `readonly property var toast: ApplicationWindow.window.toastBox`, 调用点不变.
    readonly property alias toastBox: toast
    Toast {
        id: toast
        // 铺满整个 Window,Toast 内部 anchors 到底部显示
        anchors.fill: parent
        z: 9999  // 最高层级,在所有页面之上
    }

    // 2026-09-21: 物种 service 4 路调度 —— 这里原来实例化一个 SpeciesServiceRegistry 并靠
    //   id 给各页调用. 2026-10-20 撤掉: 四王国 service 都是 context property, 任何文件都能
    //   直接引用 (FieldGuideDetailPage / HomePage / RouteDetailPage 一直是这么写的), 不需要
    //   在 Window 里养一个实例再靠跨文件 id 查它 —— 那种查法只靠"创建上下文链"这个巧合,
    //   QML 语义并不保证. 唯一的使用方 FieldGuidePage 已改成本地 kingdomService() 分发.

    // 2026-09-11: 拦截 Android 手机返回键 (onClosing 由 Qt 6.7 QtActivityBase
    // 把 back key 翻译成 close 事件). 行为:
    //   - stackView.depth > 1 (在子页): 先 pop, 不退出
    //   - 在别的格的根页 (非 BASE): 回到营地格, 不退出 —— 5 格应用的常规返回语义
    //   - 已在 BASE 根页: 允许退出
    onClosing: function(close) {
        if (stackView.depth > 1) {
            close.accepted = false
            stackView.pop()
            return
        }
        if (navBands.current !== "base") {
            close.accepted = false
            openBand("base")
        }
        // 已在 BASE 时 close.accepted 保持 true, 允许退出
    }

    // 状态栏
    // 2026-10-16 改版修 bug: 原来两个 ToolButton 用 icon.name: "menu" / "search",
    //   那是 Qt 的 freedesktop 图标主题名, Android 上根本没有图标主题 → 两个按钮
    //   渲染成空白可点击区 (用户看不到菜单/搜索入口). 改成 IconLabel 直接画字形.
    header: ToolBar {
        id: winHeader
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        // 2026-10-20: 顶栏收成 44 (原来 headerHeight=56). 场卡版式里正文要放盘 +
        // 读数 + 4 方位格 + 记录, 顶栏每多 1px 正文就少 1px; 两个图标按钮的
        // touchMin 仍是 44, 所以 44 是下限而不是凑数.
        height: winStyles.titleHeight

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: winStyles.spSm
            anchors.rightMargin: winStyles.spSm
            spacing: winStyles.spXs

            ToolButton {
                Layout.preferredWidth: winStyles.touchMin
                Layout.preferredHeight: winStyles.touchMin
                onClicked: drawer.open()
                contentItem: IconLabel {
                    name: "menu"
                    size: winStyles.icLg
                    tintColor: CommonOptions.colorText
                    anchors.centerIn: parent
                }
                Accessible.name: "菜单"
            }

            Label {
                text: "荒野手册"
                color: CommonOptions.colorText
                // 顶栏标题 = 标题档 15 (原来 fs2xl=22 在 44px 条里把正文挤掉一行)
                font.pixelSize: winStyles.fsLg
                font.bold: true
                Layout.fillWidth: true
                verticalAlignment: Text.AlignVCenter
            }

            // 顶栏右侧在搜索按钮前放一个等宽 BUILD 号 (现场排错时用户能直接念)
            Text {
                text: "v" + App.version
                font.family: winStyles.monoFont
                font.pixelSize: winStyles.fsXs
                font.letterSpacing: 1.0
                color: CommonOptions.colorInk3
                visible: text.length > 1
            }

            ToolButton {
                Layout.preferredWidth: winStyles.touchMin
                Layout.preferredHeight: winStyles.touchMin
                onClicked: searchDialog.open()
                contentItem: IconLabel {
                    name: "search"
                    size: winStyles.icLg
                    tintColor: CommonOptions.colorText
                    anchors.centerIn: parent
                }
                Accessible.name: "搜索"
            }
        }
    }

    // 侧边栏
    // 2026-10-16 改版修 bug: 原 ListModel 里 取火/庇护所/工具/绳结/路线/防虫防蛇/
    //   应急储备 7 项标 available:false 并灰掉, 但 KnotPage / RouteListPage /
    //   TravelListPage / EquipmentPage / ChecklistPage / SurvivalPage 这些页面
    //   早就存在且主页能进 → 抽屉里却显示"未开放", 是改版前遗留的过期状态.
    //   同时缺「地图与轨迹」条目 (onClicked 里写了 map 分支, model 却没有 map 行).
    //   现在按实际存在的页面重建, 全部可点.
    Drawer {
        id: drawer
        edge: Qt.LeftEdge
        width: window.width * 0.75
        // 2026-10-19 真机: 必须显式给 height. Qt 6.7 Material 的 Drawer 高度走
        //   implicitHeight = max(背景 implicitHeight, contentHeight + padding), 而它的
        //   background 只声明了 implicitWidth: 360, 内容 ListView 又用 anchors.fill 不贡献
        //   隐式高度 → 抽屉塌成 ~89px 一条, 13 个入口全部点不到 (只剩右上角搜索能用).
        height: window.height
        Material.background: CommonOptions.colorSurface

        ListView {
            anchors.fill: parent
            anchors.topMargin: winStyles.spSm
            anchors.bottomMargin: winStyles.spSm
            model: ListModel {
                ListElement { name: "home";          title: "首页" }
                ListElement { name: "map";           title: "地图与轨迹" }
                ListElement { name: "firstaid";      title: "急救手册" }
                ListElement { name: "warning";       title: "危险物种速查" }
                ListElement { name: "fieldguide";    title: "动植物图鉴" }
                ListElement { name: "photo";         title: "拍照检索" }
                ListElement { name: "route";         title: "徒步路线" }
                ListElement { name: "car";           title: "自驾游" }
                ListElement { name: "pack";          title: "装备清单" }
                ListElement { name: "knot";          title: "绳结" }
                ListElement { name: "shelter";       title: "生存技能" }
                ListElement { name: "build";         title: "应急清单" }
                ListElement { name: "sos";           title: "SOS 紧急求助" }
            }
            delegate: ItemDelegate {
                width: ListView.view.width
                height: winStyles.rowH
                contentItem: RowLayout {
                    spacing: winStyles.spMd
                    IconLabel {
                        name: model.name
                        size: winStyles.icLg
                        tintColor: CommonOptions.colorTextMuted
                    }
                    Text {
                        text: model.title
                        color: CommonOptions.colorText
                        font.pixelSize: winStyles.fsLg
                        Layout.fillWidth: true
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                onClicked: {
                    drawer.close()
                    switch (model.name) {
                    case "home":
                        // 2026-10-20: 一级导航已换成底部 5 方位带, "回主页" 就是回 BASE 格
                        //   (原来写 while(depth>1) pop(), 会把栈退回 initialItem, 但如果
                        //    用户是从别的格进来的, 高亮和栈会不同步)
                        window.openBand("base")
                        break
                    case "firstaid":   window.navBus.navigateTo("FirstAidPage", {}); break
                    case "warning":    window.navBus.navigateTo("DangerSpeciesPage", {}); break
                    // 动植物图鉴 = RES 格的根页, 走高德那套切格而不是压栈
                    case "fieldguide": window.openBand("res"); break
                    case "sos":        window.openBand("sos"); break
                    case "map":        window.openBand("route"); break
                    case "photo":      window.navBus.navigateTo("FieldGuideImagePickPage", {}); break
                    case "route":      window.navBus.navigateTo("RouteListPage", {}); break
                    case "car":        window.navBus.navigateTo("TravelListPage", {}); break
                    // 装备/绳结/生存/清单: 装备是「我」格的内容, 绳结与清单是手册条目,
                    // 都作为子页压在栈上 (它们不是一级格)
                    case "pack":       window.navBus.navigateTo("EquipmentPage", {}); break
                    case "knot":       window.navBus.navigateTo("KnotPage", {}); break
                    case "shelter":    window.navBus.navigateTo("SurvivalPage", {}); break
                    case "build":      window.navBus.navigateTo("ChecklistPage", {}); break
                    }
                }
            }
        }
    }

    // === 底部 5 方位带 (2026-10-20 丁骨架) ===
    // BASE 营地 / RES 资源 / ROUTE 路线 / SOS 求助 / 我.
    // 上面 12 项抽屉保留 (顶栏菜单开), 它是"全部入口"的逃生口, 也是 #26 那个
    // 抽屉高度塌陷 bug 的唯一现场 —— 一级导航换成这一条之后, 抽屉坏了不再等于
    // 全站导航全废 (改版前 绳结/生存/清单 就是这么找不到的).
    footer: NavBands {
        id: navBands
        onBandActivated: function(key) { window.openBand(key) }
    }

    // 每格对应哪个根页. 第 5 格「我」是 2026-10-20 用户拍板补的: 丁原本没有
    // 装备与我的记录的一级入口.
    readonly property var bandPage: ({
        base:  "HomePage",
        res:   "FieldGuidePage",
        route: "MapPage",
        sos:   "SOSPage",
        me:    "MePage"
    })

    // 切根页: 清掉子页栈, 换成该格的根页.
    // objectName 用来判断"已经在这一格了", 避免重复点把页面重建一次
    // (MapPage 重建会重新拉瓦片与定位, 代价不小).
    function openBand(key) {
        var page = bandPage[key]
        if (!page) return
        navBands.current = key
        var cur = stackView.currentItem
        if (stackView.depth === 1 && cur && cur.objectName === "band:" + key) return
        stackView.clear(StackView.Immediate)
        stackView.push(pageUrl(page), { objectName: "band:" + key }, StackView.Immediate)
    }

    function pageUrl(page) {
        return Qt.resolvedUrl("qrc:/qt/qml/OutdoorSurvival/qml/pages/" + page + ".qml")
    }

    // === 底图会话 (2026-10-20, #14/#21) ===
    // 为什么存在窗口级而不是 MapPage 里: Qt6 的 Map.plugin 是 write-once ——
    //   QDeclarativeGeoMap::setPlugin() 开头就是
    //   `if (m_plugin) { qmlWarning("Plugin is a write-once property, and cannot be
    //   set again."); return; }` (6.7.2 实测告警一致). 换 Plugin 对象这条路根本不通,
    //   想让新的 osm.mapping.host 生效只能重建 Map, 而 Map 内联在 MapPage 里 →
    //   重建整页. 页内属性活不过重建, 所以「选了哪个底图 / failover 试到第几个 /
    //   正看着哪儿」放在这里, 由 MapPage 读写.
    property int mapBaseMapIndex: 0
    property int mapFailoverTries: 0
    property real mapViewLat: Number.NaN
    property real mapViewLon: Number.NaN
    property real mapViewZoom: Number.NaN

    // 强制重建某一格的根页. openBand() 对「已经在这一格」直接 return (那是为了
    // 不重复拉瓦片), 换底图要的恰恰是重建, 所以单独开一个口子.
    function restartBand(key) {
        var page = bandPage[key]
        if (!page) return
        navBands.current = key
        stackView.clear(StackView.Immediate)
        stackView.push(pageUrl(page), { objectName: "band:" + key }, StackView.Immediate)
    }

    // 某个页名是不是某一格的根页 (用来同步底栏高亮)
    function bandKeyOf(page) {
        for (var k in bandPage)
            if (bandPage[k] === page) return k
        return ""
    }

    // 主内容
    StackView {
        id: stackView
        anchors.fill: parent
        // 2026-09-15: 改回 HomePage 作为 initialItem
        // (之前 MapPage 作主页时, 因地图插件/瓦片未就绪 + QML6 signal handler 语法
        //  导致 Component not ready + SIGSEGV, 用户回退方案)
        initialItem: homePageComponent

        // 监听 window.navBus 信号
        Connections {
            target: window.navBus
            function onNavigateTo(page, props) {
                if (!page) return
                var qmlUrl = (page.indexOf("qrc:") === 0 || page.indexOf("file:") === 0)
                             ? page
                             : "qrc:/qt/qml/OutdoorSurvival/qml/pages/" + page + ".qml"
                stackView.push(Qt.resolvedUrl(qmlUrl), props || {})
                // 目标正好是某一格的根页时把高亮跟过去, 否则底栏会指着别的格
                var bk = window.bandKeyOf(page)
                if (bk) navBands.current = bk
            }
            function onBack() {
                if (stackView.depth > 1) stackView.pop()
            }
            function onTrackDetail(trackId) {
                if (!trackId) return
                stackView.push(
                    Qt.resolvedUrl("qrc:/qt/qml/OutdoorSurvival/qml/pages/TrackDetailPage.qml"),
                    { trackId: trackId })
            }
            function onDecision(entryId) {
                if (!entryId) return
                stackView.push(
                    Qt.resolvedUrl("qrc:/qt/qml/OutdoorSurvival/qml/pages/FirstAidDecisionPage.qml"),
                    { entryId: entryId })
            }
        }
    }

    // 主页 Component (延迟实例化, 让 StackView 第一次 push 时再创建)
    // 关键: 不能再在 Component 内部写 onNavigateTo (QML 不识别, 报 "non-existent
    // property" 错). Component 内只能放纯 Page, 信号由外部 Connections 监听.
    Component {
        id: homePageComponent
        HomePage {}
    }

    // 2026-09-15: 保留 MapPage Component, 侧边栏可手动进入 (已不再作 initialItem)
    Component {
        id: mapPageComponent
        MapPage {}
    }

    // 2026-09-11: SOS 按钮移到 HomePage 内部 (SOSPage.qml 可独立触发),
    // 不再在 Main.qml 顶层浮一个, 避免"每个页面都有 SOS"的视觉错觉.
    // SOSButton { ... } 删除.

    // 搜索对话框
    Dialog {
        id: searchDialog
        title: "搜索"
        modal: true
        anchors.centerIn: parent
        width: parent.width * 0.9
        height: parent.height * 0.6
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText

        contentItem: ColumnLayout {
            spacing: winStyles.spMd
            TextField {
                id: searchField
                Layout.fillWidth: true
                Layout.preferredHeight: winStyles.fieldH
                placeholderText: "搜索急救、动植物、避险..."
                color: CommonOptions.colorText
                placeholderTextColor: CommonOptions.colorTextDim
                font.pixelSize: winStyles.fsMd
                onAccepted: searchDialog.performSearch()
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // 2026-10-19 真机: 结果区 fillHeight, 未搜索/无命中时是一整块空白
                //   (对话框高度固定 60%), 看不出是"还没搜"还是"搜了没有" → 叠一行提示.
                // 2026-10-20: 提示原来写在 ListView 的 foreground 里 —— ListView 没有
                //   这个属性. 声明式赋一个不存在的属性是加载期硬错误 (Cannot assign to
                //   non-existent property), 而 Main.qml 是根组件, 一处写坏 = 整个 app
                //   起不来. 改成 Item 里叠一层 Text, 不进 content、不影响滚动.
                ListView {
                    anchors.fill: parent
                    model: searchResults
                    delegate: ItemDelegate {
                        width: ListView.view.width
                        height: winStyles.rowH
                        contentItem: RowLayout {
                            spacing: winStyles.spMd
                            IconLabel {
                                name: model.icon
                                size: winStyles.icMd
                                tintColor: CommonOptions.colorTextMuted
                            }
                            Text {
                                text: model.title
                                color: CommonOptions.colorText
                                font.pixelSize: winStyles.fsMd
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        onClicked: {
                            searchDialog.close()
                            if (model.page && model.id !== undefined) {
                                // 2026-10-20: 原来所有结果都传 {entryId}, 但物种详情读的是
                                //   speciesId → 从搜索点进物种是一张空页. 入参名跟着结果走.
                                var props = {}
                                props[model.prop] = model.id
                                if (model.danger)
                                    props.preferDanger = true
                                window.navBus.navigateTo(model.page, props)
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: searchResults.count === 0
                    text: "输入关键词后点「搜索」，可查急救处置与动植物物种"
                    color: CommonOptions.colorTextMuted
                    font.pixelSize: winStyles.fsSm
                }
            }
            Button {
                text: "搜索"
                Layout.fillWidth: true
                Layout.preferredHeight: winStyles.btnH
                // 2026-10-19 真机 stage0.log: 原来直接写 performSearch(), 报
                //   "ReferenceError: performSearch is not defined" —— Dialog 体内
                //   声明的 function 是 Dialog 实例的属性, 不在 contentItem 子对象的
                //   组件作用域里, 必须用 id 限定. 全局搜索因此一次都没跑过.
                onClicked: searchDialog.performSearch()
            }
        }

        ListModel { id: searchResults }

        function performSearch() {
            searchResults.clear()
            var kw = searchField.text
            if (kw.length < 1) return

            // 搜急救
            var firstAid = firstAidService.search(kw)
            for (var i = 0; i < firstAid.length; i++) {
                searchResults.append({
                    "icon": "firstaid",
                    "title": firstAid[i].title,
                    "id": firstAid[i].id,
                    "prop": "entryId",
                    "page": "FirstAidDetailPage",
                    "danger": false
                })
            }

            // 搜物种
            var species = speciesService.search(kw)
            for (var j = 0; j < species.length; j++) {
                searchResults.append({
                    "icon": "warning",
                    "title": species[j].commonName,
                    "id": species[j].id,
                    "prop": "speciesId",
                    "page": "FieldGuideDetailPage",
                    // 结果来自 danger_species (33 条), 同一 id 在 659 条图鉴里也有
                    //   一份时, 搜索点进来的内容要跟危险页一致.
                    "danger": true
                })
            }
        }
    }
}
