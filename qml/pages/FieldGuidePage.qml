/**
 * @file FieldGuidePage.qml
 * @brief ② 资源 — 图鉴根页 (2026-10-20 丁骨架改版)
 *
 * 版式对应已评审的 mock「丁 ②」, 每块解决一件事:
 *   标题条      页名跟着筛选走 (选了"野菜"标题就是野菜), 状态行是"多少条 + 怎么排的"
 *   类目环+chip 同一份数据的两个视图: 环看占比, chip 点选筛选 (环不可点)
 *   省份/月份   保留原筛选 (数据只有省份分布, 没有坐标)
 *   排序条      长按在"按距你排序"与"目录序"之间切 —— 丁的招牌就是这一条
 *   行          3px 类别条 + 方位列 (有读数 50 / 只剩类别图标 30) + 名称行 (名称 + 危险度)
 *               + 学名 + 类目 chip 与生境月份同末行, 右侧图鉴编号与距离
 *
 * 2026-10-22 真机截图复盘 (行版式): 原来方位列一律 50px、危险度 chip 排在第三行 ——
 *   ① 绝大多数物种没有坐标, 50px 灰柱里只有一个 16px 图标, 图标列比正文还抢眼;
 *   ② "有毒/中度" 要读到第三行才看见, 与本页"离它远点先于它是哪一类"的图例规则相反。
 *   现在列宽跟读数走, 危险度紧贴名称, 文字块与色条之间补 12px 左边距。
 *
 * 三条不能破的规则:
 *   ① 不编读数. 物种本体只有省份分布, 没有经纬度 —— 所以"距你 620 m / 112°"只能来自
 *      用户在地图上标注过的物种位置 (mapService.getSpeciesLocations). 没标注的行
 *      方位列是空的, 不写 0°; 一条标注都没有时排序条直接说"目录序", 不假装按距离排.
 *   ② 数字全部来自 service, 页面不写死条数.
 *   ③ 汉字不进等宽字族. 学名/编号/距离走 monoFont (纯拉丁数字), 中文名与 chip 走默认字体.
 *
 * 2026-10-19 那轮修掉的三个真机坑仍然有效: 筛选卡不许用 anchors.fill 自指高度、
 * 分类不许拿缺字的 Material 码位当图标 (蛇/蘑菇/昆虫没有字形)、行尾不许用裸 "›".
 */

