/**
 * @file HomePage.qml
 * @brief ① 营地 — BASE 方位带根页 (2026-10-20 丁骨架落地)
 *
 * 版式逐块对应已评审的 mock (redesign-v8-ding.html 「丁 S1 v8」), 每块解决一件事:
 *   盘行        我在朝哪看 + 这个方向上有什么 (Dial 130 + 右侧读数栏)
 *   墨底仪表    坐标/海拔/精度/朝向 一眼读全 (PositionReadout, 全站只有 ①⑤ 两处墨底)
 *   你面前有什么 按"相对我的方位"列目标, 不是按字母或目录
 *   我的记录    标注 / 收藏 / 总公里 (甲版首页那块"关键统计"的替代, 只有会点进去的数)
 *   2026-10-20 Q3: 原来这里还有一整块 手册 band, 已挪到第 5 格「我」—— 营地是方位页,
 *   绳结/庇护/急救 没有方位, 留在这里只是抢罗盘和面前列表的高度 (~90px).
 *
 * 三条不能破的规则 (改这个文件前先读):
 *   ① 盘上的点是"发现"不是按钮 (130px 盘上只有 6px, 戴手套点不准), 可点的是下面的条目行.
 *   ② 数字全部来自 service, 页面不写死. 上一版首页写死过 "200+ 急救 / 100+ 路线",
 *      每一版都和 assets/data 真实条数对不上.
 *   ③ 没有定位就显示"空盘 + 未定位", 不画假指针、不编海拔. 求助场景里错的读数
 *      比没有读数更危险.
 *
 * service 可能在退出时先于 QML 绑定销毁, 所有绑定都带 null 退化分支.
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

// delegate 里要调 homePage 的方法 / 读外层 id, qmlcachegen 静态编译下必须 Bound,
// 否则真机静默 ReferenceError (2026-10-19 同类 bug 一批).
// 位置: pragma 只能在根对象之前, 写进 Page 花括号里是语法错误.
pragma ComponentBehavior: Bound

Page {
    id: homePage

    title: "营地"
    height: Math.max(parent ? parent.height : 800, 800)
    width: parent ? parent.width : 360

    background: Rectangle { color: CommonOptions.colorBg }

    Styles { id: styles; visible: false }

    function navigateTo(page, props) {
        ApplicationWindow.window.navBus.navigateTo(page, props || {})
    }

    // === 数据来源 ============================================================
    // 定位: EmergencyService 的属性 (2026-10-20 新接), 没授权时 hasLocation 一直 false
    readonly property bool hasFix: emergencyService ? emergencyService.hasLocation : false
    readonly property real curLat: emergencyService ? emergencyService.currentLatitude : 0
    readonly property real curLon: emergencyService ? emergencyService.currentLongitude : 0
    readonly property real accM: emergencyService ? emergencyService.currentAccuracy : -1
    readonly property real altM: emergencyService ? emergencyService.currentAltitude : Number.NaN

    // 朝向: 罗盘读数有效才用; 无罗盘硬件或未校准时盘停在空盘
    readonly property bool hasHeading: compassSensor ? compassSensor.valid : false
    readonly property real headingDeg: hasHeading ? compassSensor.heading : 0
    readonly property int calibPct: compassSensor ? compassSensor.calibrationPercent : -1
    // 2026-10-26 真机 (用户"方位数据未变化"): 这台机 QCompass 一整轮没给有效读数,
    //   ①营地与④地图的盘因此恒为空盘. 第二来源 = GPS 行进方向
    //   (EmergencyService.currentCourse / Android getBearing()), 只有真在走的时候
    //   有数. 优先级 罗盘 > 航向; 两者都无 → 空盘, 不给 0° 的假方向.
    //   本页与 MapPage 必须同一套口径 (两页读数不一致比没有读数更糟).
    readonly property real courseDeg: emergencyService
        ? emergencyService.currentCourse : Number.NaN
    readonly property bool hasCourse: isFinite(courseDeg)
    readonly property real effHeadingDeg: hasHeading ? headingDeg
                                                     : (hasCourse ? courseDeg : 0)
    readonly property bool hasEffHeading: hasHeading || hasCourse

    // 最后一次定位读取时间 (只在 locationUpdated 里刷新, 所以是"读取"而不是"现在")
    property string fixTime: "--:--"

    // 目标列表 ( [{name, lat, lon, bearing, dist, tone, danger, speciesId}] 按距离升序 )
    property var nearby: []

    // === 派生读数 ============================================================
    // 这三个数会在别的页面里变 (地图加标注 / 图鉴收藏 / 走出一条新轨迹), 而
    // getSpeciesLocations()/getFavorites()/getAllTracks() 是普通方法, 没有 NOTIFY,
    // 写成 readonly 绑定就只会在本页构造时求一次 → 返回首页时读到旧数.
    // 所以改成普通属性 + 进页/数据变化时主动 refreshRecords().
    property int annotateCount: 0
    property int favoriteCount: 0
    property real totalKm: 0

    // 坐标行会画进 PositionReadout 的等宽 Text, 所以这一句只许有拉丁和数字
    // (monospace 族没汉字字形). 汉字说明交给标题条那行状态.
    readonly property string coordText: hasFix
        ? curLat.toFixed(5) + (curLat >= 0 ? " N" : " S") + " / "
          + curLon.toFixed(5) + (curLon >= 0 ? " E" : " W")
        : "--"

    // 海拔: 定位没带 Elevation 属性时是 NaN, 显示 "--" 而不是 0
    readonly property string altText: (hasFix && isFinite(altM))
        ? CommonOptions.formatElevation(altM) : "--"
    // 精度: 2026-10-22 #98 起未知是 NaN (以前是 0, 会画成 "±0 m" 这种假数)
    readonly property string accText: (hasFix && isFinite(accM) && accM > 0)
        ? "\u00b1" + Math.round(accM) + " m" : "--"
    readonly property string headingText: hasEffHeading
        ? Math.round(effHeadingDeg) + "\u00b0" : "--"

    // 读数为什么空着 —— C++ 侧把 Qt 的定位错误码翻成中文 (EmergencyService::onSourceError).
    // 这行字画在墨底仪表下面 (走默认字族, 允许汉字), "--" 自己不说话.
    readonly property string fixDiag: emergencyService ? emergencyService.locationDiag : ""
    readonly property string readoutHint:
        (hasFix && !isFinite(altM))
            ? "本次定位不带高程（网络定位常见），海拔读不出" : fixDiag

    // 盘上点 + 扇区 (只画前 12 / 前 6, 再多就糊成一圈)
    readonly property var dialTargets: nearby.slice(0, 12).map(function (t) {
        return { bearing: t.bearing, tone: t.tone }
    })
    readonly property var dialSectors: nearby.slice(0, 6).map(function (t) {
        return { from: t.bearing - 9, to: t.bearing + 9, tone: t.tone }
    })

    // "你面前有什么": 相对当前朝向 ±100° 以内, 最近两条
    readonly property var frontRows: {
        var out = []
        for (var i = 0; i < homePage.nearby.length && out.length < 2; ++i) {
            var t = homePage.nearby[i]
            if (Math.abs(homePage._relAngle(t.bearing)) <= 100) out.push(t)
        }
        return out
    }

    // === 换算 ===============================================================
    // 相对朝向: 正数=偏右, 负数=偏左, 范围 -180..180
    function _relAngle(brg) {
        var d = ((brg - effHeadingDeg) % 360 + 360) % 360
        if (d > 180) d -= 360
        return d
    }
    function relativeWord(brg) {
        var d = _relAngle(brg)
        var a = Math.abs(d)
        if (!hasEffHeading) return CommonOptions.compassLabel(brg)   // 没朝向时退回绝对 8 方位
        if (a <= 22.5)  return "正前方"
        if (a <= 67.5)  return d < 0 ? "左前方" : "右前方"
        if (a <= 112.5) return d < 0 ? "正左" : "正右"
        if (a <= 157.5) return d < 0 ? "左后方" : "右后方"
        return "正后方"
    }

    // 图例色 = 类别 (Species 的 Category 枚举 0蛇/1菇/2虫/3植物/4动物).
    // 危险度 ≥3 一律压成 hazard 红 —— 这一档是"离它远点", 比类别更要先读到.
    function toneFor(category, danger) {
        if (danger >= 3) return CommonOptions.colorHazard
        switch (category) {
        case 3: return CommonOptions.colorForest
        case 4: return CommonOptions.colorWater
        case 2: return CommonOptions.colorBlaze
        case 1: return CommonOptions.colorPlum
        default: return CommonOptions.colorLegendAmber
        }
    }
    // 标注 id 前缀 -> Species Category 枚举值 (跟 toneFor 的 switch 同一套编号)
    function _kingdomCat(id) {
        if (!id) return -1
        if (id.indexOf("plant_") === 0) return 3
        if (id.indexOf("mushroom_") === 0) return 1
        if (id.indexOf("insect_") === 0) return 2
        if (id.indexOf("snake_") === 0) return 0
        if (id.indexOf("animal_") === 0) return 4
        return -1
    }
    // 枚举值 -> 界门 service (上下文属性, teardown 期可能已为 null)
    function _svcOfCat(cat) {
        return cat === 3 ? plantService
             : (cat === 4 || cat === 0) ? animalService
             : cat === 2 ? insectService
             : cat === 1 ? mushroomService : null
    }
    function _sumTrackKm() {
        if (!mapService) return 0
        var list = mapService.getAllTracks()
        var sum = 0
        for (var i = 0; i < list.length; ++i)
            sum += Number(list[i].totalDistanceM) || 0
        return sum / 1000
    }

    // 重算方位表: 定位变了、或地图上标注了新高点, 都要刷新
    function refreshNearby() {
        if (!hasFix || !mapService) { nearby = []; return }
        var raw = mapService.getSpeciesLocations()
        var out = []
        for (var i = 0; i < raw.length; ++i) {
            var m = raw[i]
            var la = Number(m.lat), lo = Number(m.lon)
            if (!isFinite(la) || !isFinite(lo)) continue
            var gid = m.speciesId || ""
            var sp = (gid && speciesService) ? speciesService.getById(gid) : null
            // ③ 详情页记录的是 659 条图鉴 id, 不在 33 条危险物种库里 → speciesService
            //   查不到, category 停在 -1: 色带全变琥珀, 而且 openTarget 的 category>=0
            //   判据会把用户错送到地图页. 按前缀回退到界门 service.
            var gcat = sp ? -1 : homePage._kingdomCat(gid)
            var gsvc = gcat >= 0 ? homePage._svcOfCat(gcat) : null
            var ge = gsvc ? gsvc.getById(gid) : null
            var useG = !!(ge && ge.id)
            var cat = sp ? Number(sp.category) : gcat
            var dgr = sp ? Number(sp.dangerLevel)
                         : (useG ? (Number(ge.dangerLevel) || 0) : Number(m.dangerLevel || 0))
            var nm = (sp && sp.commonName) ? sp.commonName
                   : (useG && ge.commonName) ? ge.commonName
                   : (m.speciesName ? m.speciesName : CommonOptions.speciesCategoryLabel(m.speciesCategory))
            out.push({
                name: nm ? nm : "未命名标注",
                speciesId: m.speciesId || "",
                lat: la, lon: lo,
                category: cat, danger: dgr,
                fromDanger: !!sp,
                bearing: CommonOptions.bearingDegrees(homePage.curLat, homePage.curLon, la, lo),
                dist: CommonOptions.distanceMeters(homePage.curLat, homePage.curLon, la, lo),
                tone: homePage.toneFor(cat, dgr),
                note: m.note || ""
            })
        }
        out.sort(function (a, b) { return a.dist - b.dist })
        nearby = out
    }

    // 「我的记录」三格重新取数 (无 NOTIFY 的方法只能手动刷)
    function refreshRecords() {
        if (mapService) homePage.annotateCount = mapService.getSpeciesLocations().length
        if (fieldGuideHistory) homePage.favoriteCount = fieldGuideHistory.getFavorites().length
        homePage.totalKm = homePage._sumTrackKm()
    }

    // === 生命周期 ===========================================================
    Component.onCompleted: {
        if (emergencyService) emergencyService.requestLocationUpdate()
        if (compassSensor) compassSensor.active = true
        refreshNearby()
        refreshRecords()
    }
    Component.onDestruction: {
        // 离开这一页就把罗盘关掉: 传感器常开在户外是实打实的电量
        if (compassSensor) compassSensor.active = false
    }
    // 从别的页面退回来时重新取数 —— 标注/收藏/轨迹多半就是在那些页面新增的
    onVisibleChanged: {
        if (visible) {
            refreshNearby()
            refreshRecords()
        }
    }

    Connections {
        target: emergencyService
        function onLocationUpdated(lat, lon, accuracy) {
            var d = new Date()
            homePage.fixTime = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
            homePage.refreshNearby()
        }
    }
    Connections {
        target: mapService
        function onDataChanged() {
            homePage.refreshNearby()
            homePage.refreshRecords()
        }
    }

    // === 版面 ==============================================================
    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width

        ColumnLayout {
            width: parent.width
            spacing: styles.spMd

            // --- 标题条: 页名 + 状态行, 右上角等宽读取时间 ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    // 右上角 Plate 占位 (~"10:42" 等宽 + 字距), 不留这个边距状态行会从
                    // Plate 底下穿过去 —— 两处都看得见但谁都读不全.
                    anchors.rightMargin: 56
                    spacing: 3
                    Text {
                        text: "营地"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                    Text {
                        width: parent.width
                        text: "营地"
                        font.pixelSize: styles.fs2xl
                        font.bold: true
                        color: CommonOptions.colorText
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        // 朝向没校准时明说, 别让用户以为盘上的方位是真的.
                        //   2026-10-26: 罗盘之外还有 GPS 行进方向这一路, 那句话要分开说
                        //   —— "按行进方向"只在走动时成立, 写成"朝向"会以为站着转手机也算.
                        text: homePage.hasFix
                              ? (homePage.hasHeading
                                 ? "定位就绪 · 朝向 " + homePage.headingText
                                   + (homePage.calibPct >= 0 && homePage.calibPct < 40
                                      ? " · 罗盘需校准" : "")
                                 : (homePage.hasCourse
                                    ? "定位就绪 · 按行进方向 " + homePage.headingText
                                      + " (走动时才准)"
                                    : "定位就绪 · 无朝向来源, 按正北读"))
                              : "尚未定位 · GPS 未就绪, 盘停在空盘"
                        font.pixelSize: styles.fsSm
                        color: CommonOptions.colorTextMuted
                        elide: Text.ElideRight
                    }
                }
                Plate {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    code: homePage.fixTime
                }
            }

            // --- 盘行: 左 130 方位盘, 右侧读数栏 ---
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                spacing: styles.spMd

                Dial {
                    Layout.preferredWidth: styles.dialSize
                    Layout.preferredHeight: styles.dialSize
                    Layout.alignment: Qt.AlignVCenter
                    heading: homePage.effHeadingDeg
                    // hasFix 在这里的含义是"指针可画": Dial 只要它 true 就按 heading
                    //   画针, 哪怕 heading 是 0. 原来传的是"有定位" —— 站着不动、
                    //   罗盘又不出数时, 那是一根指向正北的假针. 改成"有朝向来源".
                    hasFix: homePage.hasEffHeading
                    hubLabel: "航向"
                    hubValue: homePage.headingText
                    hubSub: homePage.hasEffHeading
                            ? CommonOptions.compassLabel(homePage.effHeadingDeg) : ""
                    hubSubColor: CommonOptions.colorTextMuted
                    targets: homePage.dialTargets
                    sectors: homePage.dialSectors
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: styles.dialSize
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        // 写"共"不写"盘上": 盘上最多画 12 个点, 说"盘上 30 个目标"就是假读数
                        text: "共 " + homePage.nearby.length + " 个目标"
                        font.pixelSize: styles.fsMd
                        font.bold: true
                        color: CommonOptions.colorText
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: homePage.nearby.length > 0
                        // 空数组时不能读 nearby[0]: visible=false 的节点照样求值绑定,
                        // undefined.dist 会抛 TypeError 把整页拖成半渲染.
                        text: homePage.nearby.length > 0
                              ? "最近 " + CommonOptions.formatBearingDistance(homePage.nearby[0].dist)
                                + " · " + homePage.relativeWord(homePage.nearby[0].bearing)
                              : ""
                        // 这句有汉字, 不进 monoFont (见 Styles ⑦ 那条铁律)
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextDim
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: homePage.nearby.length === 0
                        text: "在地图页标注物种后, 这里按方位列出"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextDim
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                    }
                    DuoRule { Layout.fillWidth: true }
                    Text {
                        Layout.fillWidth: true
                        text: homePage.speciesSummaryLine
                        // 这句有汉字 ("749 路线 · 384 物种"), 不进 monoFont
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextDim
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        // 明确告诉用户盘上的点不能点 (规则 ①)
                        text: "盘上的点只作发现 · 条目行可点"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorBlaze
                        elide: Text.ElideRight
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // --- 墨底仪表 (全站两处之一, 与⑤求助同款) ---
            PositionReadout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                label: "实时位置"
                trailing: homePage.hasFix ? homePage.fixTime : "未定位"
                coordText: homePage.coordText
                hint: homePage.readoutHint
                cells: [
                    { v: homePage.altText,     k: "海拔" },
                    { v: homePage.accText,     k: "精度" },
                    { v: homePage.headingText, k: "朝向" },
                    { v: String(homePage.nearby.length), k: "目标数" }
                ]
            }

            // --- 你面前有什么 ---
            SectionTitle {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.topMargin: 2
                text: "你面前有什么"
                trailing: "按方位"
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                spacing: styles.spSm

                Repeater {
                    model: homePage.frontRows
                    delegate: Rectangle {
                        id: frontRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 43
                        color: CommonOptions.colorSurface
                        border.color: modelData.danger >= 3
                                      ? CommonOptions.colorHazard : CommonOptions.colorRule
                        border.width: styles.lineHair

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: styles.lineAccent
                            color: frontRow.modelData.tone
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: styles.lineAccent + 6
                            anchors.rightMargin: styles.cardPad
                            spacing: styles.spSm

                            Text {
                                Layout.preferredWidth: styles.bearingColW
                                text: String(Math.round(frontRow.modelData.bearing)) + "\u00b0"
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsLg
                                color: frontRow.modelData.tone
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: frontRow.modelData.name
                                    font.pixelSize: styles.fsMd
                                    font.bold: true
                                    color: CommonOptions.colorText
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: homePage.relativeWord(frontRow.modelData.bearing)
                                          + " " + CommonOptions.formatBearingDistance(frontRow.modelData.dist)
                                          + (frontRow.modelData.danger >= 3 ? " · 危险度 " + frontRow.modelData.danger : "")
                                    // 有汉字 → 默认字族; 等宽数字已经在左侧方位列里给过了
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorTextDim
                                    elide: Text.ElideRight
                                }
                            }
                            IconLabel {
                                Layout.alignment: Qt.AlignVCenter
                                name: frontRow.modelData.danger >= 3 ? "warning" : "chevron_right"
                                size: frontRow.modelData.danger >= 3 ? styles.icSm : styles.icMd
                                tintColor: frontRow.modelData.danger >= 3
                                           ? CommonOptions.colorHazard : CommonOptions.colorInk3
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: homePage.openTarget(frontRow.modelData)
                        }
                    }
                }

                // 一条都没有时的说明行 (方位列表空着比写死一句话更没底)
                Text {
                    Layout.fillWidth: true
                    visible: homePage.frontRows.length === 0
                    text: homePage.hasFix
                          ? "面前 100° 内没有标注点 · 转身看看别的方向"
                          : "定位就绪后才能按方位列出标注点"
                    font.pixelSize: styles.fsSm
                    color: CommonOptions.colorTextDim
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                }
            }

            // --- 我的记录 ---
            SectionTitle {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.topMargin: 2
                text: "我的记录"
                trailing: "日志"
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                spacing: styles.spSm

                Repeater {
                    model: [
                        { v: homePage.annotateCount, k: "标注", tap: "MapPage" },
                        { v: homePage.favoriteCount, k: "收藏", tap: "FieldGuidePage" },
                        { v: homePage.totalKm.toFixed(1), k: "总公里", tap: "MapPage" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        color: CommonOptions.colorSurface
                        border.color: CommonOptions.colorRule
                        border.width: styles.lineHair
                        Column {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.v
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsLg
                                color: CommonOptions.colorText
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.k
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorTextDim
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: homePage.navigateTo(modelData.tap, {})
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: styles.spLg }
        }
    }

    // 点条目行: 能解析到物种就进详情, 只有坐标的交给地图页 (地图中心落到那个点)
    // 判据用 refreshNearby 已经解析过的 category (>=0 说明 speciesService 查到了),
    // 不再二次 getById —— 那对无效 id 返回 undefined, 直接读 .commonName 会抛 TypeError.
    function openTarget(t) {
        if (t.speciesId && t.category >= 0)
            navigateTo("FieldGuideDetailPage",
                       { speciesId: t.speciesId, preferDanger: !!t.fromDanger })
        else
            navigateTo("MapPage", { pendingFocusLat: t.lat, pendingFocusLon: t.lon })
    }

    // 物种总数一行 (service 没就绪时不带数字)
    readonly property string speciesSummaryLine: {
        if (!routeService || !speciesService) return "离线数据 · 条目数以库内为准"
        return routeService.totalCount + " 路线 · " + speciesService.totalCount + " 物种"
    }
}
