/**
 * @file SearchTab.qml
 * @brief 查找 Tab: 按城市/名称 + 类型/难度/时长 筛路线, 或按地名找起终点 (2026-10-27 #132)
 *
 * 数据源: 路线模式 RouteService.search(keyword) + getByProvince + getByDifficulty;
 *        地点模式 RouteService.searchPlaces(keyword) + TravelService.searchPlaces(keyword).
 *
 * 2026-10-19 整体改版 (props / signal / doSearch 语义不变):
 *   - 尺寸字号全换 Styles token (原 12 / 8 / 6 / 4 / 80 / 56 / 4 / 2 / 16 / 14 / 11 裸数字).
 *   - 标题 → SectionTitle, 结果行 → ListRow, 搜索按钮 → PrimaryButton,
 *     空结果 → EmptyState, 省份下拉 → FilterRow(combo 模式).
 *   - 对比度修复: "查找路线"标题与结果行标题原用 colorTextOnAccent 白字画在
 *     sheet 的 colorSurface / colorSurfaceDim 深灰底上 → colorText.
 *   - routeService 是上下文属性, 拆解构前可能为 null → 取数全部加守卫.
 *   - TextField / SpinBox 补上 token 尺寸与 colorText 前景, 不再吃 Material 默认值.
 * 2026-10-23 巡检 (#110 A11/A12):
 *   - A11: 难度并排的两个 Material SpinBox 在真机看起来像两组坏掉的 [− 1 +] [− 5 +],
 *     换成一行"两端 ± 步进 + 中间 1 ~ 5 合并读数", min>max 改为钳制顶推, 不再静默画空.
 *   - A12: 空态补"是否搜过"三态文案 (没搜过不再谎称"还没有搜索结果"), 并给宿主抽屉
 *     底部「标注这里」让出 btnH 级底边距, 空态改在可用区内垂直居中.
 * 2026-10-27 #132: 「查找」加路线 / 地点两种查法 (C++ 侧 searchPlaces 上一轮已就位).
 *   - 地点模式合并 RouteService.searchPlaces() + TravelService.searchPlaces():
 *     两边同一套打分 (POI 名 3 / 线路名 2 / 省市山 1) 与同一套键
 *     (id/name/routeId/routeName/side/lat/lon/address/region), 所以能直接并排渲染,
 *     只需按 name + 经纬度去重.
 *   - 地点模式只吃关键词, 没有省/难度可筛 → 那两行整体隐藏. 留着最坏: 用户把难度
 *     区间调了半天点搜索, 结果纹丝不动, 看着像搜索坏了.
 *   - 点地点行只把地图挪过去 (placeSelected → MapPage.focusTarget), 不叠加路线 ——
 *     叠加是路线模式的动作, 地点行代表的是某条线的一个端点.
 * 2026-10-28 #156 按两步路工作台改版:
 *   - SectionTitle + 独立 TextField + 居中通栏「搜索」→ SheetPanelHead 一行 (标题 +
 *     条数 + 内嵌搜索框 + ✕ 收起), 「搜索 / 清空条件 / 收起」下移到底部动作带.
 *     A12 那条"给宿主「标注这里」让出 btnH 底边距"的补丁随通栏按钮一起消失 ——
 *     按钮不再常驻抽屉底部, 让位高度自然不需要.
 *   - 关键词仍然只在点搜索/回车时提交进 root.keyword (和改版前一致): 输入框里
 *     打一半的字就触发查询, 会把列表刷成用户没打算看的中间态.
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

// delegate 里读外层 id (list / root): qmlcachegen 静态编译下没有 Bound 语义会在
// 真机静默 ReferenceError.
pragma ComponentBehavior: Bound

Item {
    id: root

    // 2026-10-16 整体改版: 尺寸/间距 token 实例 (Wave 3 逐页替换用)
    Styles { id: styles; visible: false }

    property string keyword: ""
    property string province: ""
    property int minDifficulty: 1
    property int maxDifficulty: 5
    property int maxDays: 99
    property var results: []
    property var provinces: []
    // 由宿主 (MapBottomSheet ← MapPage) 传进来的已选路线.
    // 不能在 delegate 里直接写 mapPage.selectedRouteIds: id 只在本文件内可见,
    // 跨文件引用恒为 undefined → 每次生成行都抛 ReferenceError, 列表整块空掉.
    property var selectedRouteIds: []
    // 2026-10-23 巡检 (#110 A12): 空态文案要区分"还没搜过"与"搜过但 0 条" ——
    // 抽屉刚打开就写「还没有搜索结果」是假陈述, 得有个"真的发起过查询没有"的状态.
    property bool _searched: false
    // 2026-10-27 #132: "route" = 按省/难度区间筛路线 (本文件原来的唯一行为);
    // "place" = 按地名找路线/自驾的起终点. 两模式共用 results 这一个列表模型,
    // 由 mode 决定谁去填它、每行读哪些键.
    property string mode: "route"

    signal routeSelected(string routeId, var route)
    // 2026-10-27 #132: 地点行上抛整条记录 (含 lat/lon), 宿主只要坐标就够定位了,
    // 但透传整个对象比在抽屉里猜字段稳妥 (与 targetClicked(var target) 同一口径).
    signal placeSelected(var place)
    // 2026-10-28 #156: 面板头 ✕ / 动作带「收起」只报意图, 折叠态归宿主抽屉.
    signal foldRequested()

    // 抽屉展开态按这一面报的高度来 (见 MapBottomSheet._expandedHeight). 列表面要滚动空间.
    readonly property int preferredSheetHeight: styles.sheetExpH

    // 底部动作带: 搜索 = 唯一主行动; 清空条件把省/难度/关键词一起收回默认,
    // 原来这一屏没有退出口, 调坏的区间只能靠刷新页面重来.
    // 图标只能取 IconLabel._iconMap 里有的码位 (restart_alt 字体没有 → 空白格).
    readonly property var _bandActions: [
        { key: "search", icon: "search", label: "搜索", tone: "prime" },
        { key: "reset",  icon: "delete", label: "清空条件" },
        { key: "fold",   icon: "expand_more", label: "收起" }
    ]

    function _onBandAction(key) {
        if (key === "search") root.commitAndSearch()
        else if (key === "reset") root.resetFilters()
        else if (key === "fold") root.foldRequested()
    }

    // 输入框里的字 → root.keyword → 查询. 只有这一条路径提交关键词,
    // 所以打一半不会边打边刷列表.
    function commitAndSearch() {
        root.keyword = String(panelHead.searchText || "")
        root.doSearch()
    }

    function resetFilters() {
        panelHead.searchText = ""
        root.keyword = ""
        root.province = ""
        root.minDifficulty = 1
        root.maxDifficulty = 5
        root.results = []
        root._searched = false
    }

    Component.onCompleted: {
        if (routeService)
            provinces = routeService.getAvailableProvinces()
    }

    // 切模式丢掉上一批结果: 两模式的行结构不一样 (路线有 difficulty/distanceKm,
    // 地点有 side/routeName), 留着等于用另一套文案去渲染已经不对的数据.
    // 已经有关键词时直接按新模式重查, 省得用户再点一次搜索.
    function setMode(m) {
        if (root.mode === m) return
        root.mode = m
        root.results = []
        root._searched = false
        if (root.keyword.length > 0)
            root.doSearch()
    }

    function doSearch() {
        // 2026-10-27 #132: 地点模式. 两个服务都是上下文属性, 拆解构前可能为 null,
        // 但只要有一个能用就算真的发起过查询 (_searched 的语义).
        if (root.mode === "place") {
            if (!routeService && !travelService) return
            root._searched = true
            results = root.mergePlaces()
            return
        }
        if (!routeService) return
        // 2026-10-23 巡检 (#110 A12): 守卫之后置位 —— routeService 为空时这次
        // 点击根本没查到东西, 不该谎称"搜过了".
        root._searched = true
        if (keyword && keyword.length > 0) {
            var rs = routeService.search(keyword) || []
            // 2026-10-28 问题4 (用户: "不能再地图上搜索城市"): 城市名不是路线名。
            //   输「济南」时路线模式恒 0 条 (search() 只比 name/alias), 用户看到的
            //   就是"地图搜不到城市" —— 而济南是 35 条山东路线的 city 字段,
            //   searchPlaces() 按省/市/区/山给 1 分, 一直都在库里。空表时拿同一个关键词
            //   转地点模式重查; mode 真的翻过去 (上面两枚 chip 跟着亮), 让用户看得见
            //   这一批是地名命中而不是线路名命中。翻完还是空才落到下面的空态。
            if (rs.length === 0) {
                var places = root.mergePlaces()
                if (places.length > 0) {
                    root.mode = "place"
                    root.results = places
                    return
                }
            }
            results = rs
        } else if (province && province.length > 0) {
            results = routeService.getByProvinceAndDifficulty(
                province, minDifficulty, maxDifficulty)
        } else {
            results = routeService.getByDifficulty(minDifficulty, maxDifficulty)
        }
    }

    // 2026-10-27 #132: 合并两个来源的地点命中 (徒步路线起终点 + 自驾游起终点).
    // 去重键带上经纬度而不是只用 name —— 数据里同名 POI 成批出现 (749 条路线里
    // 189 条起终点同名), 只按名字去重会把两座不同的"白马雪山"并成一条.
    // toFixed(4) ≈ 11 m: 够宽, 不至于让同一条线在两个库里的起点因末位小数不同而
    // 重复; 也够窄, 不会把真挨在一起的两个地名吃掉.
    function mergePlaces() {
        var merged = []
        var seen = ({})
        var sources = []
        if (routeService) sources.push(routeService.searchPlaces(root.keyword, 40))
        if (travelService) sources.push(travelService.searchPlaces(root.keyword, 40))
        for (var i = 0; i < sources.length; ++i) {
            var src = sources[i]
            if (!src) continue
            for (var j = 0; j < src.length; ++j) {
                var p = src[j]
                var key = String(p.name || "") + "|"
                        + Number(p.lat).toFixed(4) + "|" + Number(p.lon).toFixed(4)
                if (seen[key]) continue
                seen[key] = true
                merged.push(p)
            }
        }
        return merged
    }

    // 2026-10-23 巡检 (#110 A11): 区间自洽靠钳制, 不靠"用户别把下限调过头".
    // 原来两个 SpinBox 各写各的 minDifficulty/maxDifficulty, 互不约束: min>max 时
    // getByDifficulty 的过滤区间为空, 点搜索后整块列表静默画空, 看着像功能坏了.
    // 现在抬下限会把上限一起顶上去、压上限会把下限一起带下来, 读数永远是合法区间.
    function bumpMin(delta) {
        var v = Math.max(1, Math.min(5, root.minDifficulty + delta))
        root.minDifficulty = v
        if (root.maxDifficulty < v)
            root.maxDifficulty = v
    }
    function bumpMax(delta) {
        var v = Math.max(1, Math.min(5, root.maxDifficulty + delta))
        root.maxDifficulty = v
        if (root.minDifficulty > v)
            root.minDifficulty = v
    }

    // 副标题口径对齐 NearbyTab(目标): 省 · 全长.
    // 原来写的是 province + " · " + city —— search()/getByProvinceAndDifficulty()/
    // getByDifficulty() 三个返回里根本没有 city 这个键 (RouteService.cpp 手搓的
    // QVariantMap 只有 id/name/province/difficulty/distanceKm), 拼出来永远只剩一个点.
    // 用 filter+join 而不是硬拼: 省为空的条目不会留个孤零零的 "·".
    function subOf(r) {
        var parts = []
        var p = String(r.province || "")
        if (p.length > 0) parts.push(p)
        var km = Number(r.distanceKm) || 0
        if (km > 0) parts.push("全长 " + CommonOptions.formatDistance(km))
        return parts.join(" · ")
    }

    // 2026-10-27 #132: 地点行的副标题. region 已经在 C++ 侧拼成 "省 · 市 · 山"
    // (去空去重), 这里只再加归属路线名 —— 同名 POI 成批出现时"是哪条线的起点"
    // 是唯一能把两行分开的线索.
    function placeSubOf(p) {
        var out = []
        var rg = String(p.region || "")
        if (rg.length > 0) out.push(rg)
        var rn = String(p.routeName || "")
        if (rn.length > 0) out.push(rn)
        return out.join(" · ")
    }

    // 2026-10-27 #132: 空态文案按模式分档. 地点模式比路线模式多一档 "搜过但没填
    // 关键词" —— searchPlaces 空关键词恒返回空表, 这时写"没有匹配的地点"是假陈述
    // (压根没查询过), 而且"重新搜索"点了还是空, 所以那一格不给动作按钮.
    function emptyText() {
        if (root.mode === "place") {
            if (!root._searched) return "按地名找起点、终点或自驾目的地"
            if (root.keyword.length === 0) return "先输入地名或关键词"
            return "没有匹配的地点"
        }
        return root._searched ? "没有匹配的路线" : "按城市、关键词或难度区间找路线"
    }

    function emptyHint() {
        if (root.mode === "place") {
            if (!root._searched)
                return "在上方输入地名、城市或山名再点搜索; 点结果行把地图挪过去"
            if (root.keyword.length === 0)
                return "城市 / 山名 / POI 名都行, 例如「泰山」「丽江」"
            return "换个地名或城市写法; 想看整条线路请切回「路线」用省份与难度区间筛"
        }
        return root._searched
              ? "换个城市或关键词, 或放宽上方难度区间后重新搜索"
              : "在上方输入关键词, 或选省份并用难度 1 ~ 5 区间筛选, 再点搜索"
    }

    function emptyActionText() {
        if (root.mode === "place")
            return (root._searched && root.keyword.length > 0) ? "重新搜索" : ""
        return root._searched ? "重新搜索" : ""
    }

    // 2026-10-23 巡检 (#110 A11): 难度区间行共用的 ± 方块按钮 (样式对齐 FilterRow
    // 的 stepper 模式). 内联组件看不到外层 styles id —— MapBottomSheet 的 SheetTab
    // 注释里已经踩过这个坑, 所以自带一份 Styles.
    component RangeStep: Rectangle {
        id: step
        Styles { id: stepStyles; visible: false }
        property string iconName: "add"
        property bool stepEnabled: true
        signal stepClicked()
        Layout.preferredWidth: stepStyles.rowHSm
        Layout.preferredHeight: stepStyles.rowHSm
        radius: stepStyles.rMd
        color: step.stepEnabled ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
        border.color: CommonOptions.colorDivider
        border.width: stepStyles.lineHair
        IconLabel {
            anchors.centerIn: parent
            name: step.iconName
            size: stepStyles.icMd
            tintColor: step.stepEnabled ? CommonOptions.colorText : CommonOptions.colorTextDisabled
        }
        MouseArea {
            anchors.fill: parent
            enabled: step.stepEnabled
            onClicked: step.stepClicked()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: styles.pageMargin
        anchors.rightMargin: styles.pageMargin
        anchors.topMargin: styles.spXs
        anchors.bottomMargin: styles.spSm
        spacing: styles.spSm

        // 2026-10-28 #156: SectionTitle + 独立搜索框合成一行 (标题 + 条数 + 输入 + ✕).
        //   原来这三块各占一行, 480 高的抽屉里结果列表只剩 3 行半 (pass9 ④).
        //   读数只在真的查过之后才出现 —— 抽屉刚打开就写 "0 条" 是假读数.
        SheetPanelHead {
            id: panelHead
            Layout.fillWidth: true
            iconName: "search"
            title: root.mode === "place" ? "查找地点" : "查找路线"
            trailing: root._searched ? root.results.length + " 条" : ""
            searchPlaceholder: root.mode === "place" ? "地名/城市/山名" : "城市/路线名/关键词"
            onFoldRequested: root.foldRequested()
            onSearchSubmitted: root.commitAndSearch()
        }

        // 2026-10-27 #132: 两种查法的数据源与可筛项完全不同 (路线吃省 + 难度区间,
        // 地点只吃关键词), 所以做成模式切换, 而不是在同一个表单里再塞一行筛选.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: styles.chipH
            spacing: styles.spSm

            Chip {
                text: "路线"
                checked: root.mode === "route"
                onClicked: root.setMode("route")
            }
            Chip {
                text: "地点"
                checked: root.mode === "place"
                onClicked: root.setMode("place")
            }
            // 胶囊按自身隐式宽靠左, 后面这块空白负责吃掉余量 (否则 RowLayout 会把
            // 两枚胶囊往两端散开).
            Item { Layout.fillWidth: true }
        }

        FilterRow {
            Layout.fillWidth: true
            // 2026-10-27 #132: 地点模式只吃关键词 (searchPlaces 没有省/难度参数),
            // 这两行整体隐藏; 普通 visible 就能让 ColumnLayout 收起这一格
            // (Qt 6.7 的 Layout 附加属性里没有 Layout.visible).
            visible: root.mode === "route"
            label: "省/市"
            labelWidth: styles.icBox
            // 2026-09-14 修: routeService.getAvailableProvinces() 已在
            // C++ 端 prepend "全部", 不要重复加 "(全部)"
            comboModel: root.provinces
            // 2026-11-03 (L11): 下拉显示必须从 root.province 反查, 不能让控件内部的
            //   currentIndex 当第二条真相来源 (真机 F1: 列表按状态筛了, 框还写着「全部」).
            //   provinces[0] 是 C++ 端 prepend 的「全部」, 对应 province === "".
            // 2026-11-04 (F1-2 / 定律 L14): 反查原来写 `Array.isArray(root.provinces) ? indexOf : -1`,
            //   而 root.provinces 来自 routeService.getAvailableProvinces() —— QStringList 到 QML
            //   是包装列表, Array.isArray 恒 false, 所以这支**永远 -1**, 选完省份框永远回显「全部」.
            //   包装列表自己带 indexOf (容器实测 typeofIndexOf=function), 所以判"有没有这个方法",
            //   不判"是不是 JS 数组".
            comboCurrentIndex: {
                var m = root.provinces
                var i = (m && typeof m.indexOf === 'function') ? m.indexOf(root.province) : -1
                return i > 0 ? i : 0
            }
            onComboActivated: (index, value) => {
                root.province = (index === 0) ? "" : value
            }
        }

        // 2026-10-23 巡检 (#110 A11): 这里原来是两个并排的 Material SpinBox
        //   (minSpin→root.minDifficulty / maxSpin→root.maxDifficulty), 中间只有一个
        //   孤零零的 "—". 真机上 SpinBox 自身就画成 [− 1 +], 于是整行读起来像两组
        //   坏掉/重复的步进器, 完全看不出它们是同一条难度区间的下限与上限
        //   (doSearch() 里 getByProvinceAndDifficulty/getByDifficulty 两个都在用).
        //   改成: 两端各一组 ±, 中间只剩合并读数 "1 ~ 5", 区间语义一眼可读;
        //   越过对侧端点由 bumpMin/bumpMax 钳制顶推, 不再画空列表.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: styles.rowHSm
            visible: root.mode === "route"   // 同上: 地点模式没有难度可筛
            spacing: styles.spXs

            Text {
                text: "难度"
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsSm
                Layout.preferredWidth: styles.icBoxSm
            }
            RangeStep {
                iconName: "remove"
                stepEnabled: root.minDifficulty > 1
                onStepClicked: root.bumpMin(-1)
            }
            RangeStep {
                iconName: "add"
                stepEnabled: root.minDifficulty < 5
                onStepClicked: root.bumpMin(1)
            }
            Text {
                // 纯 ASCII 数字读数才进 monoFont (绑了等宽的 Text 不许混汉字, 见 Styles.qml)
                text: root.minDifficulty + " ~ " + root.maxDifficulty
                font.family: styles.monoFont
                font.pixelSize: styles.fsMd
                font.bold: true
                color: CommonOptions.colorText
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            RangeStep {
                iconName: "remove"
                stepEnabled: root.maxDifficulty > 1
                onStepClicked: root.bumpMax(-1)
            }
            RangeStep {
                iconName: "add"
                stepEnabled: root.maxDifficulty < 5
                onStepClicked: root.bumpMax(1)
            }
        }

        // 2026-10-23 巡检 (#110 A12): 列表与空态包进同一块"可用区".
        //   空态原来跟着 ColumnLayout 排在搜索按钮正下方, 底部又压着宿主的
        //   「标注这里」按钮; 现在这块 Item 吃掉剩余高度, EmptyState 垂直居中在
        //   这块可用区, 而不是贴顶或被压底.
        //   2026-10-28 #156: 通栏「搜索」那一行删掉了 —— 搜索动作进底部动作带,
        //   这一格直接吃满剩余高度, 不用再为常驻按钮让底边距.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                // 2026-10-23 巡检 (#104 布局): 空列表照样吃满整块高度, 把 EmptyState
                //   顶到 sheet 最底、中间一片死白. 空时隐藏, 让位给居中的空态.
                visible: !!root.results && root.results.length > 0
                spacing: styles.spXs
                clip: true
                model: root.results

                delegate: ListRow {
                    required property var modelData

                    // 2026-09-15: 选中路线高亮 — 沿用原先从 mapPage.selectedRouteIds
                    // 反查的绑定式写法 (选中状态变化会即时刷新行底色)
                    // 2026-10-27 #132: 地点行的 id 是 "路线id#start/#end", 库里存的
                    // 是纯路线 id, 所以按 routeId 反查 —— 高亮表达的是"这条线已经画上".
                    readonly property bool picked: root.selectedRouteIds.indexOf(
                        root.mode === "place" ? (modelData.routeId || "") : modelData.id) >= 0

                    width: list.width
                    dense: true
                    title: modelData.name || "(未命名)"
                    titleColor: CommonOptions.colorText
                    subtitle: root.mode === "place" ? root.placeSubOf(modelData)
                                                    : root.subOf(modelData)
                    // 地点行右侧写"起点/终点" (这条线哪一端), 路线行右侧写难度档
                    value: root.mode === "place" ? (modelData.side || "")
                                                 : CommonOptions.difficultyLabel(modelData.difficulty || 1)
                    bg: picked ? CommonOptions.colorSurfaceDim : CommonOptions.colorSurface
                    // 2026-10-19: ListRow 的 value 文字吃 accent 色. 这里不能再用
                    // difficultyColor() / colorAccent —— 黄绿橙蓝那几档落在 colorSurface
                    // 深灰底上只有 2.7~2.9:1, 小字看不清; 换 colorAccentSoft (7.4:1),
                    // 难度等级改由文字 difficultyLabel 表达.
                    accent: CommonOptions.colorAccentSoft
                    onClicked: {
                        if (root.mode === "place")
                            root.placeSelected(modelData)
                        else
                            root.routeSelected(modelData.id, modelData)
                    }
                }
            }

            // 2026-10-23 巡检 (#110 A12): 文案三态. 抽屉刚打开、一次都没搜过时写
            //   「还没有搜索结果」是假陈述 (还没搜, 谈不上"没有结果"), 改成提示
            //   能搜什么、且不摆"重新搜索"这种无意义动作; 搜过且 0 条才是"没有匹配".
            // 2026-10-27 #132: 文案搬到 emptyText/emptyHint/emptyActionText ——
            //   地点模式再多一档"没填关键词", 三元表达式嵌在属性里已经读不动了.
            EmptyState {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.results || root.results.length === 0
                iconName: "search"
                text: root.emptyText()
                hint: root.emptyHint()
                actionText: root.emptyActionText()
                onActionTriggered: root.commitAndSearch()
            }
        }

        // 2026-10-28 #156: 搜索/清空条件/收起 收到共用动作带 (与「记录」「轨迹」同一条,
        //   同一形状不再逐页各画一遍 —— pass6 收口口径).
        SheetActionBand {
            Layout.fillWidth: true
            actions: root._bandActions
            onTriggered: root._onBandAction(key)
        }
    }
}
