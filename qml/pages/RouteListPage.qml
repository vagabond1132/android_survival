/**
 * @file RouteListPage.qml
 * @brief 徒步路线目录 (2026-10-20 v9 F1 同款, 丁骨架二级页)
 *
 * 入口是顶栏菜单抽屉的「路线」(Main.qml case "route"), 压在 stackView 上,
 * 不是④地图那一格的根页, 所以没有底栏, 返回走标题条右上角的方角.
 *
 * 版式逐块对应已评审的 mock (手册目录 F1 母版):
 *   标题条   左三段 (ROUTE 微标签 / 页名 / 读数行), 右上 26px 方角返回.
 *   筛选卡   难度 6 枚 chip 单行 + 一行说明上限语义的汉字注, 省份/月份走 combo.
 *   分组     按省份分组 (33 个省, 组头带条数), 组内按图鉴编号序.
 *   行       3px 难度条 + 46px 编号列 + 名称/里程·天数·性质 + 5 格难度梯 + 人字纹.
 *
 * 三条不能破的规则:
 *   ① 不编数字. 读数行与组头条数全部来自 routeService.getAdvanced() 一次取回的那份库,
 *      页面不写死. 749 是 totalCount, 能列出来的是 747 —— 差额是被"不推荐"规则
 *      (notRecommended 或 6000m+ 且非休闲类) 剔掉的库拉岗日与玉珠峰两条. 旧版 Hero
 *      写"共 749 条经典徒步路线"却列 747 条, 这一版把差额直接说出来.
 *   ② 难度是上限不是精确匹配. 选"3 星"= 1~3 星 (野外选线问的是"我走不走得动这个及以下"),
 *      这个语义写在 chip 下面那行注里, 不靠用户猜.
 *   ③ 汉字不进等宽. 编号与 SKILLS 类微标签走 monoFont + letterSpacing, 名称/副行走默认字体
 *      (见 [[qml-monofont-no-cjk]]).
 *
 * 2026-10-20 改版顺带换掉的三处旧实现:
 *   - 不再用 ServiceListModel + getFiltered 每改一次筛选回表一次. 三个筛选条件全在
 *      客户端算: 747 行一次取回, 换条件只重排一遍, 省掉每次点击的 Result 解包, 也
 *      避免 getFiltered 遍历 QHash 时组内顺序每次启动都可能变.
 *   - 省份/月份的下拉框 index 改成从页面状态反查的绑定. 旧版 resetFilters() 直接写
 *      filterRowProv.comboBoxInstance.currentIndex = 0 (从外面扳组件内部的 Loader 实例),
 *      重置得靠那句才生效; 现在状态是单一来源, FilterRow 自己跟着变.
 *   - 行尾的 "★" 与手抄 "›" 字符去掉, 难度改用 Ladder 格梯 (星号要挤进等宽族才有形状,
 *      而汉字不许进等宽), 人字纹改用 IconLabel chevron_right.
 */

