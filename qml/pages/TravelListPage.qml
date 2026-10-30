/**
 * @file TravelListPage.qml
 * @brief 自驾游路线目录 (2026-10-20 v9 F1 母版, 丁骨架二级页)
 *
 * 入口: 侧边抽屉 "car" (Main.qml: window.navBus.navigateTo("TravelListPage", {})).
 *       这是抽屉推上来的二级页 → 有右上 26px 方角返回, 没有底部导航带.
 *
 * 版式逐块对应已评审的 mock (F1 目录母版, 与徒步路线目录同一套骨架):
 *   标题条  54px 三行 (拉丁微标签 / 页名 / 读数行) + 右上 26px 方角返回 (热区外扩 9px).
 *   筛选卡  两行各 5 枚 chip (天数区间 / 里程区间) + 省份下拉 + 月份下拉.
 *   目录    ListView 混排 head/item: head = 3px 中性条 + 分组名 + "N 条路线";
 *           item = 3px 紫条 + 编号 + 名称/副行 + 最高海拔 + chevron, 只有 item 有 1px 组线.
 *
 * 这一版换掉的东西与原因:
 *   - Hero + ListRow + ServiceListModel → 一次 getFiltered 拉全库再本地分桶.
 *     原因与 RouteListPage 一致: 每次动一个筛选就重跑一次服务调用, 而且 QHash 遍历序
 *     不稳, 目录次序会每次启动都变; 101 条一次拉完, 本地筛是即时的.
 *   - 删掉 resetFilters() 里那四句 filterRowXxx.comboBoxInstance.currentIndex = 0 ——
 *     那是隔着组件去捅别人的内部节点; 现在下拉框的当前项由 comboCurrentIndex 声明式
 *     反查, 状态只有一个来源 (province / month 这些字段本身).
 *   - "›" 手抄箭头换成 IconLabel chevron_right; 计数行不再手抄 "共 N 条路线",
 *     读数行同时报"筛出 / 全库 / 分组数 / 里程跨度".
 *
 * 不编读数 (规则 ①): 天数/里程/最高海拔/路面类型/适游季月份全部来自 travelService;
 *   分组用的是数据里的 province 原值 —— 9 条跨省环线写的就是 "四川/西藏" 这种串,
 *   不拆成两个组 (拆了会出现"同一条线在两个组里各出现一次"的假象).
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: travelListPage

    Styles { id: styles; visible: false }

    title: "自驾游"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 筛选状态 ==========================================================
    // 0 = 全部; 1..4 = 区间档 (与下面两行 chip 的 model 一一对应)
    property int daysBucket: 0
    property int kmBucket: 0
    property string province: ""   // "" = 全部
    property int month: 0          // 0 = 全部

    // === 数据 ==============================================================
    property var library: []
    property var rows: []
    property var provinceChoices: ["全部"]
    property int shownCount: 0
    property int provinceTotal: 0
    property int kmLo: 0
    property int kmHi: 0
    readonly property int libCount: library.length

    // 区间表: 下标 = chip 档位. 天数取闭区间 (数据是整数天), 里程取 [lo, hi)
    // —— 里程可能有小数 (服务层是 double), 闭区间会在 500 这种边界上两头都不落.
    // hi === 0 表示上不封顶.
    readonly property var dayRanges: [[0, 0], [1, 2], [3, 5], [6, 10], [11, 0]]
    readonly property var kmRanges: [[0, 0], [0, 500], [500, 1000], [1000, 2000], [2000, 0]]

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    // getFiltered 全给"不过滤"的参数 = 全库, 返回的是 Result 信封 {ok,value,error}
    // (2026-09-21 Phase 5 改的), 所以取 value.
    function loadLibrary() {
        if (!travelService) { library = []; return }
        var res = travelService.getFiltered("", 0, 0, 0, 0, 0)
        var fetched = (res && res.ok && res.value && res.value.length !== undefined)
                      ? res.value : []
        library = fetched

        var seen = ({})
        var lo = 0
        var hi = 0
        for (var i = 0; i < library.length; ++i) {
            var t = library[i]
            var p = String(t.province || "")
            if (p !== "") seen[p] = true
            var km = Math.round(Number(t.distanceKm) || 0)
            if (km <= 0) continue
            if (lo === 0 || km < lo) lo = km
            if (km > hi) hi = km
        }
        var keys = []
        for (var k in seen) keys.push(k)
        // 码位序 —— 与 C++ 侧 getAvailableProvinces() 的 std::sort 同一条序.
        keys.sort(function (a, b) { return a < b ? -1 : (a > b ? 1 : 0) })
        provinceChoices = ["全部"].concat(keys)
        provinceTotal = keys.length
        kmLo = lo
        kmHi = hi
    }

    // 数据里的适游季就是 "5月" 这种 token
    function hasMonth(seasons, m) {
        if (!seasons || seasons.length === undefined) return false
        var token = m + "月"
        for (var i = 0; i < seasons.length; ++i) {
            if (String(seasons[i]) === token) return true
        }
        return false
    }

    function formatKm(km) {
        // undefined 过不了 `km <= 0`, 但会一路走到 toFixed 抛 TypeError
        if (!(km > 0)) return "0"
        return (km === Math.round(km)) ? String(Math.round(km)) : km.toFixed(1)
    }

    // 0 表示"库里没这个数" —— 一旦选了区间档, 没有数的条目就不该混进来
    function inDays(d) {
        if (daysBucket === 0) return true
        if (d <= 0) return false
        var lo = dayRanges[daysBucket][0]
        var hi = dayRanges[daysBucket][1]
        return d >= lo && (hi <= 0 || d <= hi)
    }
    function inKm(km) {
        if (kmBucket === 0) return true
        if (km <= 0) return false
        var lo = kmRanges[kmBucket][0]
        var hi = kmRanges[kmBucket][1]
        return km >= lo && (hi <= 0 || km < hi)
    }

    function rebuild() {
        var bucket = ({})
        var order = []
        var shown = 0
        for (var i = 0; i < library.length; ++i) {
            var t = library[i]
            var p = String(t.province || "未标注")
            if (province !== "" && p !== province) continue
            if (month > 0 && !hasMonth(t.bestSeason, month)) continue
            var days = Number(t.days) || 0
            if (!inDays(days)) continue
            var km = Number(t.distanceKm) || 0
            if (!inKm(km)) continue
            if (!bucket[p]) { bucket[p] = []; order.push(p) }
            var sName = String(t.startName || t.startCity || "")
            var eName = String(t.endName || t.endCity || "")
            bucket[p].push({
                kind: "item",
                id: String(t.id || ""),
                name: String(t.name || "未命名路线"),
                km: km,
                days: days,
                alt: Number(t.maxAltitude) || 0,
                road: String(t.roadType || ""),
                // 起终点同名 = 环线 (数据里 88/101 是这种). 环线只写一处地名,
                // 写 "上海 → 上海" 会读成脏数据.
                loop: (sName !== "" && sName === eName),
                loopAt: sName,
                fromTo: [sName, eName]
                        .filter(function (s) { return !!(s && String(s).length) })
                        .join(" → ") || "起终点未标注",
                plate: CommonOptions.plateCode("TV", String(t.id || "")),
                // head 那一支的字段: delegate 一个 Item 里两个 RowLayout,
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
            // 组内按编号排, 目录序才稳定 (服务层遍历 QHash, 原始序每次启动都可能变)
            members.sort(function (a, b) { return a.plate < b.plate ? -1 : (a.plate > b.plate ? 1 : 0) })
            out.push({
                kind: "head", label: key, count: members.length,
                id: "", name: "", plate: "", km: 0, days: 0, alt: 0, road: "",
                loop: false, loopAt: "", fromTo: ""
            })
            for (var m = 0; m < members.length; ++m) out.push(members[m])
        }
        shownCount = shown
        rows = out
    }

    function resetFilters() {
        travelListPage.daysBucket = 0
        travelListPage.kmBucket = 0
        travelListPage.province = ""
        travelListPage.month = 0
    }

    // 读数行: 有筛选时先报"现 N 条", 再报库的覆盖面.
    readonly property string statusLine: {
        if (libCount === 0) return "自驾数据尚未载入 · 检查 assets/data/travel.json"
        var filtering = (daysBucket > 0 || kmBucket > 0 || province !== "" || month > 0)
        var t = filtering ? ("现 " + shownCount + " / " + libCount + " 条")
                          : (libCount + " 条")
        t += " · " + provinceTotal + " 组 · 里程 "
          + (kmLo === kmHi ? kmHi : kmLo + "~" + kmHi) + " km"
        if (province !== "") t += " · " + province
        if (daysBucket > 0) t += " · " + daysBucketLabel(daysBucket)
        if (kmBucket > 0) t += " · " + kmBucketLabel(kmBucket)
        if (month > 0) t += " · " + month + " 月"
        return t
    }

    // 档位标签只有一处定义: chip 文案与读数行共用, 免得两处写歪
    function daysBucketLabel(n) {
        if (n === 1) return "1-2 天"
        if (n === 2) return "3-5 天"
        if (n === 3) return "6-10 天"
        return "10 天以上"
    }
    function kmBucketLabel(n) {
        if (n === 1) return "500 km 内"
        if (n === 2) return "500-1000 km"
        if (n === 3) return "1000-2000 km"
        return "2000 km 以上"
    }

    Component.onCompleted: {
        loadLibrary()
        rebuild()
    }
    Connections {
        target: travelService
        function onDataChanged() {
            travelListPage.loadLibrary()
            travelListPage.rebuild()
        }
    }
    onDaysBucketChanged: rebuild()
    onKmBucketChanged: rebuild()
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
                    text: "自驾路线索引"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: "自驾游"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: travelListPage.statusLine
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
                    onClicked: travelListPage.goBack()
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

            // 天数 5 枚 chip 压成一行: 每枚 Layout.fillWidth → 宽度均分、不换行.
            RowLayout {
                Layout.fillWidth: true
                spacing: styles.spXs
                Repeater {
                    model: [0, 1, 2, 3, 4]
                    delegate: Chip {
                        required property int modelData
                        Layout.fillWidth: true
                        text: modelData === 0 ? "全部" : travelListPage.daysBucketLabel(modelData)
                        checked: travelListPage.daysBucket === modelData
                        accent: CommonOptions.colorPlum
                        textSize: styles.fsXs
                        onClicked: travelListPage.daysBucket =
                                   (travelListPage.daysBucket === modelData) ? 0 : modelData
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: "第一行按天数区间 · 再点一次取消"
                font.pixelSize: styles.fsXs
                color: CommonOptions.colorInk3
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: styles.spXs
                Repeater {
                    model: [0, 1, 2, 3, 4]
                    delegate: Chip {
                        required property int modelData
                        Layout.fillWidth: true
                        text: modelData === 0 ? "全部" : travelListPage.kmBucketLabel(modelData)
                        checked: travelListPage.kmBucket === modelData
                        accent: CommonOptions.colorPlum
                        textSize: styles.fsXs
                        onClicked: travelListPage.kmBucket =
                                   (travelListPage.kmBucket === modelData) ? 0 : modelData
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: "第二行按里程区间 (单位 km)"
                font.pixelSize: styles.fsXs
                color: CommonOptions.colorInk3
                elide: Text.ElideRight
            }

            FilterRow {
                Layout.fillWidth: true
                label: "省份"
                comboModel: travelListPage.provinceChoices
                comboCurrentIndex: {
                    if (travelListPage.province === "") return 0
                    var i = travelListPage.provinceChoices.indexOf(travelListPage.province)
                    return i > 0 ? i : 0
                }
                onComboActivated: (idx, value) => {
                    travelListPage.province = idx === 0 ? "" : String(value)
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
                        if (opts[i].value === travelListPage.month) return i
                    }
                    return 0
                }
                onComboActivated: (idx, value) => { travelListPage.month = value }
            }

            OutlineButton {
                Layout.alignment: Qt.AlignRight
                text: "重置筛选"
                tone: CommonOptions.colorTextMuted
                textSize: styles.fsXs
                onClicked: travelListPage.resetFilters()
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
                id: driveList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: travelListPage.rows

                delegate: Item {
                    required property var modelData
                    width: driveList.width
                    height: modelData.kind === "head" ? 30 : styles.touchMin

                    // 分组标题 (省份原值). 分组轴没有颜色语义 → 左条走中性灰.
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

                        // 紫 = 地物图例里的"路线"色, 与地图上的自驾线同源
                        Rectangle {
                            Layout.fillHeight: true
                            Layout.preferredWidth: styles.lineAccent
                            color: CommonOptions.colorPlum
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
                                text: (modelData.loop ? "环线 · " + modelData.loopAt
                                                      : modelData.fromTo)
                                      + " · " + travelListPage.formatKm(modelData.km) + " km"
                                      + (modelData.road ? " · " + modelData.road : "")
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                                elide: Text.ElideRight
                            }
                        }
                        // 最高海拔: 数字走等宽, 单位单独一个节点 (汉字不进 mono)
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0
                            visible: modelData.alt > 0
                            Text {
                                text: String(modelData.alt)
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsSm
                                color: CommonOptions.colorText
                            }
                            Text {
                                text: "米"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
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
                        onClicked: travelListPage.navigateTo("TravelDetailPage",
                                                            { travelId: modelData.id })
                    }
                }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: travelListPage.rows.length === 0
                iconName: "car"
                text: travelListPage.libCount === 0 ? "自驾数据没有载入" : "这一档筛不出路线"
                hint: travelListPage.libCount === 0
                      ? "重装 APK 或检查 assets/data/travel.json 是否打进包里"
                      : "换个省份、放宽天数或里程区间 —— 适游季是按整月匹配的"
                actionText: travelListPage.libCount === 0 ? "重新载入" : "重置筛选"
                onActionTriggered: {
                    if (travelListPage.libCount === 0) {
                        travelListPage.loadLibrary()
                        travelListPage.rebuild()
                    } else {
                        travelListPage.resetFilters()
                    }
                }
            }
        }
    }
}
