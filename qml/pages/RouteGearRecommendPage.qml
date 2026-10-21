/**
 * @file RouteGearRecommendPage.qml
 * @brief 路线 · 时节装备推荐 (2026-10-20 v9 F2 同款, 丁骨架二级页)
 *
 * 入口: 只有 RouteDetailPage 的「看装备」(navBus.navigateTo({routeId})).
 *
 * 这一页存在的理由 (2026-09-30 立项, 口径没变):
 *   「查看装备」原本直接跳 EquipmentPage 的生成器表单 —— 路线里已经有的海拔/天数/
 *   难度要用户再抄一遍. 本页把它们自动带过去, 只留下"哪个月出发"这一个选择.
 *
 * 版式 (F2 详情母版的表单变体):
 *   图版头 150px: --paper-sunk 底 + 1px 墨线压底; 左上 "省份 · 类型" chip, 右上 26px
 *           方角返回, 中间是"所选月份 + 难度梯" (本页唯一的输入就是月份), 底下
 *           编号 + 性质 + 路线名 (21px 800).
 *   读数带  4 格 (天数 / 最高海拔 / 难度 / 适游季月数), 值全部是这条路线的字段.
 *   正文    失败话术 → 12 个月份格 → 适游季匹配 → 生成参数坦白 → 生成结果读数.
 *   底栏    1px 墨线 + --card-2 底; 左 88px 空心「回详情」, 右实心「生成 N 月清单」.
 *
 * 四条不能破的规则:
 *   ① 不编读数. 读数带四项来自 routeService.getById; 生成结果四项来自
 *      equipmentService.generateList 的返回 (critical/important/recommended/optional
 *      的条数 + totalWeightG + altitudeLevelName), 不是本页现算的漂亮话.
 *   ② 生成器要的其余参数本页没有来源, 一律用固定档 —— 那就把真正进规则匹配的固定档
 *      写在页面上: 风(2 m/s · 微风) / UV 等级 / 湿度 / 降水 / 昼夜温差. 旧版只在按钮
 *      下面塞一行"按常规值估算", 现在逐条列出, 并把"营地海拔 = 最高-200m /
 *      最低 = 最高-500m"这两条本页现推的口径也写出来: 路线库里没有营地高度, 这是估的,
 *      得让用户知道它在按什么算.
 *      反面教材 (2026-10-20 删): 旧版还传了 tempAvg/tempMin/uvIndex/people 并写在页面上,
 *      但引擎的 14 个规则前缀里没有温度、没有 uv 数值、people 读完没人用 —— 把死参数
 *      摆出来"坦白"是假坦白, 详见 generateList() 上方注释.
 *   ③ 不闪 toast. 旧版三处 toast.error 划一下就没了, 风里读不到 (与 RouteDetailPage
 *      同一处理) → 失败原因留在正文顶部的 note, 一直看得见.
 *   ④ 汉字不进等宽. 月份格只写两位数字, "月"字在格外的说明里 (见 [[qml-monofont-no-cjk]]).
 */

