/**
 * @file RouteGearRecommendPage.qml
 * @brief 路线 · 时节装备推荐 (2026-10-20 v9 F2 同款, 丁骨架二级页)
 *
 * 入口: 只有 RouteDetailPage 的「看装备」(navBus.navigateTo({routeId})).
 *
 * 这一页存在的理由 (2026-09-30 立项, 口径没变):
 *   「查看装备」原本直接跳 EquipmentPage 的生成器表单 —— 路线里已经有的海拔/天数/
 *   难度要用户再抄一遍. 本页把它们自动带过去, 只留下"哪个月出发 + 怎么背"两个选择
 *   (2026-10-22 起天气也是自动的: 路线省份 × 月份 × 海拔, 不用再抄第三遍).
 *
 * 版式 (F2 详情母版的表单变体):
 *   图版头 150px: --paper-sunk 底 + 1px 墨线压底; 左上 "省份 · 类型" chip, 右上 26px
 *           方角返回, 中间是"所选月份 + 难度梯" (输入只有月份与背负档), 底下
 *           编号 + 性质 + 路线名 (21px 800).
 *   读数带  4 格 (天数 / 最高海拔 / 难度 / 适游季月数), 值全部是这条路线的字段.
 *   正文    失败话术 → 12 个月份格 → 背负方式 → 适游季匹配 → 送进引擎的天气 → 生成结果读数.
 *   底栏    1px 墨线 + --card-2 底; 左 88px 空心「回详情」, 右实心「生成 N 月清单」.
 *
 * 四条不能破的规则:
 *   ① 不编读数. 读数带四项来自 routeService.getById; 生成结果四项来自
 *      equipmentService.generateList 的返回 (critical/important/recommended/optional
 *      的条数 + totalWeightG + altitudeLevelName), 不是本页现算的漂亮话.
 *   ② 送进引擎的每一项都要在页面上看得见, 且写的就是实际送出去的那一档.
 *      2026-10-22 (#87) 起天气不再靠固定档: 路线自带 province + 最高海拔, 加上本页选的
 *      月份, 正好是 equipmentService.climateFor 的三个入参 —— 温度/降水/湿度/风/UV/
 *      昼夜温差六项从往年常态来, 按路线海拔修正过, 读数条与 params 同源.
 *      取不到读数 (省份不在 34 省表 / 服务未就绪) 时不猜温度, 直接拒生成并说明:
 *      v0.4.0 起睡袋/羽绒服档位只看 temp_min, 缺读数退到引擎缺省 20/5 ℃ 等于把冬季
 *      高海拔路线的睡袋判没 —— 那比不生成危险得多.
 *      "营地海拔 = 最高-200m / 最低 = 最高-500m"这两条仍是本页现推的口径, 照旧写出来.
 *      反面教材 (两代, 都留着别复发): 2026-10-20 删掉的是"传了死参数还当坦白"
 *      (旧引擎 14 个前缀里没有温度, 传 tempAvg/tempMin 等于没传); 2026-10-22 删掉的是
 *      "固定档冒充实测" —— 引擎现在按温度配装了, 还写"风 2 m/s / 无降水 / 温差 10 ℃"
 *      这种与实际天气无关的档位, 就是拿常数冒充这条路线.
 *   ③ 不闪 toast. 旧版三处 toast.error 划一下就没了, 风里读不到 (与 RouteDetailPage
 *      同一处理) → 失败原因留在正文顶部的 note, 一直看得见.
 *   ④ 汉字不进等宽. 月份格只写两位数字, "月"字在格外的说明里 (见 [[qml-monofont-no-cjk]]);
 *      读数条的 SRC 行同样只让 "SRC" 三个字母走 monoFont, 中文那截另起一个 Text.
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
    // 缺海拔的路线不能不生成, 按 500 m 走 —— 读数带下方那行说明的就是它
    readonly property int altMaxForGen: _maxAlt > 0 ? _maxAlt : 500
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

    // === 2026-10-22: 路线地点的往年天气 (#87) ==============================
    // 路线库里有 province + maxAltitudeM, 出发月份又是本页唯一的输入, 三者正好是
    // climateFor 的三个参数 —— 天气不必再"按固定档坦白"了. 读数按路线海拔修正过
    // (每升高 1000 m 约 -6.5 ℃ / UV +12%), 档位换算全在 C++ 侧, 这里只做展示与回填.
    // 取不到 (省份不在 34 省表 / 服务未就绪) 时 hasClimate 为假, 退回固定档并在
    // 正文里说清"这一带不在表里", 不假装自动.
    property var climateRead: ({})
    readonly property bool hasClimate: climateRead.tempAvg !== undefined
    // 与装备页读数条同一句、同一拼法: 整句在页面拼一次, 不绑成 Text 上的多行表达式
    readonly property string climateSrcLine: {
        var c = climateRead
        return (c.climateProvince || "") + " · " + selectedMonth + " 月 @"
             + c.climateAltitudeM + " m (代表站 " + c.climateRefAltitudeM
             + " m, 温度修正 " + c.climateCorrectC + " ℃)"
    }
    // 只是把引擎算出来的枚举档翻成人话 (EquipmentService.h Precipitation / HumidityType)
    readonly property var precipNames: ["无降水", "小雨", "中雨", "大雨", "暴雨",
                                        "小雪", "中雪", "大雪", "暴雪"]
    readonly property var humidityNames: ["干燥", "适中", "闷热"]

    function refreshClimate() {
        var prov = String(entity.province || "")
        if (!equipmentService || prov.length === 0) {
            climateRead = ({})
            return
        }
        var r = equipmentService.climateFor(prov, selectedMonth, altMaxForGen)
        climateRead = (r && r.tempAvg !== undefined) ? r : ({})
    }

    // === 2026-10-22: 背负方式 (轻装 / 重装) ================================
    // 与 EquipmentPage 同一套档位与推断式 (引擎 LoadStyle 枚举 0-3). 本页默认
    // "跟随行程" —— 天数是路线自带的, 多数时候推出来的档就是对的; 想按自己习惯
    // 背 (2 天路线只带一晚 = 单日强度) 再手动改.
    property int loadIndex: 0
    property bool loadFollowTrip: true
    readonly property int effDays: _days > 0 ? _days : 1
    readonly property int effDiff: _difficulty > 0 ? _difficulty : 2
    readonly property int loadAuto: effDays >= 3 ? 3
                                    : (effDays >= 2 ? 2 : (effDiff >= 4 ? 1 : 0))
    readonly property int loadEffective: loadFollowTrip ? loadAuto : loadIndex
    readonly property var loadNames: ["轻装一日", "单日强度", "过夜重装", "多日重装"]

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
        refreshClimate()
    }

    /**
     * 生成清单并进 EquipmentDetailPage (档案读数 / 导出 / 去清点页勾选).
     * params 与 EquipmentPage.generateList() 同一套字段名.
     *
     * 2026-10-22 (#87): 天气几项改由 climateFor(路线省份, 出发月份, 最高海拔) 给 ——
     *   引擎从 v0.4.0 起睡袋/羽绒服这类保暖档位**只看 temp_min**, 旧版"没有任何一条
     *   规则看温度"的注释作废. 所以这里取不到往年读数就不能装没事: 缺温度会让引擎
     *   退到 tempAvg 20 / tempMin 5 的缺省, 等于给一条 12 月的高海拔路线判成"不用带
     *   睡袋" —— 直接拒生成并说明原因. (实测: routes.json + travel.json 共 33 个省份
     *   token 全在 34 省表里, 唯一没人用的是澳门; 因此这条分支实际只在服务未就绪时走.)
     *   沙漠 / 沿海两个地区标记本页仍不判: 气候表只按省给月均值, 判不出"这条线走不走
     *   沙漠", 硬猜会给清单塞上不存在的理由, 所以留 false 并在正文说明.
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

        // 读数与展示同源。原来写的是 `if (!hasClimate) refreshClimate()` —— 取过一次就
        // 不再取, 于是"10 月生成过 → 改成 1 月 → 再生成"送进引擎的还是 10 月的温度,
        // 而卡片标题已经写着 1 月 (2026-10-27 真机 A37)。每次生成都按当前月份重取。
        refreshClimate()
        if (!hasClimate) {
            gearPage._generating = false
            gearPage.note = "取不到这一带的往年天气 (省份「"
                            + (entity.province || "未记") + "」不在表里, 或引擎还没加载好) —— "
                            + "保暖档位只看温度, 没有读数就不能瞎生成。"
                            + "去 我 → 装备清单 手填天气生成。"
            return
        }

        var c = gearPage.climateRead
        var altMax = gearPage.altMaxForGen
        var params = {
            "altitudeMax": altMax,
            "altitudeMin": Math.max(0, altMax - 500),
            "altitudeCamp": Math.max(0, altMax - 200),
            "days": gearPage.effDays,
            "difficulty": gearPage.effDiff,
            "load": gearPage.loadEffective,
            "season": gearPage.seasonIndex,
            // wind_speed 与 wind_level 是两条规则, 等级与代表风速必须同档 ——
            // 往年读数两个都给, 都是同一个风的两种写法.
            "windSpeed": c.windSpeed,
            "windLevel": c.windLevel,
            "precipitation": c.precipitation,
            "humidity": c.humidity,
            "uvLevel": c.uvLevel,
            "uvIndex": c.uvIndex,
            "diurnalRange": c.diurnalRange,
            "tempAvg": c.tempAvg,
            "tempMin": c.tempMin,
            "isRainySeason": c.isRainySeason,
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
    // 卡片标题写的是 selectedMonth, 六项读数来自 climateRead —— 换月不重取就是拿上月
    // 的天气挂本月的名 (A37)。
    onSelectedMonthChanged: refreshClimate()
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
                anchors.topMargin: styles.spXs
                width: styles.pageHeadBox
                height: styles.pageHeadBox
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
                    anchors.margins: -styles.pageHeadTapPad
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
                        code: CommonOptions.plateCode("RT", gearPage.routeId)
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
                        text: "生成输入"
                        font.pixelSize: styles.fsXs
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
                            { k: "天数", v: String(gearPage._days > 0 ? gearPage._days : 1) },
                            { k: "最高海拔", v: String(gearPage._maxAlt) },
                            { k: "难度", v: String(gearPage._difficulty) },
                            { k: "适行月", v: String(gearPage.bestSeasonMonths.length) }
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
                                    font.pixelSize: styles.fsXs
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
            Layout.bottomMargin: styles.bottomClearance   // A41: 末行给下面的吸底条让位
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
                            // 2026-10-26 A31 同类: 选中月份是实心块, 底与字必须成对翻档
                            //   (原来底 colorText 夜晚翻近白, 字 colorOnInk 写死浅色 → 月份数字看不见)
                            color: _sel ? CommonOptions.colorAccent : CommonOptions.colorSurfaceAlt
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
                                color: moCell._sel ? CommonOptions.colorTextOnAccent
                                                   : CommonOptions.colorText
                            }
                            Rectangle {
                                visible: moCell._best
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 5
                                width: 12
                                height: 3
                                color: moCell._sel ? CommonOptions.colorBlazeOnFill
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

                // --- 背负方式 (2026-10-22 新增块, 左侧 3px 橙条标出) ----------
                // 这条路线本身带天数, 所以默认"跟随行程"多半就是对的; 给手动档是为了
                // 让"2 天路线只背一晚"这种打法能生成得出来 —— 帐篷/睡袋/炉具/氧气进不进
                // 绝对必带, 全看这一档 (load >= overnight 那几条规则).
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    Layout.preferredHeight: loadCol.implicitHeight
                    spacing: styles.lineAccent

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.preferredWidth: styles.lineAccent
                        color: CommonOptions.colorBlaze
                    }
                    ColumnLayout {
                        id: loadCol
                        Layout.fillWidth: true
                        Layout.topMargin: styles.spXs
                        Layout.bottomMargin: styles.spXs
                        spacing: styles.spXs

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Repeater {
                                model: gearPage.loadNames
                                delegate: Chip {
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    checked: gearPage.loadEffective === index
                                    accent: CommonOptions.colorAccent
                                    textSize: styles.fsXs
                                    onClicked: {
                                        gearPage.loadFollowTrip = false
                                        gearPage.loadIndex = index
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Chip {
                                text: "跟随行程"
                                checked: gearPage.loadFollowTrip
                                accent: CommonOptions.colorTealDeep
                                textSize: styles.fsXs
                                onClicked: gearPage.loadFollowTrip = !gearPage.loadFollowTrip
                            }
                            Text {
                                Layout.fillWidth: true
                                text: gearPage.loadFollowTrip
                                      ? (gearPage.effDays + " 天 / 难度 "
                                         + gearPage.effDiff + " → 自动落在这一档")
                                      : "已手动定档 (与路线天数无关)"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                                elide: Text.ElideRight
                            }
                        }
                    }
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

                // 规则 ② 的坦白: 送进引擎的其余参数, 逐条写**实际送出去的那一档**
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spXs

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm
                        Text {
                            Layout.fillWidth: true
                            text: "送进引擎的 " + gearPage.selectedMonth + " 月天气"
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            color: CommonOptions.colorText
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: gearPage.hasClimate ? "取气候常态表" : "按手动档位"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                        }
                    }

                    // 读数条: 六项全部来自 climateFor, 与 generateList() 里的 params 同源
                    Rectangle {
                        Layout.fillWidth: true
                        // 同 EquipmentPage 的读数条: anchors.fill 的子布局不撑父项高度,
                        // 没有 implicitHeight 这块就是 0 高, 六格读数会溢出去压住下面的行.
                        implicitHeight: climateBody.implicitHeight + 2 * styles.spSm
                        visible: gearPage.hasClimate
                        border.width: styles.lineHair
                        border.color: CommonOptions.colorText
                        color: CommonOptions.colorSurfaceDim

                        ColumnLayout {
                            id: climateBody
                            anchors.fill: parent
                            anchors.margins: styles.spSm
                            spacing: styles.spXs

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                rowSpacing: styles.spXs
                                columnSpacing: styles.spSm

                                Repeater {
                                    model: gearPage.hasClimate
                                          ? [
                                              ["夜温", gearPage.climateRead.tempMin + " ℃"],
                                              ["日均", gearPage.climateRead.tempAvg + " ℃"],
                                              ["降水", gearPage.precipNames[
                                                           gearPage.climateRead.precipitation]
                                                      + " · " + gearPage.climateRead.climatePrecipMm + " mm"],
                                              ["紫外线", gearPage.climateRead.uvIndex + ""],
                                              ["风", gearPage.climateRead.windSpeed + " m/s"],
                                              ["昼夜温差", gearPage.climateRead.diurnalRange + " ℃"]
                                          ]
                                          : []
                                    delegate: StatTile {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        label: modelData[0]
                                        value: modelData[1]
                                        valueSize: styles.fsMd
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: styles.spXs
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "数据来源"
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorInk3
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: gearPage.climateSrcLine
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorTextMuted
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: gearPage.hasClimate
                              ? "常年平均态, 不是天气预报: 它只决定带不带冰爪、睡袋压到几度这一级,"
                                + " 出发前请看实时天气。湿度 "
                                + gearPage.humidityNames[gearPage.climateRead.humidity]
                                + " · 雨季 " + (gearPage.climateRead.isRainySeason ? "是" : "否")
                              : ("这一带取不到往年天气 (省份「" + (entity.province || "未记")
                                 + "」不在天气表内) —— 保暖档位只看温度, 取不到天气时本页拒绝生成, "
                                 + "不去猜一个把睡袋判没的温度。")
                        font.pixelSize: styles.fsXs
                        color: gearPage.hasClimate ? CommonOptions.colorTextMuted
                                                   : CommonOptions.colorHazard
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "营地海拔按 最高-200 m、最低按 最高-500 m 估 (这条路线没有记录营地高度); "
                              + "≥2500 m 由引擎自动判为高原。沙漠 / 沿海两个地区标记本页不判 —— "
                              + "省一级的月均值说不出「这条线走不走沙漠」, 留假比硬猜诚实。"
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
                                { k: "关键", v: String(gearPage._nCrit) },
                                { k: "重要", v: String(gearPage._nImp) },
                                { k: "建议", v: String(gearPage._nRec) },
                                { k: "可选", v: String(gearPage._nOpt) }
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
                                        font.pixelSize: styles.fsXs
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
            hint: "编号 " + gearPage.routeId + " · 路线目录里没有这一条"
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
