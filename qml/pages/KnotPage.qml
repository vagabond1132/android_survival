/**
 * @file KnotPage.qml
 * @brief 手册 · 绳结目录 (2026-10-20 v9 F1, 丁骨架二级页)
 *
 * 入口在「我」第一行 (Q3 已定: ①营地 的 GUIDE band 撤掉, 手册没有方位, 挤在罗盘
 * 页只是抢方位列表的高度). 本页是二级页, 压在 stackView 里, 所以没有底部导航带,
 * 返回走标题条右上角的方角.
 *
 * 版式逐块对应已评审的 mock (review-v9-screens.html 「V9 · 1」):
 *   标题条   左三段 (MANUAL / KNOTS 微标签 / 页名 / 读数行), 右上 26px 方角返回.
 *   chip 行  全部 + 四个类目, 带条数; 再点一次取消筛选.
 *   分组     基础 → 接绳 → 环形 → 锚定 (手册的概念序, 不是字母序也不是条数序),
 *            整类都学过的那一组在标题上补一枚 forest 勾.
 *   行       3px 类目条 + 46px 编号列 + 名称/学名·用途 + 已学勾 + 3 格难度梯 + 人字纹.
 *
 * 三条不能破的规则:
 *   ① 不编数字. 条数/已学数/类目全部来自 knotService (totalCount / learnedCount /
 *      getAll), 页面不写死. knots.json 的 description 字段写着 "30 种常用绳结" 而
 *      实际只有 12 条 —— 那种句子一律不显示.
 *   ② 用途列要 use_cases, 但 getAll() 不返回它 (只有 id/nameCn/nameEn/category/
 *      difficulty/learned), 所以逐条 getById 再取第一条用途. 12 次 QHash 查表, 换
 *      来目录里"这结用来干什么"这一栏, 值得.
 *   ③ 汉字不进等宽. 编号走 Plate(monoFont + letterSpacing), 名称/用途/难度文案走
 *      默认字体 (见 [[qml-monofont-no-cjk]]).
 *
 * mock 里"环形 · 锚定 5 条"被压成一张"展开"卡, 那是 666px 画框的高度限制; 真机是
 * 可滚动列表, 不需要这种折叠机关, 所以整份目录一次摊开.
 */

