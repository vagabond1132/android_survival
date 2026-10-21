/**
 * @file FirstAidPage.qml
 * @brief 手册 · 急救目录 (2026-10-20 v9 F1 同款, 丁骨架二级页)
 *
 * 入口: 「我」第一行的手册 / ⑤求助页的 TRIAGE 卡 / 侧栏抽屉.
 * 二级页压在 stackView 里, 所以没有导航带, 返回走标题条右上角的方角.
 *
 * 版式逐块对应已评审的 mock (review-v9-screens.html 「V9 · 1」):
 *   标题条   左三段 (MANUAL / FIRST AID 微标签 / 页名 / 读数行), 右上 26px 方角返回.
 *   chip 行  全部 + 五个分类, 带条数; 再点一次取消筛选.
 *   分组     按紧急度降序 (危急 → 高 → 中 → 低), 不是分类序也不是字母序.
 *   行       3px 紧急度条 + 46px 编号列 + 标题/分类·步数 + 决策树记号 + 人字纹.
 *
 * 为什么分组轴和目录页不一样 (绳结按类目分, 这里按紧急度分):
 *   现场读法不同 —— 打开急救手册时先问"要不要命", 再问"是哪一类". 分类留给上面的
 *   chip 去筛, 分组的行序按 dangerColor 的色阶走, 一眼就能看出哪几条排最前.
 *
 * 三条不能破的规则:
 *   ① 不编数字. 条数/各档数/步数全部来自 firstAidService (totalEntries / getByCategory /
 *      getById). firstaid_entries.json 顶层 description 里的概括说法不显示.
 *   ② getByCategory() 只给 {id,title,urgency}, 分类名与步数与"有没有决策树"都只在
 *      getById() 里 → 逐条查表 (35 次 QHash). 换来目录每行能写"创伤处理 · 7 步"和
 *      哪几条可以走交互式决策, 值得. (绳结目录取用途列也是同一口径)
 *   ③ 汉字不进等宽. 编号走 Plate(monoFont + letterSpacing), 标题/分类/步数走默认字体.
 *
 * 35 条里只有 1 条 (蛇咬伤) 有决策树 (decision_nodes 共 8 个节点), 所以"决策"记号只在
 * 那一条出现 —— 这是数据的真实覆盖度, 不是页面漏了.
 */