// delegate 里要读 gearPage 的属性与方法, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: gearPage

    Styles { id: styles; visible: false }

    title: "时节装备推荐"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 状态 ==============================================================
    property string routeId: ""
    property var entity: ({})
    // 出发月份 1-12, 默认当前月
    property int selectedMonth: new Date().getMonth() + 1
    property bool _generating: false
    // 失败 / 提醒话术 (取代 toast, 规则 ③)
    property string note: ""
    // generateList 的返回, 只有生成过才非空
    property var _result: ({})

    readonly property bool hasEntity: (entity.id || "").length > 0
    readonly property int _difficulty: Number(entity.difficulty) || 0
    readonly property int _days: Number(entity.daysNeeded) || 0
    readonly property int _maxAlt: Number(entity.maxAltitudeM) || 0
    readonly property color _tone: CommonOptions.difficultyColor(_difficulty)

    // 月份 -> EquipmentService::Season 枚举 (0 春 / 1 夏 / 2 秋 / 3 冬)
    readonly property int seasonIndex: {
        if (selectedMonth >= 3 && selectedMonth <= 5) return 0
        if (selectedMonth >= 6 && selectedMonth <= 8) return 1
        if (selectedMonth >= 9 && selectedMonth <= 11) return 2
        return 3
    }
    readonly property var seasonNames: ["春季", "夏季", "秋季", "冬季"]
    // 换算说明里的月份区间, 与 seasonIndex 的分档必须一致
    readonly property string seasonMonthSpan: {
        if (seasonIndex === 0) return "3-5 月"
        if (seasonIndex === 1) return "6-8 月"
        if (seasonIndex === 2) return "9-11 月"
        return "12-2 月"
    }

    // 路线适游季: 数据里就是 "5月" 这种 token, parseInt 取数字
    readonly property var bestSeasonMonths: {
        var arr = (entity.bestSeason && entity.bestSeason.length !== undefined)
                  ? entity.bestSeason : []
        var out = []
        for (var i = 0; i < arr.length; ++i) {
            var n = parseInt(String(arr[i]), 10)
            if (!isNaN(n) && n >= 1 && n <= 12 && out.indexOf(n) < 0) out.push(n)
        }
        return out
    }
    readonly property bool monthInBestSeason: bestSeasonMonths.indexOf(selectedMonth) >= 0
    readonly property string bestSeasonSpan: {
        var a = []
        for (var i = 0; i < bestSeasonMonths.length; ++i) a.push(bestSeasonMonths[i] + "月")
        return a.join("、")
    }

    // === 生成结果读数 (全部来自 generateList 的返回) =======================
    readonly property int _nCrit: _lenOf(_result.critical)
    readonly property int _nImp: _lenOf(_result.important)
    readonly property int _nRec: _lenOf(_result.recommended)
    readonly property int _nOpt: _lenOf(_result.optional)
    readonly property int _resultTotal: _nCrit + _nImp + _nRec + _nOpt
    readonly property bool _hasResult: (_result.id || "").length > 0
    readonly property string _weightLabel: {
        var g = Number(_result.totalWeightG) || 0
        return (g / 1000).toFixed(1) + " kg"
    }

    function _lenOf(v) { return (v && v.length !== undefined) ? v.length : 0 }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    function _loadData() {
        if (!routeId || !routeService) return
        entity = routeService.getById(routeId)
        note = ""
    }

    /**
     * 生成清单并进 EquipmentDetailPage (档案读数 / 导出 / 去清点页勾选).
     * params 与 EquipmentPage.generateList() 同一套字段名 —— 那 9 项固定档就是
     * 本页没有来源的部分, 正文里逐条写给了用户 (规则 ②).
     */
    function generateList() {
        if (!hasEntity) {
            gearPage.note = "这一条路线没有取到, 生成不了清单 —— 回详情里重进一次。"
            return
        }
        if (!equipmentService) {
            gearPage.note = "装备引擎还没就绪, 退出 app 重开一次。"
            return
        }
        gearPage._generating = true
        gearPage.note = ""

        var altMax = gearPage._maxAlt > 0 ? gearPage._maxAlt : 500

        // 2026-10-20 核对 (RuleConditionFactory.cpp:62-77 注册的 14 个前缀 +
        //   equipment_rules.json 全部 condition): 引擎只认 altitude / precipitation /
        //   season / wind_speed / wind_level / days / difficulty / diurnal_range /
        //   humidity / uv_level / is_rainy_season / is_plateau / is_desert / is_coastal.
        //   没有任何一条规则看温度, 也没有任何一条看 uv 数值 (uv 只按等级), people 更是
        //   读进结构体之后再没人用 → 旧版传的 tempAvg / tempMin / uvIndex / people 四项
        //   传了等于没传, 却把它们当成"坦白"写在页面上. 死参数从 params 删掉, 正文只留
        //   真正进规则匹配的固定档 (与装备清单「生成」表单默认一字不差).
        var params = {
            "altitudeMax": altMax,
            "altitudeMin": Math.max(0, altMax - 500),
            "altitudeCamp": Math.max(0, altMax - 200),
            "days": gearPage._days > 0 ? gearPage._days : 1,
            "difficulty": gearPage._difficulty > 0 ? gearPage._difficulty : 2,
            "season": gearPage.seasonIndex,
            // wind_speed 与 wind_level 是两条规则, 等级与代表风速要同档 (2 m/s = 微风)
            "windSpeed": 2.0,
            "windLevel": 1,
            "precipitation": 0,   // 无降水
            "uvLevel": 2,         // 强
            "humidity": 1,        // 适中
            "diurnalRange": 10,
            "isRainySeason": false,
            "isDesert": false,
            "isCoastal": false
        }

        var listName = (entity.name || "路线") + " · " + gearPage.selectedMonth + "月装备"
        var result = equipmentService.generateList(listName, params)
        gearPage._generating = false

        if (!result || !result.id) {
            gearPage.note = "生成没有成功 —— 引擎返回了空清单。可以换个月份再试一次。"
            gearPage._result = ({})
            return
        }
        gearPage._result = result
        gearPage.navigateTo("EquipmentDetailPage", { listId: result.id })
    }

    onRouteIdChanged: gearPage._loadData()
    // StackView 的 initialProperties 是一条条赋的: routeId 先落地时 service 可能还没就绪,
    // 补一次首帧兜底 (空 routeId 在 _loadData 里直接 return, 不会多跑一次空查表).
    Component.onCompleted: gearPage._loadData()

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- ① 图版头 (150px) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            color: CommonOptions.colorSurfaceDim

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            // 中间: 所选月份 + 难度梯. 本页唯一的输入就是月份, 所以读数放大它.
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: styles.spLg
                spacing: 5

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4
                    Text {
                        anchors.bottom: parent.bottom
                        text: (gearPage.selectedMonth < 10 ? "0" : "") + gearPage.selectedMonth
                        font.family: styles.monoFont
                        font.pixelSize: 34
                        color: CommonOptions.colorText
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        text: "月出发"
                        font.pixelSize: styles.fsMd
                        color: CommonOptions.colorTextMuted
                    }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: styles.spSm
                    Ladder {
                        anchors.verticalCenter: parent.verticalCenter
                        value: gearPage._difficulty
                        tone: gearPage._tone
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: gearPage.seasonNames[gearPage.seasonIndex]
                              + " · " + CommonOptions.difficultyLabel(gearPage._difficulty)
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
            }

            // 左上: 省份 · 类型 (两个都是数据字段, 没有就整枚不显示)
            Chip {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: styles.pageMargin
                anchors.topMargin: styles.spSm
                visible: text.length > 0
                text: [entity.province, entity.type]
                      .filter(function (s) { return !!(s && String(s).length) })
                      .join(" · ")
                accent: CommonOptions.colorInk3
                checked: true
                textSize: styles.fsXs
            }

            // 右上: 返回方角 26px, 热区向外扩 9px 到 44 (戴手套)
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: styles.pageMargin
                anchors.topMargin: styles.spSm
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
                    onClicked: gearPage.goBack()
                }
            }

            // 底部: 编号 + 性质 (左) / 路线名
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                anchors.bottomMargin: styles.spSm
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Plate {
                        Layout.alignment: Qt.AlignVCenter
                        code: "PLATE " + CommonOptions.plateCode("RT", gearPage.routeId)
                        tone: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        // 性质可能为空, 空的时候不留那个孤零零的 " · 野线"
                        text: [entity.routeNature,
                               entity.isWild ? "野线" : "景区"]
                              .filter(function (s) { return !!(s && String(s).length) })
                              .join(" · ")
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: entity.name || "时节装备推荐"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
            }
        }

        // --- ② 四格读数带 ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: readoutCol.implicitHeight + 2 * styles.spSm
            color: CommonOptions.colorSurface

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: styles.lineHair
                color: CommonOptions.colorRule
            }

            ColumnLayout {
                id: readoutCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                spacing: styles.spSm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "GENERATOR INPUTS"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        font.letterSpacing: 1.4
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    // 规则 ① 的坦白: 四项里只有月份是本页选的
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "月份由你选 · 其余三项来自路线"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: [
                            { k: "DAYS", v: String(gearPage._days > 0 ? gearPage._days : 1) },
                            { k: "ALT MAX", v: String(gearPage._maxAlt) },
                            { k: "DIFF", v: String(gearPage._difficulty) },
                            { k: "BEST MO", v: String(gearPage.bestSeasonMonths.length) }
                        ]
                        delegate: RowLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 0
                            Rectangle {
                                visible: index > 0
                                Layout.preferredWidth: styles.lineHair
                                Layout.fillHeight: true
                                color: CommonOptions.colorRuleSoft
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.k
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsXs
                                    font.letterSpacing: 1.2
                                    color: CommonOptions.colorInk3
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.v
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsSm
                                    color: CommonOptions.colorText
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "单位 天 / 米 / 星 / 个月 · 最高海拔缺数据时按 500 m 生成"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    wrapMode: Text.WordWrap
                }
            }
        }

        // --- ③ 正文 ---
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            clip: true
            visible: gearPage.hasEntity

            ColumnLayout {
                width: parent.width
                spacing: styles.spMd

                // 失败 / 提醒 (规则 ③: 看得见, 不闪)
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    Layout.topMargin: styles.spMd
                    visible: gearPage.note.length > 0
                    text: gearPage.note
                    font.pixelSize: styles.fsSm
                    color: CommonOptions.colorLegendAmber
                    wrapMode: Text.WordWrap
                }

                // 月份选择
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    Layout.topMargin: styles.spMd
                    spacing: styles.spSm
                    Text {
                        Layout.fillWidth: true
                        text: "出发月份"
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: gearPage.seasonMonthSpan + " → "
                              + gearPage.seasonNames[gearPage.seasonIndex]
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    columns: 6
                    rowSpacing: styles.spXs
                    columnSpacing: styles.spXs

                    Repeater {
                        model: 12
                        // 三态 (选中 / 适游季 / 其余) 不是 Chip 的两态能表达的,
                        // 所以这里用自制格: 墨底反白 = 选中, 底部 3px 绿刻度 = 该路线适游季.
                        delegate: Rectangle {
                            id: moCell
                            required property int index

                            Layout.fillWidth: true
                            Layout.preferredHeight: 40

                            readonly property int _m: index + 1
                            readonly property bool _sel: _m === gearPage.selectedMonth
                            readonly property bool _best: gearPage.bestSeasonMonths.indexOf(_m) >= 0

                            radius: styles.rSm
                            color: _sel ? CommonOptions.colorText : CommonOptions.colorSurfaceAlt
                            border.width: styles.lineHair
                            border.color: _sel ? CommonOptions.colorText
                                              : (_best ? CommonOptions.colorForest
                                                       : CommonOptions.colorRule)

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: moCell._best ? -3 : 0
                                text: (moCell._m < 10 ? "0" : "") + moCell._m
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsMd
                                font.bold: moCell._sel || moCell._best
                                color: moCell._sel ? CommonOptions.colorOnInk
                                                   : CommonOptions.colorText
                            }
                            Rectangle {
                                visible: moCell._best
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 5
                                width: 12
                                height: 3
                                color: moCell._sel ? CommonOptions.colorBlazeSoft
                                                   : CommonOptions.colorForest
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: gearPage.selectedMonth = moCell._m
                            }
                        }
                    }
                }

                // 图例: 三个状态各是什么 (数字格没有文字说明, 靠这一行)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "墨底 = 当前选择"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "绿刻度 = 该路线适游季"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorForest
                    }
                    Item { Layout.fillWidth: true }
                }

                // 适游季匹配
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    Layout.preferredHeight: matchTxt.implicitHeight + 2 * styles.cardPad
                    color: CommonOptions.colorSurface
                    border.color: gearPage.monthInBestSeason ? CommonOptions.colorForest
                                                             : CommonOptions.colorLegendAmber
                    border.width: styles.lineHair

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: styles.lineAccent
                        color: gearPage.monthInBestSeason ? CommonOptions.colorForest
                                                          : CommonOptions.colorLegendAmber
                    }
                    Text {
                        id: matchTxt
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: styles.lineAccent + styles.cardPad
                        anchors.rightMargin: styles.cardPad
                        text: gearPage.bestSeasonMonths.length === 0
                              ? "这条路线没有记适游季 · 按你选的月份与季节规则生成"
                              : (gearPage.monthInBestSeason
                                 ? (gearPage.selectedMonth + "月在这条路线的适游季里 ("
                                    + gearPage.bestSeasonSpan + ")")
                                 : (gearPage.selectedMonth + "月不是适游季 · 它记的是 "
                                    + gearPage.bestSeasonSpan + " · 仍可生成, 清单会更保守"))
                        font.pixelSize: styles.fsSm
                        color: CommonOptions.colorTextMuted
                        wrapMode: Text.WordWrap
                    }
                }

                // 规则 ② 的坦白: 引擎要的其余参数本页没有来源
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        text: "生成用的其余参数"
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "路线库里没有这些维度, 本页按固定档送进引擎: 风 2 m/s (微风) / "
                              + "UV 等级 强 / 湿度 适中 / 无降水 / 昼夜温差 10 ℃ —— "
                              + "与 我 → 装备清单 →「生成」表单的默认档完全一致."
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextMuted
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "营地海拔按 最高-200 m、最低按 最高-500 m 估 (库里没有营地高度); "
                              + "≥2500 m 由引擎自动判为高原."
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextMuted
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "引擎不按温度和人数配装: 冷暖只看 季节 + 海拔段位, 昼夜温差规则"
                              + "的门槛是 15 ℃ (本页固定 10 ℃, 不触发). 出发前查实际天气."
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                        wrapMode: Text.WordWrap
                    }
                }

                // 生成结果 (只有点过生成才出现, 数字是引擎返回的)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    visible: gearPage._hasResult

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm
                        Text {
                            Layout.fillWidth: true
                            text: "上一次生成"
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            color: CommonOptions.colorText
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: gearPage._result.name || ""
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                            elide: Text.ElideMiddle
                            Layout.maximumWidth: 150
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Repeater {
                            model: [
                                { k: "CRITICAL", v: String(gearPage._nCrit) },
                                { k: "IMPORTANT", v: String(gearPage._nImp) },
                                { k: "SUGGEST", v: String(gearPage._nRec) },
                                { k: "OPTIONAL", v: String(gearPage._nOpt) }
                            ]
                            delegate: RowLayout {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 0
                                Rectangle {
                                    visible: index > 0
                                    Layout.preferredWidth: styles.lineHair
                                    Layout.fillHeight: true
                                    color: CommonOptions.colorRuleSoft
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.k
                                        font.family: styles.monoFont
                                        font.pixelSize: styles.fsXs
                                        font.letterSpacing: 1.2
                                        color: CommonOptions.colorInk3
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.v
                                        font.family: styles.monoFont
                                        font.pixelSize: styles.fsSm
                                        color: CommonOptions.colorText
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm
                        Text {
                            Layout.fillWidth: true
                            text: "合计 " + gearPage._resultTotal + " 件 · 海拔等级 "
                                  + (gearPage._result.altitudeLevelName || "—")
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorTextMuted
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: gearPage._weightLabel
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsSm
                            color: CommonOptions.colorText
                        }
                    }

                    OutlineButton {
                        Layout.fillWidth: true
                        text: "再看这张清单"
                        tone: CommonOptions.colorText
                        textSize: styles.fsSm
                        onClicked: gearPage.navigateTo("EquipmentDetailPage",
                                                      { listId: gearPage._result.id })
                    }
                }

                Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spMd }
            }
        }

        // 取不到路线 (routeId 打错 / service 还没载入)
        EmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: styles.spXl * 2
            visible: !gearPage.hasEntity
            iconName: "backpack"
            text: "这一条路线没有取到"
            hint: "routeId=" + gearPage.routeId + " 不在路线库里"
            actionText: "返回"
            onActionTriggered: gearPage.goBack()
        }

        // --- ④ 底栏 ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: bottomRow.implicitHeight + 2 * styles.spSm
            color: CommonOptions.colorSurfaceAlt

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            RowLayout {
                id: bottomRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: styles.spLg
                anchors.rightMargin: styles.spLg
                spacing: styles.spMd

                OutlineButton {
                    Layout.preferredWidth: 88
                    Layout.alignment: Qt.AlignVCenter
                    text: "回详情"
                    tone: CommonOptions.colorTextMuted
                    textSize: styles.fsSm
                    onClicked: gearPage.goBack()
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: gearPage._generating ? "生成中…"
                                               : ("生成 " + gearPage.selectedMonth + "月装备清单")
                    iconName: "backpack"
                    tone: gearPage._tone
                    textSize: styles.fsSm
                    busy: gearPage._generating
                    enabled: !gearPage._generating
                    onClicked: gearPage.generateList()
                }
            }
        }
    }
}
