/**
 * @file TravelDetailPage.qml
 * @brief 自驾游详情 (2026-10-20 v9 F2 母版, 丁骨架二级页)
 *
 * 入口: TravelListPage 目录行 / MapPage 自驾线卡片 (navBus.navigateTo({travelId})).
 *
 * 版式逐块对应已评审的 mock (F2 详情母版, 与徒步路线详情同一套骨架):
 *   图版头 150px: --paper-sunk 底 + 1px 墨线压底; 左上 "省份 · 路面" chip, 右上 26px
 *           方角返回, 中间是"里程"读数 (自驾没有难度星, 所以这里不放难度梯), 底下
 *           编号 + 环线/往返标记 + 名称 (21px 800).
 *   读数带  4 格 (天数 / 驾驶时长 / 最高海拔 / 油费), 值全是这条路线的字段.
 *   正文    描述 → 起终点 (逐点导航 + 全程) → 路面/补给/亮点/标签/适游季 chip → 收藏.
 *   底栏    1px 墨线 + --card-2 底; 左 88px 空心「回目录」, 右实心「在地图查看」.
 *
 * 四条不能破的规则:
 *   ① 不编读数. 天数/驾驶时长/最高海拔/油费/里程都来自 travelService.getById;
 *      库里没有难度、没有危险级, 所以这一屏没有难度梯, 也没有"推荐指数".
 *   ② 起终点只到城市级 —— 这是数据的上限, 不是页面的 bug, 所以页面上直说
 *      (101 条的 startName 全是 "成都" 这种 2-4 字地名), 并把坐标原样列出来可核对.
 *      见 [[nav-endpoint-data-quality]]: 用户已定口径 "只要代码修复, 数据保持现状".
 *   ③ 环线不摆全程导航按钮. 101 条里 88 条起终点是同一个坐标 (例: 川西大环线终点也写
 *      "成都"), 旧版照样给"全程导航 (驾车)" —— 高德收到的起点=终点, 出来是一条 0 米的
 *      路线. 现在同城同坐标时按钮不出现, 改一行说明 + 保留逐点导航.
 *   ④ 汉字不进等宽 (见 [[qml-monofont-no-cjk]]); 导航失败不闪 toast, 话术留在卡面上.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: travelDetail

    Styles { id: styles; visible: false }

    title: entity.name || "自驾游详情"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 状态 ==============================================================
    property string travelId: ""
    // 名字沿用 entity: 详情系页面同一个口径, 也避开 Item 的默认属性 data
    // (2026-09-19 那个绑定不重估的坑).
    property var entity: ({})
    property string navNote: ""

    readonly property bool hasEntity: (entity.id || "").length > 0
    readonly property int _days: Number(entity.days) || 0
    readonly property int _driveHours: Number(entity.driveHours) || 0
    readonly property int _maxAlt: Number(entity.maxAltitude) || 0
    readonly property int _fuel: Number(entity.fuelCostCNY) || 0
    readonly property real _km: Number(entity.distanceKm) || 0

    readonly property var _seasons: _toArr(entity.bestSeason)
    readonly property var _tags: _toArr(entity.tags)
    readonly property var _roadList: (entity.roadType ? [String(entity.roadType)] : [])
    // highlights / supply 在数据里是 "/" 连接的短串 (最长 21 字), 不是逗号句:
    // "稻城亚丁+色达+…" 那种写法只有 1 条. 旧版按 [,、] 拆 → 100/101 条拆出来还是整句.
    readonly property var _highlights: _splitSlashes(entity.highlights)
    readonly property var _supply: _splitSlashes(entity.supply)

    function _toArr(v) { return (v && v.length !== undefined && typeof v !== "string") ? v : [] }

    // 五个短项块共用一套版式 (标题 + "N 项" + Flow 胶囊), 所以收成一张表.
    // 值都在页面属性里算好, delegate 里只做渲染.
    readonly property var _groups: [
        { t: "路面类型", a: _roadList },
        { t: "沿途补给", a: _supply },
        { t: "沿途亮点", a: _highlights },
        { t: "标签", a: _tags },
        { t: "适游月份", a: _seasons }
    ]
    function _splitSlashes(s) {
        if (!s) return []
        var parts = String(s).split("/")
        var out = []
        for (var i = 0; i < parts.length; ++i) {
            var p = String(parts[i]).trim()
            if (p.length > 0) out.push(p)
        }
        return out
    }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    // 2026-09-20 的坑: 变更信号与首帧兜底都跑一次的话, incrementVisitCount 会跳 2.
    // 两条都要留 (initialProperties 可能早于 onCompleted 落地, 也可能晚于), 所以按
    // "同一个 id 只取一次" 来去重, 而不是赌信号顺序.
    property string _loadedId: ""
    onTravelIdChanged: travelDetail._loadData()
    Component.onCompleted: travelDetail._loadData()

    function _loadData() {
        if (!travelId || !travelService) return
        if (travelId === _loadedId) return
        _loadedId = travelId
        entity = travelService.getById(travelId)
        travelService.incrementVisitCount(travelId)
        navNote = ""
    }

    // === 起终点 ============================================================
    readonly property var _points: [
        _mkPoint("起点", "START", entity.startName, entity.startCity,
                 Number(entity.startLat), Number(entity.startLon)),
        _mkPoint("终点", "END", entity.endName, entity.endCity,
                 Number(entity.endLat), Number(entity.endLon))
    ]
    // 同城同坐标 = 环线回到起点 (数据里 88/101 是这种)
    readonly property bool _isLoop: _points[0].ok === true && _points[1].ok === true
                                    && _points[0].lat === _points[1].lat
                                    && _points[0].lon === _points[1].lon
    readonly property bool _bothUsable: _points[0].ok === true && _points[1].ok === true
    // 端点坐标可信度 (#131): 量化误差与来源都是数据侧字段 (coordPrecisionM /
    // coordSource), 格式化与地图读数条、路线详情走 CommonOptions 同一个口径。
    readonly property int _coordPrecisionM: Number(entity.coordPrecisionM) || 0
    readonly property string _coordPrecisionText: CommonOptions.coordPrecisionLabel(_coordPrecisionM)
    readonly property string _coordSourceText: CommonOptions.coordSourceLabel(entity.coordSource || "")

    function _mkPoint(tag, code, rawName, city, lat, lon) {
        var la = Number(lat) || 0
        var lo = Number(lon) || 0
        var nm = String(rawName || "").trim()
        return {
            tag: tag, code: code,
            name: nm.length > 0 ? nm : tag,
            city: String(city || "").trim(),
            lat: la, lon: lo, ok: (la !== 0 || lo !== 0),
            coord: (la !== 0 || lo !== 0)
                   ? (la.toFixed(5) + ", " + lo.toFixed(5)) : ""
        }
    }

    // 真机只装了高德, geo: 会把 q 当关键词搜 → 一律走高德 app URI, dev=1 声明传入
    // 的是 WGS-84, 由高德自己转 GCJ-02 (见 [[amap-uri-handoff]]).
    function _navPoint(p) {
        if (!p.ok) {
            travelDetail.navNote = p.tag + "在这一条数据里没有坐标, 无法直接导航。"
            return
        }
        if (!CommonOptions.openMapMarker(p.lat, p.lon, p.name))
            travelDetail.navNote = "这台机器没有可接管的地图应用, 起终点坐标已在下方给出, 可手动输入。"
        else
            travelDetail.navNote = ""
    }

    function _navWhole() {
        if (!_bothUsable) {
            travelDetail.navNote = "起点或终点缺坐标, 全程规划不可用 —— 用上面的逐点导航。"
            return
        }
        if (!CommonOptions.openMapRoute(_points[0].lat, _points[0].lon, _points[0].name,
                                        _points[1].lat, _points[1].lon, _points[1].name, "drive"))
            travelDetail.navNote = "这台机器没有可接管的地图应用, 无法发起全程规划。"
        else
            travelDetail.navNote = ""
    }

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

            // 中间: 里程. 自驾库里没有难度字段, 所以这里只有读数, 不配难度梯.
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
                        text: travelDetail._km > 0 ? String(travelDetail._km) : "—"
                        font.family: styles.monoFont
                        font.pixelSize: 34
                        color: CommonOptions.colorText
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        visible: travelDetail._km > 0
                        text: "km"
                        font.pixelSize: styles.fsMd
                        color: CommonOptions.colorTextMuted
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (travelDetail._days > 0 ? travelDetail._days + " 天" : "")
                          + (travelDetail._driveHours > 0
                             ? " · 驾驶 " + travelDetail._driveHours + " 小时" : "")
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                }
            }

            // 左上: 省份 · 路面 (两个都是数据字段, 没有就整枚不显示)
            Chip {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: styles.pageMargin
                anchors.topMargin: styles.spSm
                visible: text.length > 0
                text: [entity.province, entity.roadType]
                      .filter(function (s) { return !!(s && String(s).length) })
                      .join(" · ")
                accent: CommonOptions.colorPlum
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
                    onClicked: travelDetail.goBack()
                }
            }

            // 底部: 编号 + 环线标记 (左) / 名称
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
                        code: CommonOptions.plateCode("TV", entity.id || travelId)
                        tone: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        // 两端同坐标有两回事: 真环线 (走过一圈回来) 与库里只给到
                        // 城区中心点 (88/101 条, coordSource=city_center)。后者不是
                        // 环线 —— 写「环线 · 回到起点」是给一条根本没测过的线编性质。
                        text: entity.coordSource === "city_center"
                              ? "两端同城 (非实测环线)"
                              : (travelDetail._isLoop ? "环线 · 回到起点" : "往返异点")
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: entity.name || "自驾游详情"
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
                        text: "本条统计"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "油费是全库同口径的估算值"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: [
                            { k: "天数", v: String(travelDetail._days) },
                            { k: "驾驶时长", v: String(travelDetail._driveHours) },
                            { k: "最高海拔", v: String(travelDetail._maxAlt) },
                            { k: "油费", v: String(travelDetail._fuel) }
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
                    text: "单位 天 / 小时 / 米 / 元 · 最高海拔 " + travelDetail._maxAlt
                          + " m 是这条线路上到的最高点"
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
            visible: travelDetail.hasEntity

            ColumnLayout {
                width: parent.width
                spacing: styles.spMd

                // 路线描述
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

                // 起终点
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    Text {
                        Layout.fillWidth: true
                        text: "起点与终点"
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "WGS-84"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        font.letterSpacing: 1.2
                        color: CommonOptions.colorInk3
                    }
                }

                Repeater {
                    model: travelDetail._points
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        Layout.preferredHeight: ptCol.implicitHeight + 2 * styles.cardPad
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
                        ColumnLayout {
                            id: ptCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: styles.lineAccent + styles.cardPad
                            anchors.rightMargin: styles.cardPad
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: styles.spSm
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                          + (modelData.city.length > 0
                                             && modelData.city !== modelData.name
                                             ? " · " + modelData.city : "")
                                    font.pixelSize: styles.fsMd
                                    font.bold: true
                                    color: CommonOptions.colorText
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData.code
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsXs
                                    font.letterSpacing: 1.2
                                    color: CommonOptions.colorInk3
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: modelData.coord.length > 0
                                text: modelData.coord
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsSm
                                color: CommonOptions.colorTextMuted
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: !modelData.ok
                                text: "这一条数据里没有这个点的坐标"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorLegendAmber
                            }
                            OutlineButton {
                                Layout.preferredWidth: 96
                                text: modelData.tag
                                tone: CommonOptions.colorText
                                textSize: styles.fsXs
                                onClicked: travelDetail._navPoint(modelData)
                            }
                        }
                    }
                }

                // 规则 ③: 起终点同坐标不给全程导航按钮
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: travelDetail._isLoop
                    text: (entity.coordSource === "city_center"
                           ? "两端坐标是同一个城区中心点 (这条路线只给到城区级)"
                           : "起终点是同一个位置 (环线)")
                          + " —— 全程规划只会得到一条 0 米的线, "
                          + "所以这里只给逐点导航; 要整条线的走向用下面的「在地图查看」。"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorTextMuted
                    wrapMode: Text.WordWrap
                }
                OutlineButton {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: travelDetail._bothUsable && !travelDetail._isLoop
                    text: "全程导航 (驾车)"
                    tone: CommonOptions.colorText
                    textSize: styles.fsSm
                    onClicked: travelDetail._navWhole()
                }

                // 规则 ②: 端点的粒度与量化误差如实报 (#131), 而不是留一个看似精确的落点。
                // 原先这句是写死的 "自驾库里的起终点只到城市" —— 对 88/101 条成立,
                // 剩下 13 条两端是不同地名, 套同一句话就成了替数据编造来历。
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: travelDetail._coordSourceText.length > 0
                    text: {
                        var p = travelDetail._coordPrecisionText
                        var err = p.length > 0 ? "坐标量化误差 " + p + "。" : ""
                        if (entity.coordSource === "city_center")
                            return "注意: 这一条的起终点是同一个城区中心点 (如「成都」) —— "
                                   + err + "它指的是城, 不是路口: 导航能到城里, 到不了具体入口。"
                        return "注意: 这一条的端点是 " + travelDetail._coordSourceText + " —— "
                               + err + "落点不是实测, 导航只当参考。"
                    }
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: travelDetail.navNote.length > 0
                    text: travelDetail.navNote
                    font.pixelSize: styles.fsSm
                    color: CommonOptions.colorLegendAmber
                    wrapMode: Text.WordWrap
                }

                // 路面 / 沿途补给 / 亮点 / 标签 / 适游季
                Repeater {
                    model: travelDetail._groups
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        spacing: styles.spSm
                        visible: modelData.a.length > 0

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spSm
                            Text {
                                Layout.fillWidth: true
                                text: modelData.t
                                font.pixelSize: styles.fsLg
                                font.bold: true
                                color: CommonOptions.colorText
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData.a.length + " 项"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                        }
                        // Flow + Chip: 这些短串一行放得下六七个, 比一项一行省半屏.
                        // checked:false —— 它们是标签不是筛选, 点下去没有下文.
                        Flow {
                            Layout.fillWidth: true
                            spacing: styles.spSm
                            Repeater {
                                model: travelDetail._toArr(modelData.a)
                                delegate: Chip {
                                    required property var modelData
                                    text: String(modelData)
                                    checked: false
                                    textSize: styles.fsXs
                                }
                            }
                        }
                    }
                }

                // 收藏 (失败写进 navNote, 不闪 toast)
                OutlineButton {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    text: entity.isFavorite ? "取消收藏" : "收藏这条"
                    tone: entity.isFavorite ? CommonOptions.colorLegendAmber
                                            : CommonOptions.colorText
                    textSize: styles.fsSm
                    onClicked: {
                        var r = entity.isFavorite
                                ? travelService.deleteFavorite(travelDetail.travelId)
                                : travelService.addFavorite(travelDetail.travelId)
                        if (r && r.ok) {
                            entity = travelService.getById(travelDetail.travelId)
                            travelDetail.navNote = ""
                        } else {
                            travelDetail.navNote = "收藏没有成功"
                                    + ((r && r.error) ? ": " + (r.error.message || "") : "")
                        }
                    }
                }

                Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spMd }
            }
        }

        // 取不到条目 (id 打错 / service 还没载入)
        EmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: styles.spXl * 2
            visible: !travelDetail.hasEntity
            iconName: "car"
            text: "这一条自驾路线没有取到"
            hint: "编号 " + travelDetail.travelId + " · 自驾目录里没有这一条"
            actionText: "返回目录"
            onActionTriggered: travelDetail.goBack()
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
                    onClicked: travelDetail.goBack()
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: "在地图查看这条线"
                    iconName: "map"
                    tone: CommonOptions.colorPlum
                    textSize: styles.fsSm
                    // MapPage 读 pendingTravelId 自动把这条线画出来
                    onClicked: travelDetail.navigateTo("MapPage",
                                                      { pendingTravelId: travelDetail.travelId })
                }
            }
        }
    }
}
