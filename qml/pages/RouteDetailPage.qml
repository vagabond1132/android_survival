/**
 * @file RouteDetailPage.qml
 * @brief 路线详情 (2026-10-20 v9 F2 同款, 丁骨架二级页)
 *
 * 入口: RouteListPage 目录行 (navBus.push({routeId})) / MapPage 路线卡 / 收藏.
 *
 * 版式逐块对应已评审的 mock (F2 详情母版, 与野外生活/绳结详情同一套骨架):
 *   图版头 150px: --paper-sunk 底 + 1px 墨线压底; 左上 "省份 · 类型" chip, 右上 26px
 *           方角返回, 中间是"里程 + 难度梯"读数, 底下 编号 + 性质 + 名称 (21px 800).
 *   读数带  4 格 (时长 / 天数 / 爬升 / 最高), 值全是纯数字, 单位在旁边的汉字注里说一次.
 *   正文    不推荐警示 → 描述 → 别名 → 起终点 (逐点导航 + 全程) → 救援 (长按门) →
 *           评分 11 项 → 许可 → 季节/地形 chip → 亮点 → 沿途物种 → 收藏与装备.
 *   底栏    1px 墨线 + --card-2 底; 左 88px 空心「回目录」, 右实心「在地图查看」.
 *
 * 四条不能破的规则:
 *   ① 不编读数. 每一项都来自 routeService.getById; 库里没有的字段不占位.
 *      旧版的"高度推荐: 路况好 / 补给足 / 安全"是按总分区间现编的判词, 数据里没有这个
 *      口径 —— 换成 scoreDetail 的 11 项真实分项 (分项之和 == 总分, 已由单测钉住).
 *   ② 蛇虫提醒不编季节. 旧版每条形同"6-9 月注意毒蛇"的通栏黄条与这一条路线无关,
 *      现在只有沿途物种表里真有危险级 ≥3 的条目时才出现, 数字来自那张表.
 *   ③ 拨号必须长按. 救援电话只走 HoldConfirmRow, 页面里没有任何单击即拨的口子.
 *   ④ 汉字不进等宽. 编号/坐标/数字走 monoFont, 名称与说明走默认字体
 *      (见 [[qml-monofont-no-cjk]]).
 *
 * 2026-10-20 顺带修掉的三处:
 *   - scoreDetail 恒为空 (loader 读 "score_detail" 而数据是驼峰 "scoreDetail", 且
 *     QJsonValue::toString() 取对象也返回空串) → C++ 侧已修, 这条页面用它的分项.
 *   - 物种跳转不再传 preferDanger: true. 实测 25 个关联 id 里只有 1 个在危险物种库,
 *      其余都是图鉴 id, 那句 flag 只是多跑一次查表并让 _fromGuide 绕一圈.
 *   - 导航失败不再只弹 toast (划一下就没了, 用户在风里读不到). 失败原因留在起终点卡
 *      的注里, 一直看得见.
 */