// delegate 里要读 fieldGuidePage 的属性与方法, qmlcachegen 静态编译下必须 Bound,
// 否则真机静默 ReferenceError. 位置: pragma 只能在根对象之前.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: fieldGuidePage

    title: "动植物图鉴"

    // === 筛选状态 ===========================================================
    // 2026-10-28 问题1: 界门初值取自窗口级会话 (Main.qml 的 guideKingdom), 理由与
    //   MapPage 的 mapBaseMapIndex 完全一样 —— 底栏切格 stackView.clear() 会重建本页,
    //   页内的 0 每次都会把用户打回植物, 看着就像"资源里只有植物".
    readonly property var _appWin: fieldGuidePage.ApplicationWindow.window
    // `| 0`: 跑起来的 ApplicationWindow 若没有 guideKingdom (老构建的 Main.qml, #143 的
    // 现场), 直接绑定 undefined 到 int 会让这条绑定每次求值都抛错. |0 兜成 0, 界门照常可切.
    property int currentKingdom: _appWin ? (_appWin.guideKingdom | 0) : 0   // 0=植物 1=动物 2=昆虫 3=蘑菇
    // 2026-09-21: 默认必须是 0=全部月份. 之前默认当前月, 数据稀疏月份直接空列表.
    property int currentMonth: 0
    property string currentProvince: "全部"
    property string currentCategory: ""   // "" = 全部类目 (speciesCategoryLabel 的键)
    // 丁: 默认按"离我多远"排. 切序靠长按, 见下面排序条.
    property bool sortByNear: true

    readonly property var kingdomOptions: ["植物", "动物", "昆虫", "蘑菇"]

    // 2026-10-20: 四王国 service 直取. 这里原来写 speciesServiceRegistry.serviceOf(...) ——
    //   那个 id 声明在 Main.qml, 靠"创建上下文链"才查得到 (QML 语义只保证 id 在本文件可见),
    //   而且为了让它可见还得在 Main.qml 里养一个 QtObject 实例. service 本来就是 context
    //   property, 任何文件都能直接引用: FieldGuideDetailPage / HomePage / RouteDetailPage
    //   一直是这个写法, ②跟它们对齐, Main.qml 那个实例随之删掉.
    function kingdomService(idx) {
        return idx === 0 ? plantService
             : idx === 1 ? animalService
             : idx === 2 ? insectService
             : idx === 3 ? mushroomService : null
    }

    // === 数据 ===============================================================
    // base    = 界门+省份+月份筛完的全部条目 (类目筛选与排序都在这一份上做)
    // catKeys = base 里实际出现过的类目键, 按条数降序 (环与 chip 的模型)
    // rows    = 最终显示行: { e: 条目, key: 图鉴编号, bearing, dist, tone, icon }
    // annMap  = 物种 id -> 最近一次地图标注的经纬度 (只有这个能给出真实距离)
    property var base: []
    property var catKeys: []
    property var rows: []
    property var annMap: ({})

    // 定位: 与①营地/⑤求助同一来源 (EmergencyService), 没授权时 hasFix 一直 false
    readonly property bool hasFix: emergencyService ? emergencyService.hasLocation : false
    readonly property real curLat: emergencyService ? emergencyService.currentLatitude : 0
    readonly property real curLon: emergencyService ? emergencyService.currentLongitude : 0

    // base 里有真实标注位置的条数 —— 决定排序条能不能真按距离排
    readonly property int markedCount: {
        var n = 0
        for (var i = 0; i < rows.length; ++i)
            if (rows[i].dist >= 0) n++
        return n
    }

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles; visible: false }

    // === 类别 → 图例色 / 图标 ===============================================
    // 危险度 ≥3 一律压成 hazard 红: "离它远点"比"它是哪一类"要先读到.
    // 图标只给本字体核验过存在的字形 (植物=花, 动物=爪印); 昆虫与蘑菇在本字体
    // 里没有对应物, 宁可留空也不用别的码位凑 —— 上一版拿"插图片"当图鉴图标就是这么错的.
    function toneFor(kingdom, danger) {
        if (danger >= 3) return CommonOptions.colorHazard
        switch (kingdom) {
        case 0: return CommonOptions.colorForest
        case 1: return CommonOptions.colorWater
        case 2: return CommonOptions.colorBlaze
        default: return CommonOptions.colorPlum
        }
    }
    function iconFor(kingdom) {
        if (kingdom === 0) return "plant"
        if (kingdom === 1) return "animal"
        return ""
    }

    // === 换算 ===============================================================
    // 距离/方位只从"用户标注过的位置"算, 算不出来就返回 -1 (调用方不画这一格)
    function geoFor(id) {
        if (!hasFix) return { bearing: -1, dist: -1 }
        var a = annMap[id]
        if (!a) return { bearing: -1, dist: -1 }
        var la = Number(a.lat), lo = Number(a.lon)
        if (!isFinite(la) || !isFinite(lo)) return { bearing: -1, dist: -1 }
        return {
            bearing: CommonOptions.bearingDegrees(curLat, curLon, la, lo),
            dist: CommonOptions.distanceMeters(curLat, curLon, la, lo)
        }
    }

    function refreshAnnotations() {
        var m = ({})
        if (mapService) {
            var raw = mapService.getSpeciesLocations()
            // 同一物种可能标过多次, 后写的覆盖先写的 → 留最近一次
            for (var i = 0; i < raw.length; ++i) {
                var r = raw[i]
                if (r.speciesId) m[r.speciesId] = { lat: r.lat, lon: r.lon }
            }
        }
        annMap = m
    }

    // === 取数 ==============================================================
    // 2026-10-20: 不再走 ServiceListModel. 丁的②要在客户端做类目统计 + 按距离排序,
    // ListModel  role 化之后每条还得 get(i) 再拆, 不如直接拿 service 的 QVariantList
    // (species 的 getAll/getByXxx 返回裸数组, 没有 Result 包装, 不需要解包).
    function loadData() {
        var svc = kingdomService(currentKingdom)
        if (!svc) { base = []; rebuildCategories(); return }
        var list = null
        if (currentProvince === "全部" && currentMonth === 0) list = svc.getAll()
        else if (currentProvince === "全部") list = svc.getByMonth(currentMonth)
        else if (currentMonth === 0) list = svc.getByProvince(currentProvince)
        else list = svc.getByProvinceAndMonth(currentProvince, currentMonth)
        base = (list && list.length !== undefined) ? list : []
        rebuildCategories()
        applyFilter()
    }

    // 类目按条数降序, 条数相同按键序 —— 环与 chip 每轮筛选后都保持同一顺序,
    // 否则颜色位置在两次筛选之间跳, 环就变成噪声.
    function rebuildCategories() {
        var counts = ({})
        for (var i = 0; i < base.length; ++i) {
            var k = base[i].category || ""
            if (k === "") continue
            counts[k] = (counts[k] || 0) + 1
        }
        var keys = []
        for (var key in counts) keys.push(key)
        keys.sort(function (a, b) {
            if (counts[a] !== counts[b]) return counts[b] - counts[a]
            return a < b ? -1 : (a > b ? 1 : 0)
        })
        catKeys = keys
        // 筛完之后当前类目可能已经不在结果里 (换省份/换界门), 这时退回"全部",
        // 不然环全压淡、列表空着, 看起来像崩了.
        if (currentCategory !== "" && counts[currentCategory] === undefined)
            currentCategory = ""
    }

    function categoryCount(key) {
        var n = 0
        for (var i = 0; i < base.length; ++i)
            if ((base[i].category || "") === key) n++
        return n
    }

    // 类目环要用色, 而色是按"这一类最危险的那条"定的: 毒菇/毒蛇整段是红的,
    // 不会因为这类里混了几条低危条目就变绿.
    function dangerOfCategory(key) {
        var mx = 0
        for (var i = 0; i < base.length; ++i) {
            if ((base[i].category || "") !== key) continue
            var d = Number(base[i].dangerLevel) || 0
            if (d > mx) mx = d
        }
        return mx
    }

    function applyFilter() {
        var out = []
        for (var i = 0; i < base.length; ++i) {
            var e = base[i]
            if (currentCategory !== "" && (e.category || "") !== currentCategory) continue
            var g = geoFor(e.id)
            out.push({
                e: e,
                key: CommonOptions.plateCode("SP", e.id),
                bearing: g.bearing,
                dist: g.dist,
                tone: toneFor(currentKingdom, Number(e.dangerLevel) || 0),
                icon: iconFor(currentKingdom)
            })
        }
        var plateOrder = function (a, b) {
            return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0)
        }
        if (sortByNear && hasFix) {
            // 有标注的排前面 (距离升序), 没标注的按图鉴编号跟在后面.
            // 不能把没标注的直接丢掉: 那等于"这一界只有 5 个物种", 是错的.
            out.sort(function (a, b) {
                var av = a.dist < 0 ? Number.MAX_VALUE : a.dist
                var bv = b.dist < 0 ? Number.MAX_VALUE : b.dist
                if (av !== bv) return av - bv
                return plateOrder(a, b)
            })
        } else {
            out.sort(plateOrder)
        }
        rows = out
    }

    // 状态行 + 排序条文案: 四三种情况要分开说, 不能一律写"按距你排序"
    readonly property string sortWord: {
        if (!hasFix) return "目录序 (未定位)"
        if (markedCount === 0) return "目录序 (无标注位置)"
        if (!sortByNear) return "目录序"
        return "按距你排序"
    }
    readonly property string sortHint: {
        if (!hasFix) return "开定位后可按距离排 · 长按切序"
        if (markedCount === 0) return "在地图上标注物种位置后即可按距离排"
        if (sortByNear) return "长按切换为目录序"
        return "长按切换为按距你排序"
    }
    readonly property string pageTitle: currentCategory !== ""
        ? CommonOptions.speciesCategoryLabel(currentCategory)
        : kingdomOptions[currentKingdom]
    readonly property string statusLine: {
        var t = rows.length + " 条 · " + sortWord
        if (currentProvince !== "全部") t += " · " + currentProvince
        if (currentMonth > 0) t += " · " + currentMonth + " 月"
        return t
    }

    // 省份下拉: 取当前界门自己的省份列表 (2026-09-24 那条仍然有效 —— 全国 34 项里
    // 大半选了直接空列表). 类目 chip 是本页自己的 Repeater, 不需要 ListModel.
    ListModel { id: provinceComboModel }
    function rebuildProvinces() {
        var svc = kingdomService(currentKingdom)
        provinceComboModel.clear()
        provinceComboModel.append({ "name": "全部" })
        if (!svc || typeof svc.getAvailableProvinces !== "function") return
        var provs = svc.getAvailableProvinces()
        for (var i = 0; i < provs.length; i++)
            provinceComboModel.append({ "name": provs[i] })
    }

    Component.onCompleted: {
        if (emergencyService) emergencyService.requestLocationUpdate()
        rebuildProvinces()
        refreshAnnotations()
        loadData()
    }
    onVisibleChanged: {
        if (!visible) return
        if (emergencyService) emergencyService.requestLocationUpdate()
        refreshAnnotations()
        applyFilter()
    }
    onCurrentKingdomChanged: {
        // #143 真机教训 (旧顺序的第一句就是这里原来的跨文件写回):
        // 若跑着的 ApplicationWindow 没有 guideKingdom (老构建 Main.qml), 那句赋值当场抛
        // 并中止 handler —— loadData() 永远走不到, chip 变色、currentKingdom 变了,
        // 列表却停在植物, 症状就是"界门装了还是只有植物". 换界只许依赖本页状态:
        // 重建链路排在最前, 会话写回降级成锦上添花, 放最后并用 try/catch 隔离.
        fieldGuidePage.currentProvince = "全部"
        fieldGuidePage.currentCategory = ""
        rebuildProvinces()
        loadData()
        // 存回窗口级, 页面重建后还是这一界 (见上面 currentKingdom 的初值说明)
        try {
            if (fieldGuidePage._appWin) fieldGuidePage._appWin.guideKingdom = currentKingdom
        } catch (e) {
            console.log("[FieldGuide] kingdom session persist skipped: " + e)
        }
    }
    onCurrentMonthChanged: loadData()
    onCurrentProvinceChanged: loadData()
    onCurrentCategoryChanged: applyFilter()
    onSortByNearChanged: applyFilter()
    Connections {
        target: emergencyService
        function onLocationUpdated(lat, lon, accuracy) { fieldGuidePage.applyFilter() }
    }

    // === 版面 ===============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- 标题条 ---
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                // 右上角编号让位, 否则状态行从它底下穿过两边都读不全
                anchors.rightMargin: 56
                spacing: 3
                Text {
                    text: "资源"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: fieldGuidePage.pageTitle
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: fieldGuidePage.statusLine
                    font.pixelSize: styles.fsSm
                    color: CommonOptions.colorTextMuted
                    elide: Text.ElideRight
                }
            }
            // 屏号: 图鉴是 RES 这一格, 界门 1..4 → G-1..G-4 (地物图例的页面编号,
            // 与"这条物种是什么"无关, 别当数据读)
            Plate {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                code: "G-" + (fieldGuidePage.currentKingdom + 1)
                tone: CommonOptions.colorInk3
            }
        }

        // --- 类目环 + 类目 chip ---
        Card {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            spacing: styles.spSm

            // --- 界门 ---
            // 2026-10-27 真机 (A20): 这一行以前不存在 —— currentKingdom 只有初值 0,
            //   页面里没有任何写它的入口, 动物/昆虫/蘑菇三个界 (共 320 条) 在②资源里
            //   根本到不了。下面的 onCurrentKingdomChanged 链路一直是通的, 缺的就是这个按钮。
            // 2026-10-28 #143: chip 装了仍"只有植物" —— 断点不在这一行, 在 handler 首句的
            //   跨文件写回抛错中止 (修法见 onCurrentKingdomChanged). 本行只加一件事:
            //   某界真的 0 条时 chip 直说"暂无资料", 不写个 "0" 让用户以为筛选坏了.
            Flow {
                Layout.fillWidth: true
                spacing: styles.spXs
                Repeater {
                    model: [0, 1, 2, 3]
                    delegate: Chip {
                        required property var modelData
                        // 每界自己的行数 (service 缺失或 0 条时如实说"暂无资料")
                        readonly property int kingdomCount: fieldGuidePage.kingdomService(modelData)
                                                          ? fieldGuidePage.kingdomService(modelData).totalCount : 0
                        text: fieldGuidePage.kingdomOptions[modelData] + " "
                              + (kingdomCount > 0 ? kingdomCount : "暂无资料")
                        // 每界沿用行左侧那条类别色, 切界与认色是同一套口径
                        accent: fieldGuidePage.toneFor(modelData, 0)
                        checked: fieldGuidePage.currentKingdom === modelData
                        textSize: styles.fsSm
                        onClicked: fieldGuidePage.currentKingdom = modelData
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: styles.spMd

                CategoryRing {
                    Layout.alignment: Qt.AlignVCenter
                    diameter: 64
                    hasSelection: fieldGuidePage.currentCategory !== ""
                    centerValue: String(fieldGuidePage.base.length)
                    centerLabel: "总计"
                    // 环的分段 = 当前筛选结果里的类目占比
                    segments: {
                        var out = []
                        for (var i = 0; i < fieldGuidePage.catKeys.length; ++i) {
                            var k = fieldGuidePage.catKeys[i]
                            out.push({
                                value: fieldGuidePage.categoryCount(k),
                                tone: fieldGuidePage.toneFor(fieldGuidePage.currentKingdom,
                                                            fieldGuidePage.dangerOfCategory(k)),
                                active: (fieldGuidePage.currentCategory === ""
                                         || fieldGuidePage.currentCategory === k)
                            })
                        }
                        return out
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: styles.spXs

                    Flow {
                        Layout.fillWidth: true
                        spacing: styles.spXs
                        Repeater {
                            model: fieldGuidePage.catKeys
                            delegate: Chip {
                                required property var modelData
                                text: CommonOptions.speciesCategoryLabel(modelData) + " "
                                      + fieldGuidePage.categoryCount(modelData)
                                checked: fieldGuidePage.currentCategory === modelData
                                accent: CommonOptions.colorTeal
                                textSize: styles.fsSm
                                onClicked: {
                                    fieldGuidePage.currentCategory =
                                        (fieldGuidePage.currentCategory === modelData) ? "" : modelData
                                }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        // 汉字行: 绝不绑 monoFont (方框踩过). 环不可点这条也在这儿交代,
                        // 免得用户在 64px 的弧上找按钮.
                        text: "环 = 类目占比 · 点文字筛选 · 再点一次取消"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextDim
                        elide: Text.ElideRight
                    }
                }
            }

            // --- 省份 / 月份 ---
            FilterRow {
                Layout.fillWidth: true
                label: "省份"
                comboModel: provinceComboModel
                comboTextRole: "name"
                comboCurrentIndex: {
                    for (var i = 0; i < provinceComboModel.count; i++) {
                        if (provinceComboModel.get(i).name === fieldGuidePage.currentProvince) return i
                    }
                    return 0
                }
                onComboActivated: (idx) => {
                    fieldGuidePage.currentProvince = provinceComboModel.get(idx).name
                }
            }

            FilterRow {
                Layout.fillWidth: true
                label: "月份"
                // 2026-09-23: CommonOptions.monthOptions() 第 0 项已经是 "全部"(value=0),
                //   之前页面又 concat 一个 → ComboBox 出现两个 "全部".
                comboModel: CommonOptions.monthOptions()
                comboTextRole: "label"
                comboValueRole: "value"
                comboCurrentIndex: {
                    var opts = CommonOptions.monthOptions()
                    for (var i = 0; i < opts.length; i++) {
                        if (opts[i].value === fieldGuidePage.currentMonth) return i
                    }
                    return 0
                }
                onComboActivated: (idx, value) => { fieldGuidePage.currentMonth = value }
            }
        }

        // --- 排序条 (长按切序) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            Layout.preferredHeight: styles.rowHSm
            color: CommonOptions.colorSurfaceAlt
            border.color: sortArea.pressed ? CommonOptions.colorBlaze : CommonOptions.colorRuleSoft
            border.width: styles.lineHair

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: styles.cardPad
                anchors.rightMargin: styles.cardPad
                spacing: styles.spSm
                IconLabel {
                    Layout.alignment: Qt.AlignVCenter
                    name: "sort"
                    size: styles.icSm
                    tintColor: CommonOptions.colorTextMuted
                }
                Text {
                    Layout.fillWidth: true
                    text: "排序：" + fieldGuidePage.sortWord
                    font.pixelSize: styles.fsSm
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: fieldGuidePage.sortHint
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorTextDim
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: sortArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // 只做长按: 单击留给滚动误触, 排序不该在划列表时被翻掉 (评审 mock 定的就是长按)
                onPressAndHold: fieldGuidePage.sortByNear = !fieldGuidePage.sortByNear
            }
        }

        // --- 蘑菇安全警告 (2026-09-14 起保留: 这是数据侧给的强提示, 不是装饰) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            visible: fieldGuidePage.currentKingdom === 3
            Layout.preferredHeight: visible ? warnText.implicitHeight + styles.spMd * 2 : 0
            radius: styles.rMd
            color: CommonOptions.colorDangerBg
            border.color: CommonOptions.colorDanger
            border.width: styles.lineHair
            RowLayout {
                anchors.fill: parent
                anchors.margins: styles.spMd
                spacing: styles.spSm
                IconLabel {
                    name: "warning"
                    size: styles.icMd
                    tintColor: CommonOptions.colorDanger
                }
                Text {
                    id: warnText
                    Layout.fillWidth: true
                    text: mushroomService ? mushroomService.safetyWarning()
                                          : "蘑菇风险极高, 仅作信息展示, 不要据此采食。"
                    color: CommonOptions.colorDanger
                    font.pixelSize: styles.fsSm
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // --- 列表 ---
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: styles.spSm
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin

            ListView {
                id: speciesList
                anchors.fill: parent
                clip: true
                spacing: styles.spSm
                model: fieldGuidePage.rows

                delegate: Rectangle {
                    required property var modelData
                    width: speciesList.width
                    height: rowBody.implicitHeight + styles.spMd * 2

                    readonly property var e: modelData.e
                    readonly property bool hazard: (Number(e.dangerLevel) || 0) >= 3

                    color: CommonOptions.colorSurface
                    border.color: hazard ? CommonOptions.colorHazard : CommonOptions.colorDivider
                    border.width: styles.lineHair

                    // 3px 类别条 (左侧满高)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: styles.lineAccent
                        color: modelData.tone
                    }

                    // 方位列: 只有用户在地图上标过这个物种才有读数.
                    // 没读数时不该占 50px 的灰柱 (真机: 图标列把标题挤没了).
                    Rectangle {
                        id: bearingStrip
                        anchors.left: parent.left
                        anchors.leftMargin: styles.lineAccent
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: modelData.dist >= 0 ? styles.bearingColW : styles.bearingColWIcon
                        color: CommonOptions.colorSurfaceAlt

                        BearingCell {
                            anchors.centerIn: parent
                            columnWidth: parent.width
                            icon: modelData.icon
                            tone: modelData.tone
                            // 没有标注位置就没有方位 —— 这一格整条关掉,
                            // 不拿 bearing=0 顶替 (0° 在野外读作"正北")
                            showBearing: modelData.dist >= 0
                            bearing: modelData.bearing
                        }
                    }

                    RowLayout {
                        id: rowBody
                        anchors.left: bearingStrip.right
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: styles.spMd
                        anchors.rightMargin: styles.spMd
                        spacing: styles.spMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs

                            // 名称行: 危险度紧贴名称. 本文件的图例规则就是
                            // "离它远点"要先于"它是哪一类"被读到, 不该排在第三行.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: styles.spSm
                                Text {
                                    Layout.fillWidth: true
                                    text: e.commonName || "未知"
                                    color: CommonOptions.colorText
                                    font.pixelSize: styles.fsLg
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                DangerChip {
                                    visible: (Number(e.dangerLevel) || 0) > 0
                                    level: Number(e.dangerLevel) || 0
                                    compact: true
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                            // 学名是拉丁, 可以进等宽字族 (斜体仍属拉丁)
                            // 空的学名不许占一行: ColumnLayout 认 visible (Qt 6.7.2 实测
                            // 隐藏项 implicitHeight 与几何都不算, 见 [[qml-layout-visible-vs-row]]).
                            // 注意 Layout 附身属性里 **没有** visible —— 写 Layout.visible
                            // 是加载期硬错误 "Cannot assign to non-existent property", 整页起不来.
                            Text {
                                Layout.fillWidth: true
                                visible: (e.scientificName || "").length > 0
                                text: e.scientificName || ""
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorTextDim
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: styles.spSm
                                Chip {
                                    visible: fieldGuidePage.currentCategory === ""
                                    text: CommonOptions.speciesCategoryLabel(e.category || "")
                                    accent: CommonOptions.colorTeal
                                    textSize: styles.fsXs
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Text {
                                    // 生境 + 月份: 数据里有什么就写什么, 空就整条不占位
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: ((e.habitats && e.habitats.length > 0)
                                           ? e.habitats[0] : "")
                                          + ((e.activeMonths && e.activeMonths.length > 0)
                                             ? " · " + e.activeMonths.join("/") + " 月" : "")
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorTextMuted
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: styles.spXs

                            Plate {
                                Layout.alignment: Qt.AlignRight
                                code: modelData.key
                                tone: CommonOptions.colorInk3
                            }
                            Text {
                                Layout.alignment: Qt.AlignRight
                                visible: modelData.dist >= 0
                                // 距离数字走等宽: 620 m / 1.1 km 右边界要对齐
                                text: CommonOptions.formatBearingDistance(modelData.dist)
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsXs
                                color: modelData.tone
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // 传 entityId 而非 model, 让详情页重新拉完整数据,
                            // 避免 role 化丢失嵌套数组 (ediblePart/lookAlike).
                            fieldGuidePage.ApplicationWindow.window.navBus.navigateTo(
                                        "FieldGuideDetailPage",
                                        { entityId: e.id, kingdomIndex: fieldGuidePage.currentKingdom })
                        }
                    }
                }
            }

            // 空态: 筛到 0 条不能只剩一片黑 (2026-10-19 真机).
            // #143: 两类 0 条要分开说 —— 界门里这一界本身就 0 条 (base 空) 是"该界暂无资料",
            // 不是筛选问题; 拿"换个省份试试"糊它, 用户会把 chip 当成坏掉的筛选器.
            // 当前四界都有数据 (323/131/107/67), 这条是给未来某界清空时兜底的诚实口径.
            EmptyState {
                anchors.centerIn: parent
                visible: fieldGuidePage.rows.length === 0
                readonly property bool kingdomEmpty: fieldGuidePage.base.length === 0
                iconName: kingdomEmpty ? "list" : "search"
                text: kingdomEmpty
                      ? fieldGuidePage.kingdomOptions[fieldGuidePage.currentKingdom] + " · 该界暂无资料"
                      : "该筛选条件下没有物种"
                hint: kingdomEmpty
                      ? "点上方其它界门试试"
                      : "换个省份、月份或类目试试, 部分物种只在特定季节出现"
                actionText: kingdomEmpty ? "" : "重置筛选"
                onActionTriggered: {
                    fieldGuidePage.currentCategory = ""
                    fieldGuidePage.currentProvince = "全部"
                    fieldGuidePage.currentMonth = 0
                }
            }
        }
    }
}