// delegate 里要读 knotPage 的方法与属性, qmlcachegen 静态编译下必须 Bound,
// 否则真机静默 ReferenceError (位置: pragma 只能在根对象之前).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: knotPage

    Styles { id: styles; visible: false }

    title: "绳结"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 状态 ==============================================================
    property string currentCategory: ""    // "" = 全部
    property var rows: []                  // 目录行 (head / knot 混合)
    property var catCounts: ({})           // 类目 -> 条数

    // service 在 teardown 期间可能为 null, 全部走空值退化
    readonly property int totalKnots: knotService ? knotService.totalCount : 0
    readonly property int learnedCount: knotService ? knotService.learnedCount : 0

    // 手册的概念序 (基础→接绳→环形→锚定: 先防脱, 再接绳, 再成环, 最后锚定受力).
    // 数据里冒出第五个类目时不丢条目, 排在已知类目之后.
    readonly property var categoryOrder: ["基础", "接绳", "环形", "锚定"]

    // 类目 → 图例色 (hazard 红留给 SOS 与真危险, 这一页一律不碰):
    //   基础 forest  常用与防脱, 与"安全/可食"同绿
    //   接绳 plum    连接两段绳, 借丁骨架里"路线=紫"的连接义
    //   环形 water   承重挂点, 蓝在图例里是"可以靠它"的资源色
    //   锚定 amber   拉紧/固定, 失效即失控, 用警示而不是危险
    function toneFor(category) {
        if (category === "基础") return CommonOptions.colorForest
        if (category === "接绳") return CommonOptions.colorPlum
        if (category === "环形") return CommonOptions.colorWater
        if (category === "锚定") return CommonOptions.colorLegendAmber
        return CommonOptions.colorTextMuted
    }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }

    // C++ 侧写操作返回 Result 信封 {ok,value,error}, 不是 bool —— 直接 `if (res)` 恒真
    function _ok(res) { return !!(res && res.ok) }

    function categoryCount(cat) {
        return catCounts[cat] || 0
    }

    // 未知类目排在已知类目后面, 同一段内按编号序
    function _orderOf(cat) {
        var i = categoryOrder.indexOf(cat)
        return i < 0 ? categoryOrder.length : i
    }

    // getAll() 的 QHash 遍历序每次启动都可能变 → 行内与组内都按编号排, 目录才稳.
    // 编号由 id 决定 (CommonOptions.plateCode), 与遍历序无关.
    function reload() {
        var src = knotService ? knotService.getAll() : []
        var counts = ({})
        var ordered = []
        for (var i = 0; i < src.length; ++i) {
            var k = src[i]
            var cat = k.category || ""
            counts[cat] = (counts[cat] || 0) + 1
            // 规则 ②: 用途只在 getById 里有, 目录这一栏取第一条 use_case
            var full = knotService ? knotService.getById(k.id) : ({})
            var uses = (full && full.useCases) ? full.useCases : []
            var useStr = ""
            for (var u = 0; u < uses.length; ++u) {
                useStr += (u ? " / " : "") + uses[u]
                if (u >= 1) break          // 两条例子够了, 第三行会挤掉名称
            }
            ordered.push({
                kind: "knot",
                id: k.id,
                nameCn: k.nameCn || "",
                nameEn: k.nameEn || "",
                use: useStr,
                category: cat,
                difficulty: Number(k.difficulty) || 1,
                learned: !!k.learned,
                plate: CommonOptions.plateCode("KN", k.id),
                tone: toneFor(cat)
            })
        }
        ordered.sort(function (a, b) { return a.plate < b.plate ? -1 : (a.plate > b.plate ? 1 : 0) })

        var keys = []
        for (var key in counts) keys.push(key)
        keys.sort(function (a, b) {
            var oa = _orderOf(a), ob = _orderOf(b)
            if (oa !== ob) return oa - ob
            return a < b ? -1 : (a > b ? 1 : 0)
        })

        var out = []
        for (var c = 0; c < keys.length; ++c) {
            if (currentCategory !== "" && keys[c] !== currentCategory) continue
            var cat2 = keys[c]
            var members = ordered.filter(function (it) { return it.category === cat2 })
            var allLearned = members.length > 0
            for (var m = 0; m < members.length; ++m)
                if (!members[m].learned) allLearned = false
            out.push({
                kind: "head",
                category: cat2,
                count: members.length,
                tone: toneFor(cat2),
                allLearned: allLearned
            })
            for (var n = 0; n < members.length; ++n) out.push(members[n])
        }
        catCounts = counts
        rows = out
    }

    // 读数行: "12 结 · 难度 1~3 档 · 基础 3 接绳 4 环形 2 锚定 3 · 已学 5"
    // 整行带数字, 但数字在默认字体里也是可读的, 所以不拆等宽 (②图鉴页 statusLine 同处理)
    readonly property string statusLine: {
        if (totalKnots === 0) return "结法数据尚未载入"
        var t = totalKnots + " 结 · 难度 1~3 档"
        for (var i = 0; i < categoryOrder.length; ++i) {
            var c = categoryOrder[i]
            if (catCounts[c]) t += " · " + c + " " + catCounts[c]
        }
        return t + " · 已学 " + learnedCount
    }

    Component.onCompleted: reload()
    Connections {
        target: knotService
        function onDataChanged() { knotPage.reload() }
        function onProgressChanged() { knotPage.reload() }
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
                    text: "MANUAL / KNOTS"
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsXs
                    font.letterSpacing: 1.8
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: "绳结"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: knotPage.statusLine
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    elide: Text.ElideRight
                }
            }

            // 返回方角: 26px 描边方块, 热区向外扩 9px 到 44 (戴手套)
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
                    onClicked: {
                        var win = ApplicationWindow.window
                        if (win && win.navBus) win.navBus.back()
                    }
                }
            }
        }

        // --- 类目 chip (全部 + 四个类目, 带条数) ---
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            spacing: styles.spXs

            Repeater {
                // "全部" 固定第一位, 后面按手册的概念序 (不跟着条数跳)
                model: [""].concat(knotPage.categoryOrder.filter(function (c) {
                    return (knotPage.catCounts[c] || 0) > 0
                }))
                delegate: Chip {
                    required property var modelData
                    text: (modelData === "" ? "全部 " : modelData + " ")
                          + (modelData === "" ? knotPage.totalKnots : knotPage.categoryCount(modelData))
                    // 选中态是墨底 (mock 的 .chip.on), 不是信号色 —— 这一行只表"在看哪一组"
                    checked: knotPage.currentCategory === modelData
                    accent: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: knotPage.currentCategory =
                               (knotPage.currentCategory === modelData) ? "" : modelData
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
                id: knotList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: knotPage.rows

                // 分组标题行
                delegate: Item {
                    required property var modelData
                    width: knotList.width
                    height: modelData.kind === "head" ? 30 : styles.touchMin

                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
                        spacing: styles.spSm
                        visible: modelData.kind === "head"

                        IconLabel {
                            visible: modelData.allLearned === true
                            name: "check"
                            size: styles.icSm
                            tintColor: CommonOptions.colorForest
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.category
                                  + (modelData.allLearned ? " · 整类已学" : "")
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        // 拉丁微标签才加字距, 中文不加 (样式铁律)
                        Text {
                            text: modelData.count + " KNOTS"
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
                        visible: modelData.kind === "knot"

                        // 3px 类目条 (满高)
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
                                text: modelData.nameCn
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsMd
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: (modelData.nameEn || "")
                                      + (modelData.use ? " · " + modelData.use : "")
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                                elide: Text.ElideRight
                            }
                        }
                        IconLabel {
                            visible: modelData.learned
                            Layout.alignment: Qt.AlignVCenter
                            name: "check"
                            size: 13
                            tintColor: CommonOptions.colorForest
                        }
                        // 难度梯: 3 格实心 = 档数, 第 3 格上色 = 高难. 不用 "★★★":
                        // 星号既占宽又要在 mono 里排, 而这一栏只表达"要练几遍".
                        // 走 Ladder 组件而不是内联 Repeater —— 内层 model: 3 会把外层
                        // delegate 的 modelData 遮蔽掉, 梯度在真机上会永远空着.
                        Ladder {
                            Layout.alignment: Qt.AlignVCenter
                            cells: 3
                            value: modelData.difficulty
                            topTone: CommonOptions.colorHazard
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
                        visible: modelData.kind === "knot"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: styles.lineHair
                        color: CommonOptions.colorRuleSoft
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: modelData.kind === "knot"
                        cursorShape: Qt.PointingHandCursor
                        onClicked: knotPage.navigateTo("KnotDetailPage", { knotId: modelData.id })
                    }
                }

                // 进度重置: 学习进度是本机唯一会被"清空"的数据, 所以不藏在菜单里,
                // 也不给红色按钮 —— 它不是危险操作, 只是重练.
                // 外面包一层 Item 是因为 RowLayout 没有 topPadding/bottomPadding
                // (写了就是 qmllint missing-property), 高度只能自己按内容算.
                footer: Item {
                    width: knotList.width
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
                            text: knotPage.learnedCount + " / " + knotPage.totalKnots + " 已学 · 进度只存本机"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorTextDim
                            elide: Text.ElideRight
                        }
                        OutlineButton {
                            text: "重置进度"
                            tone: CommonOptions.colorTextMuted
                            enabled: knotPage.learnedCount > 0
                            onClicked: {
                                if (knotService) {
                                    if (!knotPage._ok(knotService.resetProgress()))
                                        console.warn("[knots] resetProgress 返回非 ok 信封")
                                    knotPage.reload()
                                }
                            }
                        }
                    }
                }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: knotPage.rows.length === 0
                iconName: "knot"
                text: knotPage.totalKnots === 0 ? "绳结库没有载入" : "这一类没有条目"
                hint: knotPage.totalKnots === 0
                      ? "重装 APK 或检查 assets/data/knots.json 是否打进包里"
                      : "换一类, 或点上面的「全部」"
                actionText: knotPage.totalKnots === 0 ? "重新载入" : "看全部"
                onActionTriggered: {
                    if (knotPage.totalKnots === 0) knotPage.reload()
                    else knotPage.currentCategory = ""
                }
            }
        }
    }
}