// delegate 里要读 routeDetail 的属性与方法, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: routeDetail

    Styles { id: styles; visible: false }

    title: entity.name || "路线详情"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 状态 ==============================================================
    property string routeId: ""
    // 名字沿用 entity: 详情系四页同一个口径 (FieldGuideDetailPage / SurvivalDetailPage),
    // 也避开 Item 的默认属性 data (2026-09-19 那个绑定不重估的坑).
    property var entity: ({})
    property var assocList: []
    // 导航失败的话术留在卡面上, 不做一闪而过的 toast
    property string navNote: ""

    readonly property bool hasEntity: (entity.id || "").length > 0
    readonly property int _difficulty: Number(entity.difficulty) || 0
    readonly property color _tone: CommonOptions.difficultyColor(_difficulty)
    readonly property real _km: Number(entity.distanceKm) || 0
    readonly property int _hours: Number(entity.durationHours) || 0
    readonly property int _days: Number(entity.daysNeeded) || 0
    readonly property int _gain: Number(entity.elevationGainM) || 0
    readonly property int _loss: Number(entity.elevationLossM) || 0
    readonly property int _maxAlt: Number(entity.maxAltitudeM) || 0
    readonly property int _minAlt: Number(entity.minAltitudeM) || 0
    readonly property int _score: Number(entity.score) || 0
    readonly property var _seasons: _toArr(entity.bestSeason)
    readonly property var _terrainList: _toArr(entity.terrain)
    readonly property var _aliases: _toArr(entity.alias)
    readonly property int _dangerCount: {
        var n = 0
        for (var i = 0; i < assocList.length; ++i)
            if ((assocList[i].dangerLevel || 0) >= 3) n++
        return n
    }

    function _toArr(v) { return (v && v.length !== undefined) ? v : [] }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    // === 取数 ==============================================================
    function _svcOf(k) {
        if (k === 0) return plantService
        if (k === 1) return animalService
        if (k === 2) return insectService
        return mushroomService
    }

    function _load() {
        if (!routeId || !routeService) return
        entity = routeService.getById(routeId)
        routeService.incrementVisitCount(routeId)
        navNote = ""

        var assoc = routeService.getAssociatedSpecies(routeId)
        var out = []
        // 四个界门都查: 库里 insects/mushrooms 目前全是空的, 但关联表的字段是这四本,
        // 只挑植物与动物两条写死, 以后数据补上就静默丢掉.
        var groups = [[0, _toArr(assoc.plants)], [1, _toArr(assoc.animals)],
                      [2, _toArr(assoc.insects)], [3, _toArr(assoc.mushrooms)]]
        for (var g = 0; g < groups.length; ++g) {
            var svc = _svcOf(groups[g][0])
            var ids = groups[g][1]
            if (!svc || ids.length === 0) continue
            for (var i = 0; i < ids.length; ++i) {
                var s = svc.getById(String(ids[i]))
                if (!s || !s.id) continue
                out.push({
                    id: s.id,
                    commonName: s.commonName || "",
                    scientificName: s.scientificName || "",
                    dangerLevel: Number(s.dangerLevel) || 0,
                    plate: CommonOptions.plateCode("SP", s.id)
                })
            }
        }
        // 危险的排最前: 这一张表在野外是"路上会遇到什么", 不是名录
        out.sort(function (a, b) {
            if (a.dangerLevel !== b.dangerLevel) return b.dangerLevel - a.dangerLevel
            return a.plate < b.plate ? -1 : (a.plate > b.plate ? 1 : 0)
        })
        assocList = out
    }

    // === 起终点 ============================================================
    // 坐标缺失时服务层给 0 (getById: trailhead.isValid() ? latitude : 0.0),
    // 所以判"有没有坐标"就是判 0 —— 没有坐标就明说, 不摆一个点了没反应的按钮.
    readonly property var _points: {
        var m = entity.mountain || ""
        var out = []
        out.push(_mkPoint("起点", "TRAILHEAD", entity.trailheadName, entity.trailheadAddress,
                          Number(entity.trailheadLat), Number(entity.trailheadLon), m))
        out.push(_mkPoint("终点", "TRAIL END", entity.trailendName, entity.trailendAddress,
                          Number(entity.trailendLat), Number(entity.trailendLon), m))
        return out
    }
    readonly property bool _bothPointsUsable: _points[0].ok === true && _points[1].ok === true
    // 端点坐标可信度 (#131): 量化误差与来源都是数据侧字段 (coord_precision_m /
    // coord_source), 格式化走 CommonOptions, 与地图读数条同一个口径。
    // "齐"不等于"准": 库里 286 条端点是整数度坐标 (±5.6 公里), 落到图上是一整片山,
    // 所以读数条必须跟着出现, 而且粗到当不了导航目标时不许标绿。
    readonly property int _coordPrecisionM: Number(entity.coordPrecisionM) || 0
    readonly property string _coordPrecisionText: CommonOptions.coordPrecisionLabel(_coordPrecisionM)
    readonly property string _coordSourceText: CommonOptions.coordSourceLabel(entity.coordSource || "")
    readonly property bool _coordCoarse: _coordPrecisionM >= 1000
    // polyline 在不在库: 0 = 地图上只能画起终点示意直线
    readonly property int _waypointCount: Number(entity.waypointCount) || 0

    function _mkPoint(tag, code, rawName, addr, lat, lon, mountain) {
        var la = Number(lat) || 0
        var lo = Number(lon) || 0
        var nm = CommonOptions.poiName(mountain, String(rawName || ""))
        return {
            tag: tag, code: code, name: nm, addr: String(addr || ""),
            lat: la, lon: lo, ok: (la !== 0 || lo !== 0),
            coord: (la !== 0 || lo !== 0)
                   ? (la.toFixed(5) + ", " + lo.toFixed(5)) : ""
        }
    }

    // 真机只装了高德, geo: 会把 q 当关键词搜 → 一律走高德 app URI, dev=1 声明传入
    // 的是 WGS-84, 由高德自己转 GCJ-02 (见 CommonOptions 与 [[amap-uri-handoff]]).
    function _navPoint(p) {
        if (!p.ok) {
            routeDetail.navNote = p.tag + "在这一条数据里没有坐标, 无法直接导航。"
            return
        }
        if (!CommonOptions.openMapMarker(p.lat, p.lon, p.name))
            routeDetail.navNote = "这台机器没有可接管的地图应用, 起终点坐标已在下方给出, 可手动输入。"
        else
            routeDetail.navNote = ""
    }

    function _navWhole() {
        if (!_bothPointsUsable) {
            routeDetail.navNote = "起点或终点缺坐标, 全程规划不可用 —— 用上面的逐点导航。"
            return
        }
        if (!CommonOptions.openMapRoute(_points[0].lat, _points[0].lon, _points[0].name,
                                        _points[1].lat, _points[1].lon, _points[1].name, "walk"))
            routeDetail.navNote = "这台机器没有可接管的地图应用, 无法发起全程规划。"
        else
            routeDetail.navNote = ""
    }

    // === 评分分项 ==========================================================
    readonly property var _detail: _parseDetail(entity.scoreDetail)

    function _parseDetail(s) {
        if (!s) return null
        try {
            var o = JSON.parse(String(s))
            return (o && typeof o === "object") ? o : null
        } catch (e) {
            return null
        }
    }

    // 分项键的读序 —— 数据来自 JSON 序列化, 键序是按字典排的, 这里按"野外先读什么"重排.
    readonly property var _detailKeys: ["road", "length", "climb", "altitude", "water",
                                        "resupply", "season", "venom", "danger", "rescue",
                                        "trailAdjust"]
    function detailLabel(k) {
        if (k === "road") return "路况"
        if (k === "length") return "长度"
        if (k === "climb") return "爬升"
        if (k === "altitude") return "海拔"
        if (k === "water") return "水源"
        if (k === "resupply") return "补给"
        if (k === "season") return "季节"
        if (k === "venom") return "蛇虫"
        if (k === "danger") return "危险"
        if (k === "rescue") return "救援"
        if (k === "trailAdjust") return "线路调整"
        return k      // 库里新加的键原样显示, 不假装不认识也不瞎猜中文名
    }

    readonly property var _detailRows: {
        var d = _detail
        if (!d) return []
        var out = []
        var used = ({})
        for (var i = 0; i < _detailKeys.length; ++i) {
            var k = _detailKeys[i]
            if (d[k] === undefined) continue
            used[k] = true
            out.push({ label: detailLabel(k), v: Number(d[k]) || 0 })
        }
        for (var kk in d) {
            if (used[kk]) continue
            out.push({ label: detailLabel(kk), v: Number(d[kk]) || 0 })
        }
        return out
    }
    readonly property int _detailSum: {
        var s = 0
        for (var i = 0; i < _detailRows.length; ++i) s += _detailRows[i].v
        return s
    }

    onRouteIdChanged: routeDetail._load()
    // StackView 的 initialProperties 是一条条赋的: routeId 先落地时 entity 还是空,
    // 补一次首帧兜底 (空 routeId 会在 _load 里直接 return).
    Component.onCompleted: routeDetail._load()

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

            // 中间: 里程 + 难度梯. 这一页没有配图 (库里没有线路图素材), 放读数不放假图.
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
                        text: routeDetail._km > 0 ? String(routeDetail._km) : "—"
                        font.family: styles.monoFont
                        font.pixelSize: 34
                        color: CommonOptions.colorText
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        visible: routeDetail._km > 0
                        text: "km"
                        font.pixelSize: styles.fsMd
                        color: CommonOptions.colorTextMuted
                    }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: styles.spSm
                    Ladder {
                        anchors.verticalCenter: parent.verticalCenter
                        value: routeDetail._difficulty
                        tone: routeDetail._tone
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: CommonOptions.difficultyLabel(routeDetail._difficulty)
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
                    onClicked: routeDetail.goBack()
                }
            }

            // 底部: 编号 + 性质 (左/右) / 名称
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
                        code: CommonOptions.plateCode("RT", entity.id || "")
                        tone: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: (entity.routeNature || "")
                              + (entity.isWild === true ? " · 野线"
                                 : (entity.isWild === false ? " · 景区" : ""))
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: entity.name || "路线详情"
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
            visible: routeDetail.hasEntity

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
                        text: "路线读数"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    // 单位只在这里说一次: 格子里全是裸数字, 汉字不许挤进等宽栏
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "单位 小时 / 天 / 米"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: [
                            { k: "小时", v: String(routeDetail._hours) },
                            { k: "天数", v: String(routeDetail._days) },
                            { k: "爬升", v: "+" + routeDetail._gain },
                            { k: "最高", v: String(routeDetail._maxAlt) }
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

                // 海拔与下降: 读数带只有四格, 这两项跟在下面一行说完
                Text {
                    Layout.fillWidth: true
                    text: "最低 " + routeDetail._minAlt + " m · 下降 " + routeDetail._loss + " m"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    elide: Text.ElideRight
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
            visible: routeDetail.hasEntity

            ColumnLayout {
                width: parent.width
                spacing: styles.spMd

                // 不推荐警示 (库里 2 条 6000m+ 被目录规则挡掉, 但从地图/收藏仍进得来)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    Layout.topMargin: styles.spMd
                    visible: entity.notRecommended === true
                    Layout.preferredHeight: nrRow.implicitHeight + 2 * styles.cardPad
                    color: CommonOptions.colorSurface
                    border.color: CommonOptions.colorLegendAmber
                    border.width: styles.lineHair

                    HazardBand {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        stripe: CommonOptions.colorHazard
                    }
                    RowLayout {
                        id: nrRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: styles.hazardBandW + styles.cardPad
                        anchors.rightMargin: styles.cardPad
                        spacing: styles.spSm
                        IconLabel {
                            Layout.alignment: Qt.AlignTop
                            name: "alert"
                            size: styles.icMd
                            tintColor: CommonOptions.colorHazard
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: "本线在目录里默认不推荐"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorHazard
                            }
                            Text {
                                Layout.fillWidth: true
                                // 原因用数据给的原文, 页面不替它编一句
                                text: (entity.notRecommendedReason || "").length > 0
                                      ? String(entity.notRecommendedReason)
                                      : "库里这条没有写原因"
                                font.pixelSize: styles.fsMd
                                color: CommonOptions.colorText
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // 一句话描述
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    Layout.topMargin: styles.spMd
                    visible: (entity.description || "").length > 0
                    text: entity.description || ""
                    font.pixelSize: styles.fsMd
                    color: CommonOptions.colorTextMuted
                    wrapMode: Text.WordWrap
                }

                // 别名 (库里 749 条都有 alias, 多为 1 个)
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    visible: routeDetail._aliases.length > 0
                    text: "又称 · " + routeDetail._aliases.join(" / ")
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    wrapMode: Text.WordWrap
                }

                // --- 起终点 ---
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    Text {
                        Layout.fillWidth: true
                        text: "起终点"
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: !routeDetail._bothPointsUsable ? "有缺坐标"
                              : (routeDetail._coordPrecisionText.length > 0
                                 ? "端点 " + routeDetail._coordPrecisionText
                                 : "坐标齐全")
                        font.pixelSize: styles.fsXs
                        color: (routeDetail._bothPointsUsable && !routeDetail._coordCoarse)
                               ? CommonOptions.colorForest
                               : CommonOptions.colorLegendAmber
                    }
                }

                // 端点是什么性质 + 线是不是实测 (#131)
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: routeDetail._coordSourceText.length > 0
                             || routeDetail._waypointCount > 0
                    text: {
                        var bits = []
                        if (routeDetail._coordSourceText.length > 0)
                            bits.push("坐标来源: " + routeDetail._coordSourceText)
                        bits.push(routeDetail._waypointCount > 0
                                  ? "路径点 " + routeDetail._waypointCount + " 个 (图上按实测轨迹连线)"
                                  : "库里没有路径点, 图上那条线是起终点直线示意")
                        return bits.join("  ·  ")
                    }
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorTextMuted
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: routeDetail._points
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        Layout.preferredHeight: ptRow.implicitHeight + 2 * styles.cardPad
                        color: CommonOptions.colorSurface
                        border.color: CommonOptions.colorRule
                        border.width: styles.lineHair

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: styles.lineAccent
                            color: CommonOptions.colorPlum
                        }

                        RowLayout {
                            id: ptRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: styles.lineAccent + styles.cardPad
                            anchors.rightMargin: styles.cardPad
                            spacing: styles.spSm

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name.length > 0 ? modelData.name : "库里未给名称"
                                    font.pixelSize: styles.fsMd
                                    font.bold: true
                                    color: CommonOptions.colorText
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: modelData.addr.length > 0
                                    text: modelData.addr
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorInk3
                                    wrapMode: Text.WordWrap
                                }
                                // 坐标是拉丁与数字, 可以进等宽族
                                Text {
                                    Layout.fillWidth: true
                                    visible: modelData.coord.length > 0
                                    text: modelData.code + "  " + modelData.coord
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorInk3
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: !modelData.ok
                                    text: "无坐标 · 只能在地图上手动定点"
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorLegendAmber
                                    wrapMode: Text.WordWrap
                                }
                            }
                            OutlineButton {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 66
                                text: modelData.tag
                                tone: CommonOptions.colorText
                                textSize: styles.fsSm
                                onClicked: routeDetail._navPoint(modelData)
                            }
                        }
                    }
                }

                // 全程规划 (徒步线用步行模式) —— 两个点都齐才摆这个按钮
                OutlineButton {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: routeDetail._bothPointsUsable
                    text: "全程导航 (步行)"
                    tone: CommonOptions.colorText
                    textSize: styles.fsSm
                    onClicked: routeDetail._navWhole()
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: routeDetail.navNote.length > 0
                    text: routeDetail.navNote
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorLegendAmber
                    wrapMode: Text.WordWrap
                }

                // --- 救援电话 (长按门) ---
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: (entity.rescuePhone || "").length > 0
                    Layout.preferredHeight: rescueCol.implicitHeight + 2 * styles.cardPad
                    color: CommonOptions.colorSurface
                    border.color: CommonOptions.colorRule
                    border.width: styles.lineHair

                    ColumnLayout {
                        id: rescueCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: styles.cardPad
                        anchors.rightMargin: styles.cardPad
                        spacing: styles.spSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spSm
                            Text {
                                Layout.fillWidth: true
                                text: "本地救援电话"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                            // 号码是数字, 走等宽族
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: entity.rescuePhone || ""
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsLg
                                font.bold: true
                                color: CommonOptions.colorText
                            }
                        }
                        HoldConfirmRow {
                            Layout.fillWidth: true
                            code: String(entity.rescuePhone || "").slice(-4)
                            title: "拨打救援电话"
                            subtitle: "不会自动拨号 · 长按进度条 2 秒确认"
                            accent: CommonOptions.colorHazard
                            confirmable: (entity.rescuePhone || "").length > 0
                            onConfirmed: {
                                if (emergencyService) emergencyService.callNumber(entity.rescuePhone)
                            }
                        }
                    }
                }

                // --- 评分 ---
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    visible: routeDetail._score > 0 || routeDetail._detailRows.length > 0
                    Text {
                        Layout.fillWidth: true
                        text: "综合评分"
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        visible: routeDetail._score > 0
                        text: String(routeDetail._score)
                        font.family: styles.monoFont
                        font.pixelSize: styles.fs2xl
                        color: routeDetail._tone
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "/ 100"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }

                // 11 项分项 —— 判词不编, 直接给分项. 库里 727/749 条有, 22 条只有空值.
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    visible: routeDetail._detailRows.length > 0

                    Repeater {
                        model: routeDetail._detailRows
                        delegate: Rectangle {
                            required property var modelData
                            width: cell.implicitWidth + 2 * styles.spSm
                            height: cell.implicitHeight + styles.spXs
                            color: CommonOptions.colorSurface
                            border.color: CommonOptions.colorRuleSoft
                            border.width: styles.lineHair

                            RowLayout {
                                id: cell
                                anchors.centerIn: parent
                                spacing: styles.spXs
                                Text {
                                    text: modelData.label
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorInk3
                                }
                                Text {
                                    // 分项值可正可负 (trailAdjust 会扣分), 数字走等宽
                                    text: String(modelData.v)
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsXs
                                    color: modelData.v < 0 ? CommonOptions.colorHazard
                                                           : CommonOptions.colorText
                                }
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    visible: routeDetail._detailRows.length > 0
                    text: "分项之和 " + routeDetail._detailSum
                          + (routeDetail._detailSum === routeDetail._score ? " = 总分"
                             : " ≠ 总分 " + routeDetail._score + " (库里这条的口径不一致)")
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    visible: routeDetail._score > 0 && routeDetail._detailRows.length === 0
                    text: "库里这条只有总分, 没有分项"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorLegendAmber
                    wrapMode: Text.WordWrap
                }

                // --- 许可 / 门票 ---
                // permit_required 与 has_permit 在库里有 33 条互相不一致, 所以这里不下
                // "要不要许可"的判语, 只把数据写的原文摊出来让人自己看.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: (entity.permitInfo || "").length > 0
                    Layout.preferredHeight: permitRow.implicitHeight + 2 * styles.cardPad
                    color: CommonOptions.colorSurfaceAlt
                    border.color: CommonOptions.colorRuleSoft
                    border.width: styles.lineHair

                    RowLayout {
                        id: permitRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: styles.cardPad
                        anchors.rightMargin: styles.cardPad
                        spacing: styles.spSm
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "许可"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                        }
                        Text {
                            Layout.fillWidth: true
                            text: entity.permitInfo || ""
                            font.pixelSize: styles.fsMd
                            color: CommonOptions.colorText
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // --- 季节 / 地形 ---
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    visible: routeDetail._seasons.length > 0
                    Text {
                        Layout.fillWidth: true
                        text: "适宜月份"
                        font.pixelSize: styles.fsMd
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: routeDetail._seasons.length + " 个月"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spXs
                    visible: routeDetail._seasons.length > 0

                    Repeater {
                        model: routeDetail._seasons
                        delegate: Chip {
                            required property var modelData
                            // 不可选中的展示 chip: 详情页没有筛选, 别摆成能点的样子
                            text: String(modelData)
                            accent: CommonOptions.colorWater
                            textSize: styles.fsXs
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    visible: routeDetail._terrainList.length > 0
                    Text {
                        Layout.fillWidth: true
                        text: "地形"
                        font.pixelSize: styles.fsMd
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: routeDetail._terrainList.length + " 类地形"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spXs
                    visible: routeDetail._terrainList.length > 0

                    Repeater {
                        model: routeDetail._terrainList
                        delegate: Chip {
                            required property var modelData
                            text: String(modelData)
                            accent: CommonOptions.colorForest
                            textSize: styles.fsXs
                        }
                    }
                }

                // --- 亮点 ---
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: 3
                    visible: (entity.highlights || "").length > 0
                    Text {
                        Layout.fillWidth: true
                        text: "亮点"
                        font.pixelSize: styles.fsMd
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.fillWidth: true
                        text: entity.highlights || ""
                        font.pixelSize: styles.fsMd
                        color: CommonOptions.colorTextMuted
                        wrapMode: Text.WordWrap
                    }
                }

                // --- 沿途物种 ---
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm
                        Text {
                            Layout.fillWidth: true
                            text: "沿途物种"
                            font.pixelSize: styles.fsMd
                            font.bold: true
                            color: CommonOptions.colorText
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: routeDetail.assocList.length + " 个物种"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        // 库里只有 40 条路线做了关联表, 空表说的是数据覆盖, 不是"这条没生物"
                        visible: routeDetail.assocList.length === 0
                        text: "这一条没有沿途物种关联表 (库里只有部分路线做了这份表)"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: routeDetail.assocList
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: styles.rowHSm
                            color: "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: styles.lineAccent + styles.spSm
                                anchors.rightMargin: styles.spXs
                                spacing: styles.spSm

                                Rectangle {
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: styles.lineAccent
                                    color: CommonOptions.dangerColor(modelData.dangerLevel)
                                }
                                Plate {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: styles.plateW
                                    code: modelData.plate
                                    tone: CommonOptions.colorInk3
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.commonName
                                    font.pixelSize: styles.fsMd
                                    color: CommonOptions.colorText
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: (modelData.scientificName || "").length > 0
                                    text: modelData.scientificName
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorInk3
                                }
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "危险 " + modelData.dangerLevel
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.dangerColor(modelData.dangerLevel)
                                }
                                IconLabel {
                                    Layout.alignment: Qt.AlignVCenter
                                    name: "chevron_right"
                                    size: 14
                                    tintColor: CommonOptions.colorInk3
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                // 关联表里的 id 实测是图鉴 id (25 个里只有 1 个在危险库),
                                // 所以不再传 preferDanger, 让详情页按 id 前缀自己认界门.
                                onClicked: routeDetail.navigateTo("FieldGuideDetailPage",
                                        { speciesId: modelData.id })
                            }
                        }
                    }

                    // 规则 ②: 提醒只在真有毒险条目时出现, 数字来自上面那张表
                    Rectangle {
                        Layout.fillWidth: true
                        visible: routeDetail._dangerCount > 0
                        Layout.preferredHeight: dangerNote.implicitHeight + 2 * styles.cardPad
                        color: CommonOptions.colorSurface
                        border.color: CommonOptions.colorLegendAmber
                        border.width: styles.lineHair

                        HazardBand {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            stripe: CommonOptions.colorHazard
                        }
                        Text {
                            id: dangerNote
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: styles.hazardBandW + styles.cardPad
                            anchors.rightMargin: styles.cardPad
                            text: "上表有 " + routeDetail._dangerCount
                                  + " 条危险级 ≥3 · 点行看它的识别与防范"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorHazard
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // --- 收藏与装备 ---
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm

                    OutlineButton {
                        Layout.fillWidth: true
                        text: entity.isFavorite ? "取消收藏" : "收藏这条"
                        tone: entity.isFavorite ? CommonOptions.colorLegendAmber : CommonOptions.colorText
                        textSize: styles.fsSm
                        onClicked: {
                            // addFavorite/deleteFavorite 返回 Result 信封, 判 ok 再重取
                            var r = entity.isFavorite
                                    ? routeService.deleteFavorite(routeDetail.routeId)
                                    : routeService.addFavorite(routeDetail.routeId)
                            if (r && r.ok) entity = routeService.getById(routeDetail.routeId)
                            else routeDetail.navNote = "收藏没有成功" + ((r && r.error) ? ": " + (r.error.message || "") : "")
                        }
                    }
                    OutlineButton {
                        Layout.fillWidth: true
                        text: "看装备"
                        tone: CommonOptions.colorText
                        textSize: styles.fsSm
                        // 进"时节装备推荐": 读这条路线的海拔/天数/难度 + 所选月份,
                        // 一键生成可勾选清单 (以前直接跳装备页要照抄一遍路线参数).
                        onClicked: routeDetail.navigateTo("RouteGearRecommendPage",
                                                          { routeId: routeDetail.routeId })
                    }
                }

                Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spMd }
            }
        }

        // 取不到条目 (id 打错 / service 还没载入) → 空态, 不是一张只有骨架的页
        EmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: styles.spXl * 2
            visible: !routeDetail.hasEntity
            iconName: "map"
            text: "这一条路线没有取到"
            hint: "routeId=" + routeDetail.routeId + " 不在路线库里"
            actionText: "返回目录"
            onActionTriggered: routeDetail.goBack()
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
                    text: "回目录"
                    tone: CommonOptions.colorTextMuted
                    textSize: styles.fsSm
                    onClicked: routeDetail.goBack()
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: "在地图查看这条线"
                    iconName: "map"
                    tone: routeDetail._tone
                    textSize: styles.fsSm
                    // MapPage 启动时读 pendingRouteId 自动 addOrToggleRoute
                    onClicked: routeDetail.navigateTo("MapPage",
                                                      { pendingRouteId: routeDetail.routeId })
                }
            }
        }
    }
}