// delegate 里要读 routeListPage 的方法与状态, qmlcachegen 静态编译下必须 Bound,
// 否则真机静默 ReferenceError (见 [[qml-delegate-outer-id-pragma]]).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: routeListPage

    Styles { id: styles; visible: false }

    title: "路线"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 筛选状态 ===========================================================
    property int maxDifficulty: 0      // 0 = 全部; N = 只看 ≤N 星
    property string province: ""       // "" = 全部
    property int month: 0              // 0 = 全部

    // === 数据 ===============================================================
    // library = 一次取回的全部"可推荐"路线 (11 个键, 见 getAdvanced)
    // rows    = 当前筛选结果: {kind:"head"|"item", ...} 混合, 交给同一个 ListView
    property var library: []
    property var rows: []
    property var provinceChoices: ["全部"]
    property int shownCount: 0
    // 库覆盖率 (不随筛选变, 描述的是"这一库有什么")
    property int provinceTotal: 0
    property int diffLo: 0
    property int diffHi: 0

    readonly property int libCount: library.length
    readonly property int hiddenCount: routeService ? (routeService.totalCount - libCount) : 0

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    // getAdvanced 是这套服务里唯一一次就给全行情的口子: 距离/天数/性质/野线/最高海拔/
    // 适宜月份都在返回里, 而且返回的是裸 QVariantList (没有 Result 包装).
    // 12 个参数取"不加过滤"的组合: 省份空串 / 难度 1~5 / 月份 0 / 性质空串 /
    // 野线与景区都收 / 天数与里程区间 0.
    function loadLibrary() {
        if (!routeService) { library = []; return }
        var fetched = routeService.getAdvanced("", 1, 5, 0, "", true, true, 0, 0, 0, 0)
        library = (fetched && fetched.length !== undefined) ? fetched : []

        var seen = ({})
        var lo = 0
        var hi = 0
        for (var i = 0; i < library.length; ++i) {
            var r = library[i]
            var p = String(r.province || "")
            if (p !== "") seen[p] = true
            var d = Number(r.difficulty) || 0
            if (lo === 0 || d < lo) lo = d
            if (d > hi) hi = d
        }
        var keys = []
        for (var k in seen) keys.push(k)
        // 码位序 —— 与 C++ 侧 getAvailableProvinces() 的 std::sort 同一条序,
        // 两处若各排各的, 下拉框与组头会读成两个顺序.
        keys.sort(function (a, b) { return a < b ? -1 : (a > b ? 1 : 0) })
        provinceChoices = ["全部"].concat(keys)
        provinceTotal = keys.length
        diffLo = lo
        diffHi = hi
    }

    function hasMonth(seasons, m) {
        if (!seasons || seasons.length === undefined) return false
        var token = m + "月"
        for (var i = 0; i < seasons.length; ++i) {
            if (String(seasons[i]) === token) return true
        }
        return false
    }

    function formatKm(km) {
        // 里程右边界要对齐: 35.2 与 8 都写一位小数, 取整后补 ".0" 反而更啰嗦,
        // 所以只在整数时丢掉小数点.
        // `!(km > 0)` 而不是 `km <= 0`: 后者放不过 undefined, undefined.toFixed 是
        // TypeError, 整行的副标题就没了 (10-22 巡检真机报过).
        if (!(km > 0)) return "0"
        return (km === Math.round(km)) ? String(Math.round(km)) : km.toFixed(1)
    }

    function rebuild() {
        var bucket = ({})
        var order = []
        var shown = 0
        for (var i = 0; i < library.length; ++i) {
            var r = library[i]
            var d = Number(r.difficulty) || 1
            if (maxDifficulty > 0 && d > maxDifficulty) continue
            var p = String(r.province || "未标注")
            if (province !== "" && p !== province) continue
            if (month > 0 && !hasMonth(r.bestSeason, month)) continue
            if (!bucket[p]) { bucket[p] = []; order.push(p) }
            bucket[p].push({
                kind: "item",
                id: String(r.id || ""),
                name: String(r.name || "未命名路线"),
                difficulty: d,
                km: Number(r.distanceKm) || 0,
                days: Number(r.daysNeeded) || 1,
                nature: String(r.routeNature || ""),
                wild: r.isWild === true,
                plate: CommonOptions.plateCode("RT", String(r.id || "")),
                tone: CommonOptions.difficultyColor(d),
                // head 那一支的字段: delegate 是一个 Item 里两个 RowLayout,
                // `visible: false` 不阻止绑定求值, 缺了就报 Unable to assign [undefined].
                label: "", count: 0
            })
            shown++
        }

        order.sort(function (a, b) { return a < b ? -1 : (a > b ? 1 : 0) })
        var out = []
        for (var g = 0; g < order.length; ++g) {
            var key = order[g]
            var members = bucket[key]
            // 组内按编号排, 目录序才稳定 (getAdvanced 遍历 QHash, 原始序每次启动都可能变)
            members.sort(function (a, b) { return a.plate < b.plate ? -1 : (a.plate > b.plate ? 1 : 0) })
            out.push({
                kind: "head", label: key, count: members.length,
                id: "", name: "", plate: "", difficulty: 0, km: 0, days: 0,
                nature: "", wild: false, tone: CommonOptions.colorInk3
            })
            for (var m = 0; m < members.length; ++m) out.push(members[m])
        }
        shownCount = shown
        rows = out
    }

    function resetFilters() {
        routeListPage.maxDifficulty = 0
        routeListPage.province = ""
        routeListPage.month = 0
    }

    // 读数行: 有筛选时先报"现 N 条", 再报库的覆盖面.
    readonly property string statusLine: {
        if (libCount === 0) return "路线数据尚未载入 · 检查 assets/data/routes.json"
        var filtering = (maxDifficulty > 0 || province !== "" || month > 0)
        var t = filtering ? ("现 " + shownCount + " / " + libCount + " 条")
                          : (libCount + " 条")
        t += " · " + provinceTotal + " 省 · 难度 "
          + (diffLo === diffHi ? diffLo : diffLo + "~" + diffHi)
        if (province !== "") t += " · " + province
        if (maxDifficulty > 0) t += " · " + maxDifficulty + " 星及以下"
        if (month > 0) t += " · " + month + " 月"
        if (hiddenCount > 0) t += " · 另有 " + hiddenCount + " 条不推荐未列"
        return t
    }

    Component.onCompleted: {
        loadLibrary()
        rebuild()
    }
    Connections {
        target: routeService
        function onDataChanged() {
            routeListPage.loadLibrary()
            routeListPage.rebuild()
        }
    }
    onMaxDifficultyChanged: rebuild()
    onProvinceChanged: rebuild()
    onMonthChanged: rebuild()

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
                    text: "路线 · 步道索引"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: "徒步路线"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: routeListPage.statusLine
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
                    onClicked: routeListPage.goBack()
                }
            }
        }

        // --- 筛选卡 ---
        Card {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            spacing: styles.spSm

            // 难度 6 枚 chip 压成一行: 每枚 Layout.fillWidth, 于是宽度均分、不换行,
            // 省掉 Flow 那种两行 chip 占掉的 ~40px (列表才是这一页的主角).
            RowLayout {
                Layout.fillWidth: true
                spacing: styles.spXs

                Repeater {
                    model: [0, 1, 2, 3, 4, 5]
                    delegate: Chip {
                        required property int modelData
                        Layout.fillWidth: true
                        text: modelData === 0 ? "全部" : (modelData + " 星")
                        // 选中那枚染难度色, 与行左的 3px 条 / 难度梯同源;
                        // 未选中的保持灰面, 不然六枚全彩等于没有指示.
                        checked: routeListPage.maxDifficulty === modelData
                        accent: modelData === 0 ? CommonOptions.colorAccent
                                                : CommonOptions.difficultyColor(modelData)
                        textSize: styles.fsSm
                        onClicked: routeListPage.maxDifficulty =
                                   (routeListPage.maxDifficulty === modelData) ? 0 : modelData
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "选难度 = 该星及以下 · 再点一次取消"
                font.pixelSize: styles.fsXs
                color: CommonOptions.colorInk3
                elide: Text.ElideRight
            }

            FilterRow {
                Layout.fillWidth: true
                label: "省份"
                comboModel: routeListPage.provinceChoices
                comboCurrentIndex: {
                    if (routeListPage.province === "") return 0
                    var i = routeListPage.provinceChoices.indexOf(routeListPage.province)
                    return i > 0 ? i : 0
                }
                onComboActivated: (idx, value) => {
                    routeListPage.province = idx === 0 ? "" : String(value)
                }
            }

            FilterRow {
                Layout.fillWidth: true
                label: "月份"
                comboModel: CommonOptions.monthOptions()
                comboTextRole: "label"
                comboValueRole: "value"
                comboCurrentIndex: {
                    var opts = CommonOptions.monthOptions()
                    for (var i = 0; i < opts.length; ++i) {
                        if (opts[i].value === routeListPage.month) return i
                    }
                    return 0
                }
                onComboActivated: (idx, value) => { routeListPage.month = value }
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
                id: routeList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: routeListPage.rows

                delegate: Item {
                    required property var modelData
                    width: routeList.width
                    height: modelData.kind === "head" ? 30 : styles.touchMin

                    // 分组标题 (省份). 这一页的分组轴没有颜色语义 —— 省份不是危险也不是
                    // 植被, 所以左条走中性灰, 不借用难度色假装信息.
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
                            color: CommonOptions.colorTextMuted
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: modelData.count + " 条路线"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                        }
                    }

                    // 条目行
                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
                        spacing: 9
                        visible: modelData.kind === "item"

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
                                text: modelData.name
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsMd
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: routeListPage.formatKm(modelData.km) + " km · "
                                      + modelData.days + " 天"
                                      + (modelData.nature ? " · " + modelData.nature : "")
                                      + (modelData.wild ? " · 野线" : "")
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                                elide: Text.ElideRight
                            }
                        }
                        // 难度梯 5 格: 实心格数 = 该条难度, 颜色与左侧 3px 条同源.
                        Ladder {
                            Layout.alignment: Qt.AlignVCenter
                            value: modelData.difficulty
                            tone: CommonOptions.difficultyColor(modelData.difficulty)
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
                        visible: modelData.kind === "item"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: styles.lineHair
                        color: CommonOptions.colorRuleSoft
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: modelData.kind === "item"
                        cursorShape: Qt.PointingHandCursor
                        onClicked: routeListPage.navigateTo("RouteDetailPage",
                                                            { routeId: modelData.id })
                    }
                }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: routeListPage.rows.length === 0
                iconName: "map"
                text: routeListPage.libCount === 0 ? "路线库没有载入" : "这一档筛不出路线"
                hint: routeListPage.libCount === 0
                      ? "重装 APK 或检查 assets/data/routes.json 是否打进包里"
                      : "换个省份、放宽难度或换个月份 —— 适宜季节是按整月匹配的"
                actionText: routeListPage.libCount === 0 ? "重新载入" : "重置筛选"
                onActionTriggered: {
                    if (routeListPage.libCount === 0) {
                        routeListPage.loadLibrary()
                        routeListPage.rebuild()
                    } else {
                        routeListPage.resetFilters()
                    }
                }
            }
        }
    }
}