// delegate 里要读 firstAidPage 的方法与属性, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: firstAidPage

    Styles { id: styles; visible: false }

    title: "急救"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 状态 ==============================================================
    property int currentCategory: -1      // -1 = 全部
    property var rows: []                 // 目录行 (head / entry 混合)
    property var catCounts: ({})          // category -> 条数
    property var urgencyCounts: ({})      // urgency -> 条数
    property int decisionCount: 0

    // service 在 teardown 或未注册时为 null, 读法统一兜底
    readonly property int totalEntries: firstAidService ? firstAidService.totalEntries : 0

    // FirstAidService::Category 的枚举序 + 这一页的分类名 (与 C++ categoryName 同一套字)
    readonly property var categoryOrder: [0, 1, 2, 3, 4]
    // 紧急度档位: 分组按降序 (危急排最前), chip 与读数行按同一档名
    readonly property var urgencyOrder: [5, 4, 3, 2, 1]

    function categoryName(c) {
        if (c === 0) return "急症优先"
        if (c === 1) return "创伤处理"
        if (c === 2) return "环境急症"
        if (c === 3) return "中毒急救"
        if (c === 4) return "应急功能"
        return "分类 " + c
    }

    // 与 FirstAidService::getById 里的 urgencyName 严格同字, 页面不自造说法
    function urgencyName(u) {
        if (u === 5) return "危急"
        if (u === 4) return "高"
        if (u === 3) return "中"
        if (u === 2) return "低"
        if (u === 1) return "知识"
        return "未分级"
    }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    function categoryCount(c) { return catCounts[c] || 0 }
    function urgencyCount(u) { return urgencyCounts[u] || 0 }

    // getByCategory() 遍历的是 QHash, 顺序每次启动都可能变 → 组内按编号排, 目录才稳.
    function reload() {
        var cats = ({})
        var urg = ({})
        var ordered = []
        var decisions = 0
        for (var i = 0; i < categoryOrder.length; ++i) {
            var c = categoryOrder[i]
            var src = firstAidService ? firstAidService.getByCategory(c) : []
            if (src.length === 0) continue
            cats[c] = src.length
            for (var k = 0; k < src.length; ++k) {
                var e = src[k]
                var u = Number(e.urgency) || 0
                urg[u] = (urg[u] || 0) + 1
                // 规则 ②: 分类名 / 步数 / 决策树存在性都只在 getById 里有
                var full = firstAidService ? firstAidService.getById(e.id) : ({})
                var steps = (full && full.steps) ? full.steps.length : 0
                var hasTree = !!(full && full.decisionNodeExists === true)
                if (hasTree) decisions++
                ordered.push({
                    kind: "entry",
                    id: e.id || "",
                    title: e.title || "",
                    category: c,
                    urgency: u,
                    steps: steps,
                    hasDecision: hasTree,
                    plate: CommonOptions.plateCode("FA", e.id || ""),
                    tone: CommonOptions.dangerColor(u),
                    label: "", count: 0
                })
            }
        }
        ordered.sort(function (a, b) { return a.plate < b.plate ? -1 : (a.plate > b.plate ? 1 : 0) })

        var out = []
        for (var g = 0; g < urgencyOrder.length; ++g) {
            var uu = urgencyOrder[g]
            // 组头只在这一档"当前筛选后真的有条目"时才画. 原来按全库计数 (urg[uu]) 决定
            // 要不要发头, 行却按分类筛过 → 选中"中毒急救"时, "危急"会顶着一条空组出现.
            var members = ordered.filter(function (x) {
                return x.urgency === uu
                    && (currentCategory === -1 || x.category === currentCategory)
            })
            if (members.length === 0) continue
            // 两类行必须同键: delegate 里的绑定一律求值 (`visible: false` 不拦绑定),
            // 少一个键真机上就是 "Unable to assign [undefined] to QString/bool/int"。
            out.push({
                kind: "head",
                urgency: uu,
                label: urgencyName(uu),
                count: members.length,
                tone: CommonOptions.dangerColor(uu),
                id: "", title: "", category: "", steps: 0, hasDecision: false, plate: ""
            })
            for (var m = 0; m < members.length; ++m)
                out.push(members[m])
        }
        catCounts = cats
        urgencyCounts = urg
        decisionCount = decisions
        rows = out
    }

    // 读数行: "35 条 · 危急 9 高 11 中 10 低 5 · 急症 3 创伤 3 环境 3 中毒 20 应急 6"
    // 太长会被 elide, 所以只保留紧急度那一串 (现场最需要的), 分类数留给 chip 行显示.
    readonly property string statusLine: {
        if (totalEntries === 0) return "急救数据尚未载入"
        var t = totalEntries + " 条 · "
        var first = true
        for (var i = 0; i < urgencyOrder.length; ++i) {
            var u = urgencyOrder[i]
            if (!urgencyCounts[u]) continue
            t += (first ? "" : " ") + urgencyName(u) + " " + urgencyCounts[u]
            first = false
        }
        return t + " · 可走决策 " + decisionCount
    }

    Component.onCompleted: reload()
    Connections {
        target: firstAidService
        function onDataChanged() { firstAidPage.reload() }
    }

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- 标题条 (54px: 微标签 / 页名 / 读数行, 右上 26px 方角返回) ---
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                // 给右上角的方角让位, 否则读数行从它底下穿过
                anchors.rightMargin: 40
                spacing: 3
                Text {
                    text: "MANUAL / FIRST AID"
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsXs
                    font.letterSpacing: 1.8
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: "急救"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: firstAidPage.statusLine
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: styles.spXs
                width: 26
                height: 26
                color: CommonOptions.colorSurface
                border.color: CommonOptions.colorText
                border.width: styles.lineHair
                IconLabel {
                    anchors.centerIn: parent
                    name: "back"
                    size: styles.icSm
                    tintColor: CommonOptions.colorText
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -9
                    cursorShape: Qt.PointingHandCursor
                    onClicked: firstAidPage.goBack()
                }
            }
        }

        // --- 分类 chip (全部 + 五个分类, 带条数) ---
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            spacing: styles.spXs

            Repeater {
                model: [-1].concat(firstAidPage.categoryOrder.filter(function (c) {
                    return firstAidPage.categoryCount(c) > 0
                }))
                delegate: Chip {
                    required property var modelData
                    text: (modelData === -1 ? "全部 " : firstAidPage.categoryName(modelData) + " ")
                          + (modelData === -1 ? firstAidPage.totalEntries
                                              : firstAidPage.categoryCount(modelData))
                    // 选中态是墨底, 不是紧急度色 —— 这一行只表"在看哪一类"
                    checked: firstAidPage.currentCategory === modelData
                    accent: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: firstAidPage.currentCategory =
                               (firstAidPage.currentCategory === modelData) ? -1 : modelData
                }
            }
        }

        // --- 目录 ---
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: styles.spSm
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin

            ListView {
                id: aidList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: firstAidPage.rows

                delegate: Item {
                    required property var modelData
                    width: aidList.width
                    height: modelData.kind === "head" ? 30 : styles.touchMin

                    // 分组标题 (紧急度档)
                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
                        spacing: styles.spSm
                        visible: modelData.kind === "head"

                        Rectangle {
                            Layout.preferredWidth: styles.lineAccent
                            Layout.fillHeight: true
                            Layout.topMargin: 9
                            Layout.bottomMargin: 9
                            color: modelData.tone
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        // 拉丁微标签才加字距, 中文不加 (样式铁律)
                        Text {
                            text: modelData.count + " ENTRIES"
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsXs
                            font.letterSpacing: 1.4
                            color: CommonOptions.colorInk3
                        }
                    }

                    // 条目行
                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
                        spacing: 9
                        visible: modelData.kind === "entry"

                        Rectangle {
                            Layout.fillHeight: true
                            Layout.preferredWidth: styles.lineAccent
                            color: modelData.tone
                        }
                        Plate {
                            Layout.preferredWidth: styles.plateW
                            Layout.alignment: Qt.AlignVCenter
                            code: modelData.plate
                            tone: CommonOptions.colorInk3
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: modelData.title
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsMd
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: firstAidPage.categoryName(modelData.category)
                                      + (modelData.steps > 0 ? " · " + modelData.steps + " 步" : "")
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                                elide: Text.ElideRight
                            }
                        }
                        // 决策树记号: 35 条里只有蛇咬有树, 所以这是一个"稀有的额外入口",
                        // 不是装饰. 紧急度那一栏靠左侧色条与分组已经说了, 这里不再放梯子.
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            visible: modelData.hasDecision
                            text: "决策"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorPlum
                        }
                        IconLabel {
                            Layout.alignment: Qt.AlignVCenter
                            name: "chevron_right"
                            size: 14
                            tintColor: CommonOptions.colorInk3
                        }
                    }

                    // 组标题下不留描边 (分组靠空白分级), 条目行才有 1px 组线
                    Rectangle {
                        visible: modelData.kind === "entry"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: styles.lineHair
                        color: CommonOptions.colorRuleSoft
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: modelData.kind === "entry"
                        cursorShape: Qt.PointingHandCursor
                        onClicked: firstAidPage.navigateTo("FirstAidDetailPage",
                                                            { entryId: modelData.id })
                    }
                }

                // 底注: 这一页没有"已学/进度"这类本机状态, 所以不放重置按钮.
                // 留一行来源说明, 免得用户以为这些步骤是 App 自己写的.
                footer: Item {
                    width: aidList.width
                    height: footRow.implicitHeight + styles.spMd + styles.spLg

                    RowLayout {
                        id: footRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: styles.spMd
                        spacing: styles.spSm

                        Text {
                            Layout.fillWidth: true
                            text: "内容来自包内 firstaid_entries.json · 不能替代专业救护培训"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorTextDim
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: firstAidPage.rows.length === 0
                iconName: "firstaid"
                text: firstAidPage.totalEntries === 0 ? "急救库没有载入" : "这一类没有条目"
                hint: firstAidPage.totalEntries === 0
                      ? "重装 APK 或检查 assets/data/firstaid_entries.json 是否打进包里"
                      : "换一个分类, 或点上面的「全部」"
                actionText: firstAidPage.totalEntries === 0 ? "重新载入" : "看全部"
                onActionTriggered: {
                    if (firstAidPage.totalEntries === 0) firstAidPage.reload()
                    else firstAidPage.currentCategory = -1
                }
            }
        }
    }
}
