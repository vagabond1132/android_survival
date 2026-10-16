/**
 * @file Main.qml
 * @brief 应用主入口
 */

import QtQuick
import QtQuick.Window
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

ApplicationWindow {
    id: window
    width: 360
    height: 720

    // 2026-09-17: 加载 Material Icons 字体, 让 IconLabel 能正确显示
    // 路径是 qrc 因为 assets/fonts/MaterialIcons-Regular.ttf 在 CMakeLists 已注册
    // 2026-09-20: 删除 read-only 的 name: 属性赋值 — FontLoader.name 在 Qt 6.7 是只读
    //   (运行时从 TTF 内部字族名读取, 写它会让整个 QML 加载失败:
    //    "Invalid property assignment: 'name' is a read-only property"
    //    → rootObjects empty → hwuiTask1 SIGABRT). TTF 内部字族名即 "Material Icons".
    // 2026-09-21: 之前用 qrc:/assets/fonts/..., 但 qt_add_qml_module 把资源放到
    //   :/qt/qml/OutdoorSurvival/assets/fonts/..., 在 Android 上可能找不到 →
    //   _fontAvailable=false → IconLabel 全走 emoji/ASCII 兜底, 但 emoji
    //   在部分 Android 上不存在, 系统字体又画不出 PUA codepoint → 显示为方框.
    //   修法: 在 main.cpp 已 addApplicationFont (3 candidate paths), QFontDatabase
    //   里已经有 "Material Icons" 这个 family. 在 QML 端 FontLoader 用同样的
    //   路径列表, 找不到时绑 status=Error, IconLabel 自动 fallback.
    // 2026-09-23: 加 status 监听 - 字体加载失败时打 warning, 方便用户抓 logcat
    //   定位"图标变方框"根因 (而不是默默显示方框).
    FontLoader {
        id: materialIconsFont
        source: "qrc:/qt/qml/OutdoorSurvival/assets/fonts/MaterialIcons-Regular.ttf"
        onStatusChanged: {
            if (status === FontLoader.Error) {
                console.warn("[FontLoader] Material Icons 字体加载失败, source=",
                             source, "→ 图标将显示为方框")
            } else if (status === FontLoader.Ready) {
                console.log("[FontLoader] Material Icons 字体已就绪")
            }
        }
    }
    // 2026-09-14: 全局 navBus, 任何 Page 通过 ApplicationWindow.window.navBus 调用
    // 解决 qmlcachegen 静态编译下 Connections.target=currentItem custom signal 失效.
    property QtObject navBus: QtObject {
        signal navigateTo(string page, var props)
        signal back()
        signal trackDetail(string trackId)
        signal decision(string entryId)
    }    minimumWidth: 320
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

    Material.theme: Material.Dark
    Material.accent: Material.Orange
    Material.primary: Material.BlueGrey

    // 2026-09-20: 统一错误反馈 Toast (5 阶段架构重构 Phase 3 接入)
    // 其它页面通过动态作用域访问: toast.success("...") / toast.error("...")
    Toast {
        id: toast
        // 铺满整个 Window,Toast 内部 anchors 到底部显示
        anchors.fill: parent
        z: 9999  // 最高层级,在所有页面之上
    }

    // 2026-09-21: 物种 service 4 路调度 (跟 Toast 同模式, id 暴露,不用 Singleton)
    // 不用 pragma Singleton 因 qmlcachegen + import OutdoorSurvival 路径下
    // Singleton 类型查找不到,运行时报 "serviceOf is not a function".
    SpeciesServiceRegistry {
        id: speciesServiceRegistry
    }

    // 2026-09-11: 拦截 Android 手机返回键 (onClosing 由 Qt 6.7 QtActivityBase
    // 把 back key 翻译成 close 事件). 行为:
    //   - stackView.depth > 1 (在子页): 先 pop, 不退出
    //   - stackView.depth == 1 (在主页): 允许退出
    onClosing: function(close) {
        if (stackView.depth > 1) {
            close.accepted = false
            stackView.pop()
        }
        // depth == 1 时 close.accepted 保持 true, 允许退出
    }

    // 状态栏
    header: ToolBar {
        Material.foreground: "white"
        RowLayout {
            anchors.fill: parent
            anchors.margins: 8

            ToolButton {
                icon.name: "menu"
                onClicked: drawer.open()
            }

            Label {
                text: "荒野手册"
                font.pixelSize: 20
                font.bold: true
                Layout.fillWidth: true
            }

            ToolButton {
                icon.name: "search"
                onClicked: searchDialog.open()
            }
        }
    }

    // 侧边栏
    Drawer {
        id: drawer
        edge: Qt.LeftEdge
        width: window.width * 0.75

        ListView {
            anchors.fill: parent
            model: ListModel {
                ListElement { name: "home"; title: "首页" }
                ListElement { name: "firstaid"; title: "急救" }
                ListElement { name: "warning"; title: "危险物种" }
                ListElement { name: "sos"; title: "SOS 紧急" }
                ListElement { name: "photo"; title: "拍照识别"; available: true }
                ListElement { name: "fire"; title: "取火"; available: false }
                ListElement { name: "shelter"; title: "庇护所"; available: false }
                ListElement { name: "build"; title: "工具"; available: false }
                ListElement { name: "knot"; title: "绳结"; available: false }
                ListElement { name: "route"; title: "路线"; available: false }
                ListElement { name: "snake"; title: "防虫防蛇"; available: false }
                ListElement { name: "pack"; title: "应急储备"; available: false }
            }
            delegate: ItemDelegate {
                width: ListView.view.width
                enabled: model.available === undefined || model.available
                opacity: enabled ? 1.0 : 0.4
                contentItem: Row {
                    spacing: 16
                    IconLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        name: model.name
                        size: 24
                        tintColor: enabled ? "white" : "#888"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.title
                        font.pixelSize: 16
                        color: enabled ? "white" : "#888"
                    }
                }
                onClicked: {
                    drawer.close()
                    // 2026-09-15: 接入 navBus, 侧边栏可一键跳转
                    if (!enabled) return
                    if (model.name === "home") {
                        // 回到主页 = pop 栈到根
                        while (stackView.depth > 1) stackView.pop()
                    } else if (model.name === "firstaid") {
                        window.navBus.navigateTo("FirstAidPage", {})
                    } else if (model.name === "warning") {
                        window.navBus.navigateTo("DangerSpeciesPage", {})
                    } else if (model.name === "sos") {
                        window.navBus.navigateTo("SOSPage", {})
                    } else if (model.name === "map") {
                        // 2026-09-15: 主页不再是地图, 这里 push MapPage
                        window.navBus.navigateTo("MapPage", {})
                    } else if (model.name === "photo") {
                        window.navBus.navigateTo("FieldGuideImagePickPage", {})
                    }
                }
            }
        }
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

        contentItem: ColumnLayout {
            spacing: 16
            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "搜索急救、动植物、避险..."
                onAccepted: performSearch()
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: searchResults
                delegate: ItemDelegate {
                    width: ListView.view.width
                    contentItem: Row {
                        spacing: 12
                        IconLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            name: model.icon
                            size: 20
                            tintColor: "white"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: model.title
                            color: "white"
                            font.pixelSize: 15
                        }
                    }
                    onClicked: {
                        searchDialog.close()
                        if (model.page && model.id !== undefined) {
                            window.navBus.navigateTo(model.page, {entryId: model.id})
                        }
                    }
                }
            }
            Button {
                text: "搜索"
                Layout.fillWidth: true
                onClicked: performSearch()
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
                    "page": "FirstAidDetailPage"
                })
            }

            // 搜物种
            var species = speciesService.search(kw)
            for (var j = 0; j < species.length; j++) {
                searchResults.append({
                    "icon": "warning",
                    "title": species[j].commonName,
                    "id": species[j].id,
                    "page": "SpeciesDetailPage"
                })
            }
        }
    }
}
