/**
 * @file MapPage.qml
 * @brief ④地图 (2026-10-20 丁骨架: 满幅底图 + 仪表叠层 + 目标驱动的底部抽屉)
 *
 * 布局:
 *   - 满幅 Map (北朝上), 手动拖动 + 双指捏合缩放. 手势引擎在本文件末尾手写
 *     (DragHandler/PinchHandler, #78; 更早 #43 解的是 center/zoomLevel 绑定锁死)
 *   - 叠层: MapInstrumentOverlay —— 顶部 搜索/图层/求助 三张浮卡, 左上 比例尺 + 缩放,
 *           右上 迷你盘 (HDG 盘心 + N-UP 微标签) + 回中方块, 左下 已选 chip
 *   - 底部: MapBottomSheet (4 Tab: 目标 / 记录 / 轨迹 / 查找) + 「标注这里」主按钮
 *   - 2026-09-15: 取代 HomePage 作为 Main.qml initialItem
 *
 * 2026-10-20 #61 改版时删掉的东西 (别再加回来):
 *   - 顶部 48px 深蓝标题栏 —— 和窗口自己的 header 叠成两条横杠, 白吃 48px 图区.
 *   - MapRightButtonColumn 6 枚实心色圆钮 —— 功能见 MapInstrumentOverlay 的注释.
 *   - 地图中心的 DirectionCompassOverlay 环 —— 与右上迷你盘抢读法.
 */
// 2026-10-19 真机 stage0.log: delegate 里引用外层 id (如 categorySection / searchDialog) 在 qmlcachegen
// 编译下会抛 ReferenceError, 必须 Bound 语义才能拿到外层组件作用域.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Dialogs  // 2026-09-14: FileDialog 需要
import QtQuick.Layouts
import QtPositioning
import QtLocation
// 2026-09-11: MapOverlay 是带 qmldir 的目录式模块 (module OutdoorSurvival),
// 直接通过 import OutdoorSurvival 1.0 解析, 不再单独 import 路径.
import OutdoorSurvival 1.0

Page {
    id: mapPage

    // 2026-10-16 整体改版: 尺寸/间距 token 实例 (Wave 3 逐页替换用)
    Styles { id: styles; visible: false }
    // 2026-10-20: 不再直接引用 Main.qml 的 id "toast" -- QML 语义上 id 只在声明文件里
    //   可见, 跨文件取得到只是"创建上下文链"的巧合 (实测: qmlcachegen 编译下 StackView
    //   页面仍可解析, 所以旧写法确实弹过; 但改成动态 createObject 或被别处嵌就变 undefined).
    //   显式从 Window 上的 alias 取 (Main.qml: readonly property alias toastBox).
    readonly property var toast: ApplicationWindow.window
                                 ? ApplicationWindow.window.toastBox : null
    title: "户外地图"

    // 2026-09-15: 路由入口支持 - 从 RouteListPage 选路线后"在地图查看"
    // 可传 routeId 进来, MapPage 进入时自动选中该路线
    property string pendingRouteId: ""
    property string pendingTravelId: ""
    // 2026-10-20 (①营地): 首页方位条目点进来时把地图中心落到那个标注点上.
    // NaN = 没传 (走原来的 currentLat/currentLon 初值).
    property real pendingFocusLat: Number.NaN
    property real pendingFocusLon: Number.NaN

    // 2026-10-22 #98: 位置来源换成 EmergencyService. 本页原来自己挂一个 PositionSource,
    // 和 service 订的是同一个后端 → 两处各存一份读数, 蓝点却只按本页那份画. 现在位置
    // 只有一个来源, 精度/海拔也走同一组数 (真机拿不到读数的根因在插件的 Java 侧,
    // 修法见 android/src/com/outdoor/survival/OutdoorSurvivalApp.java 的 initQtPositioning).
    // 没定位时保持原来的北京初值: 无定位就写 0,0 会把地图甩到几内亚湾.
    property real currentLat: (emergencyService && emergencyService.hasLocation)
        ? emergencyService.currentLatitude : 39.9087
    property real currentLon: (emergencyService && emergencyService.hasLocation)
        ? emergencyService.currentLongitude : 116.3975
    property bool hasFix: emergencyService ? emergencyService.hasLocation : false
    // 2026-10-26「轨迹/标注点精度到 1 m」: 本页也要能说出"这个点准不准".
    //   NaN = 后端没给 HorizontalAccuracy (整行读数据此不显示, 不写 ±0 米).
    readonly property real accM: emergencyService ? emergencyService.currentAccuracy : Number.NaN
    readonly property real altM: emergencyService ? emergencyService.currentAltitude : Number.NaN
    // 底图索引, 见 _baseMaps (可达源在前). 初值取自窗口级「底图会话」(Main.qml):
    //   Map.plugin 是 write-once, 换源只能重建本页 (见 _rebuildForBaseMap),
    //   重建后得记住用户挑的是哪个源, 页内属性活不过重建.
    property int currentBaseMap: mapPage._appWin ? mapPage._appWin.mapBaseMapIndex : 0
    // 主窗口. 本页是压在 stackView 里的 Page, 只能用附加属性拿窗口 —— Main.qml 的
    //   id `window` 是文件级的, 在这个文件里看不见 (取窗口级属性走 navBus 同一套写法).
    readonly property var _appWin: mapPage.ApplicationWindow.window
    // 2026-10-16: 瓦片加载失败自动 failover 计数 (每成功切一个源 +1, 上限源数-1).
    //   同样存在窗口级: 自动切源会重建本页, 页内计数被清零 → 无限重建循环.
    property int _tileFailover: mapPage._appWin ? mapPage._appWin.mapFailoverTries : 0
    // 2026-10-16: 当前底图探测 URL / 探测是否已通过 (通过则停止 failover)
    property string _probeUrl: ""
    property bool _probeOk: false
    // 2026-09-15: 当前缩放 (受 fit bounds 控制). 初值同 viewLat/Lon, 换底图重建后
    //   沿用上次比例 (见 _restoredView).
    property real currentZoom: mapPage._restoredView[2]
    // 2026-10-19 (用户反馈"地图需要可以手动移动"): Map.center 原来是声明式绑定
    //   currentLat/currentLon. Qt Location 的拖拽是 C++ 侧 setCenter, 不会解除 QML
    //   绑定, 下一次 re-polish 就把中心拉回绑定值 → 地图拖不动 (+/- 按钮生效只是
    //   因为 QML 里的赋值会解绑). 现在初值改成命令式设置, 反向由 onCenterChanged
    //   回写; 定位更新不再自动抢中心 (位置只画蓝点, 见 EmergencyService 那组属性绑定),
    //   用户看哪儿地图就停哪儿.
    // 可视范围 (中心/缩放), 由 Map 拖拽与缩放回写. 「目标」半径查询与"标注这里"用它们,
    // 而不是 currentLat/Lon (那两个是 GPS 位置, 画蓝点用的).
    property real viewLat: mapPage._restoredView[0]
    property real viewLon: mapPage._restoredView[1]
    property real viewZoom: currentZoom
    // 换底图重建本页后要落回原来看的这块视野 (写进窗口级会话, 见 Main.qml).
    //   [0]=lat [1]=lon [2]=zoom; NaN/-1 = 没有可恢复的视野 → 用 GPS 位置与默认缩放.
    //   只做初值: Map 的 center/zoomLevel 没有声明式绑定 (见上 #43), 这里给一次命令式.
    // 2026-10-23 真机 (用户"地图比例尺默认为200"): 默认档原来是 11, 济南纬度下比例尺
    //   读「2 km」—— 野外看这张图要的是 200 m 一格的近景. 真机实测档位对应关系:
    //   11→2 km / 13→500 m / 14→200 m / 18→20 m, 所以默认取 14.
    readonly property int _defaultZoom: 14
    readonly property var _restoredView: {
        var w = mapPage._appWin
        if (w && isFinite(w.mapViewLat) && isFinite(w.mapViewLon))
            return [w.mapViewLat, w.mapViewLon,
                    (isFinite(w.mapViewZoom) && w.mapViewZoom > 0) ? w.mapViewZoom
                                                                   : mapPage._defaultZoom]
        return [currentLat, currentLon, mapPage._defaultZoom]
    }

    // === ④地图 丁仪表 (2026-10-20 #61) =====================================
    // 朝向与 ①营地 同一个来源 (compassSensor), 两页读数不一致比没有读数更糟.
    readonly property bool hasHeading: compassSensor ? compassSensor.valid : false
    readonly property real headingDeg: hasHeading ? compassSensor.heading : 0
    readonly property int calibPct: compassSensor ? compassSensor.calibrationPercent : -1
    // 2026-10-26 真机 (用户"个人位置原点无方向指示 / 右上方方位数据未变化"):
    //   这台机上 QCompass 一整轮没给过有效读数 (valid 恒 false), 所以盘和蓝点
    //   都停在"无朝向"状态. 第二个朝向来源 = GPS 的 course-over-ground
    //   (EmergencyService.currentCourse, 来自 Android getBearing()). 它只在真
    //   在走的时候有数, 站着不动是 NaN —— 所以优先级 罗盘 > GPS 航向, 两者都
    //   没有时宁可不画指针 (规则②: 不给一个 0° 的假方向).
    readonly property real courseDeg: emergencyService
        ? emergencyService.currentCourse : Number.NaN
    readonly property bool hasCourse: isFinite(courseDeg)
    readonly property real effHeadingDeg: hasHeading ? headingDeg
                                                     : (hasCourse ? courseDeg : 0)
    readonly property bool hasEffHeading: hasHeading || hasCourse
    // 读数旁边那句"这个方向是哪来的"必须说清楚: 行进方向和"手机朝哪"是两件事,
    //   混成一个"北朝上"会让人以为站着不动转手机也能指方向. 无朝向时给空串,
    //   叠层那行宁可不显示 (原来那行写死"北朝上", 罗盘不出数时是个假承诺).
    readonly property string headingNote: hasHeading
        ? ("北朝上" + (calibPct >= 0 ? " · 校准 " + calibPct + "%" : ""))
        : (hasCourse ? "按行进方向 · 走动时才准" : "")
    // 精度读数: 拿不到就整行不出现, 不写"±0 米" (那读起来像"极准").
    readonly property string accText: (isFinite(accM) && accM > 0)
        ? ("位置精度 ±" + accM.toFixed(1) + " m") : ""

    // 比例尺: 标准 web-mercator 反推, 口径收口到 CommonOptions.metersPerPixel
    //   (156543.03392·cos(lat)/2^z). 2026-10-22 #82: 原来这条公式抄在本文件里,
    //   而 fitBoundsToRoutes 用的是另一套"经验公式", 两者差约 7 档 —— 同一个页面
    //   里两块各算一次比例, 正是"跳 200km"能长期没人发现的原因. 现在两处共用.
    //   先按 62px 期望宽度取出档位, 再回算尺子真正的像素宽,
    //   这样 "500 m" 那句话和上面那条线永远是对齐的 —— 写死 62px 会谎报比例.
    readonly property int mapZoomInt: Math.round(viewZoom)
    readonly property real _metersPerPixel: CommonOptions.metersPerPixel(viewLat, mapZoomInt)
    readonly property var _scaleSteps: [20, 50, 100, 200, 500, 1000, 2000, 5000,
                                        10000, 20000, 50000, 100000, 200000]
    readonly property real _scaleMeters: {
        if (!isFinite(_metersPerPixel) || _metersPerPixel <= 0) return 0
        var want = _metersPerPixel * 62
        var pick = _scaleSteps[0]
        for (var i = 0; i < _scaleSteps.length; ++i)
            if (_scaleSteps[i] <= want) pick = _scaleSteps[i]
        return pick
    }
    readonly property real scaleBarPx: _metersPerPixel > 0 ? _scaleMeters / _metersPerPixel : 62
    readonly property string scaleText: _scaleMeters >= 1000
        ? (_scaleMeters / 1000) + " km"
        : (_scaleMeters > 0 ? _scaleMeters + " m" : "--")

    // 盘上的点: 原点 = 地图中心 (抽屉表头的 MAP CENTER 读数就是为这句话存在的).
    //   只画物种标注, 上限 12 —— Dial 文件头①: 130px 盘上的点再多就糊成一圈.
    readonly property var dialTargets: {
        var out = []
        for (var k = 0; k < speciesLocations.length && out.length < 12; ++k) {
            var m = speciesLocations[k]
            var la = Number(m.lat), lo = Number(m.lon)
            if (!isFinite(la) || !isFinite(lo)) continue
            out.push({
                bearing: CommonOptions.bearingDegrees(viewLat, viewLon, la, lo),
                tone: CommonOptions.dangerColor(mapPage.dangerLevelOf(m))
            })
        }
        return out
    }
    // 行列表 (盘上目标的文字版, 「目标」Tab 的数据源): 原点同样是地图中心.
    //   这里只出数据不出文案 —— 方位/距离的排版归 Tab, 免得两个地方各写一遍格式.
    readonly property var mapTargets: {
        var rows = []
        for (var k = 0; k < speciesLocations.length; ++k) {
            var m = speciesLocations[k]
            var la = Number(m.lat), lo = Number(m.lon)
            if (!isFinite(la) || !isFinite(lo)) continue
            var lvl = mapPage.dangerLevelOf(m)
            rows.push({
                id: m.id || "",
                speciesId: m.speciesId || "",
                // 2026-10-28 两档工作台: 类别标签 ("植物"/"动物") 不是名字 —— 拿它兜底
                //   会让一条没起名的标注读成一个命名物种, 是假读数. 改字面量占位,
                //   类别本来就显示在下面 sub 行.
                title: m.speciesName || "未命名标注",
                sub: CommonOptions.speciesCategoryLabel(m.speciesCategory || ""),
                // 2026-10-29 (问题1): 「目标」Tab 只拿得到类别, 危险度/记录时刻都留在
                //   本文件里没往下传 —— 行上排不了"哪条更该先看", 也认不出是哪次记的.
                //   这三个字段就是给 Tab 的排序与副标题用的 (不在这里拼文案).
                category: m.speciesCategory || "",
                danger: lvl,
                dangerLabel: lvl >= 0 ? CommonOptions.dangerLevelLabel(lvl) : "",
                time: m.takenAt || "",
                dist: CommonOptions.distanceMeters(viewLat, viewLon, la, lo),
                bearing: CommonOptions.bearingDegrees(viewLat, viewLon, la, lo),
                tone: CommonOptions.dangerColor(lvl),
                lat: la, lon: lo
            })
        }
        rows.sort(function (a, b) { return a.dist - b.dist })
        return rows
    }

    // 2026-09-15: marker 详情对话框的临时数据
    property string markerDetailKind: ""        // species / route_endpoint / danger
    property string markerDetailTitle: ""
    property string markerDetailSub: ""
    property string markerDetailRouteId: ""
    property var markerDetailCoord: null
    property string markerDetailNote: ""
    property string markerDetailSource: ""
    // 2026-10-26 真机 (A27 的另一半): 弹层原来只有 kind/title/sub/note/source, 于是点
    //   开一个物种标注, 屏上只有"物种标注 + 经纬度"两行 —— 名称/类别/危险档数据里都有,
    //   就是没往弹层里传. 补这三个通道, 由 marker 的 click 填.
    property string markerDetailSpeciesId: ""
    property string markerDetailCategory: ""      // 图鉴英文键, 显示时过 speciesCategoryLabel
    property int markerDetailDanger: -1           // -1 = 危险档还没查到, 整行不显示
    property string markerDetailTime: ""          // 记录时刻 (takenAt), 空则整行不出现
    // 2026-10-29 (问题6): 标注文件 id (species_<id>.json 里的 id). 只有它是"这一条
    //   记录"的句柄 —— speciesId 指向图鉴条目, 同一个物种可能被标过几十次, 用它删不掉.
    //   空串 = 不是物种标注 (路线端点/危险点) 或老数据没带 id, 删除入口整行不出现.
    property string markerDetailLocationId: ""

    // 2026-09-15: 危险物种缓存 {speciesId: dangerLevel} - 一次性查全, 给 marker 颜色用
    property var _speciesCache: null

    // 2026-10-23 #82①: 危险等级反查 (盘上的点 / 「目标」Tab 的行 / 地图圆点三处共用).
    //   为什么要反查: mapService.addSpeciesLocation() 把 dangerLevel **写死 0**
    //   (src/map/MapService_species.cpp:51 那行注释自己说了"MapPage 端用 speciesId 反查"),
    //   而这条反查原来只接在地图圆点上, 盘与目标列表照读 m.dangerLevel → 恒 0 →
    //   毒蛇和可食植物在盘上是同一个点. 现在三处都走这里.
    //   返回 -1 = 缓存还没就绪; `CommonOptions.dangerColor()` 把 -1 和 0 都画成三级墨,
    //   圆点那边的图标 (more_horiz / place) 才区分"未知"与"确实不危险".
    function dangerLevelOf(m) {
        if (mapPage._speciesCache === null) return -1
        var spId = m.speciesId
        if (spId && mapPage._speciesCache[spId] !== undefined)
            return mapPage._speciesCache[spId]
        // 库里查不到 (比如只写了坐标的 manual 标注) 就按类别 + 名称关键词估
        var cat = (m.speciesCategory || "").toLowerCase()
        var name = (m.speciesName || "") + " " + (m.note || "")
        if (cat === "snake") return 5
        if (cat === "mushroom") return 4
        if (cat === "insect") {
            if (name.indexOf("蜂") >= 0 || name.indexOf("蝎") >= 0) return 5
            if (name.indexOf("蚂蚁") >= 0) return 3
            return 2
        }
        if (name.indexOf("毒") >= 0) return 5
        if (name.indexOf("危险") >= 0) return 4
        return 0
    }

    // 2026-10-09: 物种标注列表 (NOTIFY-able). 旧写法 Repeater.model =
    //   mapService.getSpeciesLocations() 是一次性绑定, dataChanged 后永不刷新;
    //   改用该属性 + MapItemView (视口虚拟化, 只为可见元素建 delegate).
    property var speciesLocations: []
    // 2026-09-21: Map plugin 错误信息 (TileFetcher 失败时由 onErrorChanged 写入,
    //   banner 监听显示, 用户能立刻看到白底原因)
    property string _mapErrorMsg: ""

    // 拍摄回调: takePhoto(uri) 的 uri 非空时调
    property string lastCapturedPhoto: ""

    // 2026-09-15: 多选叠加的路线/轨迹数据
    // - routeOverlays: [{id, name, colorIdx, color, path: [coord,...], kind, approx}]
    // - routeMarkers: [{routeId, coord, label, color}] 起点 S / 终点 E
    // - waypointMarkers: [{routeId, coord, name, type}] 路径点 (营地/垭口等)
    // - dangerMarkers: [{routeId, coord, name}] 危险点
    // - trackOverlays: [{id, name, colorIdx, color, path, pointCount, thinned}]
    //   path 是"画出来的顶点"(长轨迹抽稀后比原始点少), pointCount 才是本机存的真实
    //   点数 —— 列表行报数用它, 别让抽稀冒充原始轨迹。
    // colorIdx 是这条线在 8 色板里占的号 (_freeColorIdx 分配, 删线时跟着行一起消失)
    property var routeOverlays: []
    property var routeMarkers: []
    property var waypointMarkers: []
    property var dangerMarkers: []
    property var trackOverlays: []
    // 2026-10-29 (问题2): 只有 1 个可用点的轨迹. MapPolyline 少于 2 点什么都不画,
    //   所以"点已经加载了但屏上没东西"在单点轨迹上是必然结果 —— 用一个小圆点把它
    //   画出来, 用户至少知道这条轨迹在哪.
    property var trackMarkers: []
    // 已选 id 集合 (避免重复)
    property var selectedRouteIds: []
    property var selectedTrackIds: []
    // 2026-10-29 (问题2): 复原窗口级选中集之前不要回写会话 —— 复原过程中的每一次
    //   concat 都会触发 onXxxOverlaysChanged, 若不拦住, 先复原的那一项会把窗口里的
    //   完整列表覆盖成只剩它自己.
    property bool _selectionRestored: false
    // 2026-09-15: 路线种类的颜色: 自驾/徒步 颜色不同, 便于视觉区分
    // 2026-10-16 改版: 删掉本地 8 色 _routePalette (它和 CommonOptions.categoryColor
    //   的 8 色板是同一份东西抄了两遍, 只是顺序不同 → 文档 B2 "颜色重复定义").
    //   统一走 categoryColor, 颜色顺序与全站分类色一致.
    function _colorForIndex(idx) {
        return CommonOptions.categoryColor(idx)
    }

    // 2026-10-27 #134: 叠线取色从"按各自序号"改成"按占用分配".
    //   原来路线拿 selectedRouteIds.length、轨迹拿 selectedRouteIds.length +
    //   trackOverlays.length 当色号 —— 两条序列各数各的. 于是"先勾一条轨迹 (拿到色 0),
    //   再勾一条路线 (也拿到色 0)": 两条线在图上一个颜色, 已选清单左边的色块也同色,
    //   用户分不清哪块色标对应哪条线. 删掉中间一项后长度还会塌回去, 新勾的又会和
    //   剩下的重色. 现在在"路线 + 轨迹"这一个集合里找第一个没被占用的色号,
    //   色号跟着 overlay 一起存 (colorIdx), 移除时颜色自然跟着走.
    function _freeColorIdx() {
        var n = CommonOptions.categoryPaletteSize()
        if (!isFinite(n) || n <= 0) return 0
        var used = []
        var lists = [mapPage.routeOverlays, mapPage.trackOverlays]
        for (var l = 0; l < lists.length; l++) {
            for (var i = 0; i < lists[l].length; i++) {
                var ci = lists[l][i].colorIdx
                if (ci !== undefined && used.indexOf(ci) < 0) used.push(ci)
            }
        }
        for (var k = 0; k < n; k++) {
            if (used.indexOf(k) < 0) return k
        }
        // 色板被占满 (同时叠 8 条以上) 时无法不重色, 按总数取模保证顺序稳定
        return (mapPage.routeOverlays.length + mapPage.trackOverlays.length) % n
    }

    // 2026-10-27 #134: 导入分发用的后缀识别. 单列出来是因为文件现在要先经
    //   "复制进沙盒"才有本地路径, 而复制件的后缀来自源 URI 末段 —— 万一源 URI
    //   末段没带扩展名, 调用方还要能回看原始 URI, 所以两处用同一个判据.
    function _trackFileKind(s) {
        var t = String(s || "").toLowerCase()
        if (t.endsWith(".gpx")) return "gpx"
        if (t.endsWith(".kml")) return "kml"
        if (t.endsWith(".csv")) return "csv"
        return ""
    }

    // 2026-09-15: 查 routeId 对应的路线/自驾名, 用于 marker 详情
    function _routeNameById(rid) {
        if (!rid) return ""
        for (var i = 0; i < mapPage.routeOverlays.length; i++) {
            if (mapPage.routeOverlays[i].id === rid) {
                return mapPage.routeOverlays[i].name
            }
        }
        return ""
    }

    // 2026-10-09: 坐标判空统一 helper. 旧写法用 truthy (`if (lat && lon)`) 会丢
    //   纬/经度为 0 的合法坐标 (赤道/本初子午线附近), 且与另一处 Math.abs(..)>0.01
    //   判据不一致. 统一为 isFinite + 合法区间.
    // 2026-10-27 #134: 但 (0,0) 这一对是"没填"的哨兵, 不是赤道坐标 —— 库里的路线
    //   缺坐标时就是这么落盘 (见 nav-endpoint-data-quality). 让它过门会画出一条到
    //   几内亚湾的线, 并把 fitBounds 拉到一个空屏幕上. 与 C++ 侧 importGpx/importKml
    //   的坐标门同一判据: 单轴为 0 仍然放行, 只有成对为 0 才拒.
    function _validCoord(la, lo) {
        if (!isFinite(la) || !isFinite(lo)) return false
        if (Math.abs(la) > 90 || Math.abs(lo) > 180) return false
        return !(la === 0 && lo === 0)
    }

    // 2026-10-27 #131: 端点坐标可信度读数。precisionM 是数据侧算好的量化误差
    // (coord_precision_m, 单位米, 0=未知), coordSource 说明这个点是从哪来的。
    // 格式化在 CommonOptions 里 (与两张详情页同一个口径), 这里只决定"这一行说哪些":
    // 读数条是小抽屉里的 11px 单行, 只放精度 + 城区中心点那一条 —— 因为 ±6 米
    // 看着像能直接导航, 必须当场说清那个点指的是"城"而不是路口。
    // 精度未知就整段不写, 不编「±0 米」这种读数。
    function _precisionNote(precisionM, coordSource) {
        var parts = []
        var p = CommonOptions.coordPrecisionLabel(Number(precisionM) || 0)
        if (p.length > 0) parts.push(p)
        if (coordSource === "city_center") parts.push(CommonOptions.coordSourceLabel(coordSource))
        return parts.length ? "  ·  " + parts.join("  ·  ") : ""
    }

    // 这条"线"到底是什么。库里没有路径点时只有起终点, 画出来是示意直线, 把它
    // 写成「2 个点」会被当成一条测过的轨迹 —— 违反「不给假读数」。
    // 只剩一个端点可用时(终点坐标被数据侧判为不可信, 或库里就没填)连线都画不出,
    // 只有 S 标记, 读数要说的是这件事。
    function _pathNote(o) {
        if (o.path.length < 2) return "  ·  仅起点有坐标"
        if (o.approx === true) return "  ·  起终点直线示意"
        return "  ·  GPS 实测轨迹 " + o.path.length + " 点"
    }

    // 2026-09-19: 启动时申请关键权限 (位置 + 相机). MapPage 是主页,
    //   EmergencyService 的定位读数需要 ACCESS_FINE_LOCATION 才能拿到 GPS,
    //   拍照按钮需要 CAMERA. Android 6+ 必须在运行时申请, Manifest 声明不够.
    //   走 androidPlatform.checkPermission / requestPermission (C++ 端真 JNI,
    //   不再是 stub). 已授权直接 callback(true), 未授权弹系统框, 异步回调.
    function _ensurePermissions() {
        if (!androidPlatform) return
        if (typeof androidPlatform.checkPermission !== "function") return
        if (typeof androidPlatform.requestPermission !== "function") return

        // 位置: GPS 必备
        if (!androidPlatform.checkPermission("android.permission.ACCESS_FINE_LOCATION")) {
            androidPlatform.requestPermission(
                "android.permission.ACCESS_FINE_LOCATION",
                function(granted) {
                    console.log("[MapPage] ACCESS_FINE_LOCATION granted=" + granted)
                })
        }

        // 相机: 拍照按钮点击触发 (这里提前申, 避免点击时还要等)
        if (!androidPlatform.checkPermission("android.permission.CAMERA")) {
            androidPlatform.requestPermission(
                "android.permission.CAMERA",
                function(granted) {
                    console.log("[MapPage] CAMERA granted=" + granted)
                })
        }
    }

    Component.onCompleted: {
        // 2026-10-20 #61: 不再在进页时 openTab(2). 原来那是为了"逼 NearbyTab 自己拉一次数据"
        //   的补丁 (周边 Tab 恒按 (0,0) 查询的坑), 现在中心点绑定修好了、「目标」Tab 的
        //   标注行又是纯绑定, 不需要靠开抽屉来触发取数 —— 而且一进来就压起半屏抽屉
        //   正好盖住这张页要看的地图.
        // 罗盘只在页面可见时开 (持续开明显吃电). 底栏切格走 stackView.clear() → 上一页
        //   的 onDestruction 先跑、本页 onCompleted 后跑, 这个先后顺序保证 active 不会被
        //   后一页关掉后又不打开. 与 ①营地 / ⑤求助 同一套写法.
        if (compassSensor) compassSensor.active = true
        // 2026-10-22 #98: 位置流改由 EmergencyService 提供 (本页的 PositionSource 已删),
        // 所以进页要自己起流 —— 与 ①营地 / ②图鉴 / ⑤求助 同一句写法.
        if (emergencyService) emergencyService.requestLocationUpdate()
        // 处理入口 props
        if (pendingRouteId) {
            Qt.callLater(function() {
                var route = routeService.getById(pendingRouteId)
                if (route && route.id) {
                    mapPage.addOrToggleRoute(route)
                }
            })
        } else if (pendingTravelId) {
            Qt.callLater(function() {
                var travel = travelService.getById(pendingTravelId)
                if (travel && travel.id) {
                    mapPage.addOrToggleTravel(travel)
                }
            })
        }
        // 2026-10-29 (问题2): 复原上次的选中集 (路线/自驾/轨迹). 排在入口 props 之后:
        //   pendingRouteId 那一条要先落进 selectedRouteIds, 复原循环才会跳过它而不是把它
        //   当成"没选过"再 toggle 一次 (toggle 会把它取消掉).
        Qt.callLater(mapPage._restoreSelection)
        // 2026-09-19: 申请运行时权限 (ACCESS_FINE_LOCATION + CAMERA)
        // Qt.callLater 把申请推到本页渲染完成之后, 免得启动期 Qt 主线程忙时弹窗排队
        Qt.callLater(mapPage._ensurePermissions)

        // 2026-09-20: 物种危险等级缓存初始化. 之前在 marker delegate 的 _lvl binding
        //   里调 speciesService.getDangerous(1), 会反向写 mapPage._speciesCache →
        //   binding loop ("Binding loop detected for property 'text'" at MapPage.qml:324).
        //   现在提前在 onCompleted 一次性查全写入 _speciesCache, marker 委托只读.
        try {
            var allDanger = speciesService.getDangerous(1) || []
            var m = {}
            for (var i = 0; i < allDanger.length; i++) {
                m[allDanger[i].id] = allDanger[i].dangerLevel
            }
            mapPage._speciesCache = m
        } catch (e) {
            mapPage._speciesCache = {}
        }
        // 2026-10-09: 首次加载物种标注 (后续由 dataChanged → _reloadSpecies 刷新)
        mapPage._reloadSpecies()
    }

    Component.onDestruction: {
        if (compassSensor) compassSensor.active = false
    }

    function centerOnMe() {
        map.center = QtPositioning.coordinate(currentLat, currentLon)
        map.zoomLevel = Math.max(map.zoomLevel, 13)
    }

    // 「目标」Tab 里点一行 → 把地图挪到那个点, 面板**收到入口条** (两档工作台, 2026-10-28).
    //   只挪中心不改缩放档位太多: 用户可能已经在看全局, 跳到 z16 反而丢上下文.
    //   原来这里 close() 是把整个抽屉关掉 —— 两档制下 close() 意味着"工作台没了,
    //   得重新点把手才回得来"; 收一档 (fold) 保留四格入口, 地图也立刻露出来.
    function focusTarget(t) {
        if (!t) return
        var la = Number(t.lat), lo = Number(t.lon)
        if (!mapPage._validCoord(la, lo)) return
        map.center = QtPositioning.coordinate(la, lo)
        map.zoomLevel = Math.max(map.zoomLevel, 14)
        bottomSheet.fold()
    }

    // 2026-10-09: 重载物种标注 (MapItemView.model = speciesLocations 绑定).
    //   dataChanged 时重新取列表并整体替换数组 (新引用触发 MapItemView 重建).
    function _reloadSpecies() {
        try {
            mapPage.speciesLocations = mapService.getSpeciesLocations() || []
        } catch (e) {
            mapPage.speciesLocations = []
        }
    }

    // 2026-10-29 (问题2): 选中集回写窗口会话 (见 Main.qml 的 mapSel*) . 底栏切格与
    //   换底图都会重建本页, 页内的坐标数组活不过重建 —— 不写出去, 重建后地图上就只剩
    //   从盘上重读的物种标注, 用户读作"有标注没有线".
    function _persistSelection() {
        if (!mapPage._selectionRestored) return
        var w = mapPage._appWin
        if (!w) return
        var routes = [], travels = []
        for (var i = 0; i < mapPage.routeOverlays.length; ++i) {
            var o = mapPage.routeOverlays[i]
            // 自驾借用了路线那一套 overlay, 复原时要走 travelService, 所以分开记
            if (o.kind === "travel") travels.push(o.id)
            else routes.push(o.id)
        }
        var tracks = []
        for (var k = 0; k < mapPage.trackOverlays.length; ++k)
            tracks.push(mapPage.trackOverlays[k].id)
        w.mapSelRouteIds = routes
        w.mapSelTravelIds = travels
        w.mapSelTrackIds = tracks
    }
    // 只挂这两条: 所有加/删线最终都落在两个 overlay 数组上 (selectedXxxIds 是它们的影子).
    onRouteOverlaysChanged: mapPage._persistSelection()
    onTrackOverlaysChanged: mapPage._persistSelection()

    // 2026-10-29 (问题2): 进页时按 id 复原上一次的选中集. 查不到的 (已删) 只打日志:
    //   进页先弹三条"复原失败"比丢线更烦人. 轨迹走 silent 一档, 同理.
    function _restoreSelection() {
        var w = mapPage._appWin
        var rids = (w && w.mapSelRouteIds) ? w.mapSelRouteIds : []
        var vids = (w && w.mapSelTravelIds) ? w.mapSelTravelIds : []
        var kids = (w && w.mapSelTrackIds) ? w.mapSelTrackIds : []
        var i
        for (i = 0; i < rids.length; ++i) {
            if (mapPage.selectedRouteIds.indexOf(rids[i]) >= 0) continue
            var r = routeService.getById(rids[i])
            if (r && r.id) mapPage.addOrToggleRoute(r)
            else console.warn("[map] 复原路线失败: " + rids[i])
        }
        for (i = 0; i < vids.length; ++i) {
            if (mapPage.selectedRouteIds.indexOf(vids[i]) >= 0) continue
            var t = travelService.getById(vids[i])
            if (t && t.id) mapPage.addOrToggleTravel(t)
            else console.warn("[map] 复原自驾失败: " + vids[i])
        }
        for (i = 0; i < kids.length; ++i) {
            if (mapPage.selectedTrackIds.indexOf(kids[i]) >= 0) continue
            mapPage.addOrToggleTrack(kids[i], null, true)
        }
        mapPage._selectionRestored = true
        // 入口 props (pendingRouteId 等) 带进来的那一条不在窗口列表里, 复原完再回写一次,
        // 否则下一次重建又会把它弄丢.
        mapPage._persistSelection()
        if (mapPage.routeOverlays.length + mapPage.trackOverlays.length > 0)
            mapPage.fitBoundsToRoutes()
    }

    // 2026-10-29 (问题6): 删掉一条"在哪儿见过"的标注. 数据侧只删 species_<id>.json,
    //   物种本身在图鉴里不受影响; 删完 C++ 会 emit dataChanged, 上面的 Connections 负责
    //   把盘上标记与列表刷掉, 这里不重复 reload.
    function deleteMarkedSpecies(locId) {
        if (!locId) {
            // 老数据 (旧「标注这里」写进来的那批) 的文件名里没有这条 id, 删不了
            toast.warn("这条标注没有文件 id, 删不掉")
            return
        }
        var res = mapService.deleteSpeciesLocation(locId)
        if (res && res.ok) {
            // 详情弹层正指着这条标注, 留着它就是在展示一条已经不存在的数据
            markerDetailDialog.close()
            toast.success("已删除这条标注")
        } else {
            console.warn("deleteSpeciesLocation failed:",
                         res && res.error ? res.error.message : res)
            toast.error("删除失败: "
                        + ((res && res.error && res.error.message) || "接口没给原因"))
        }
    }

    // 2026-10-26「精度到 1 m」: 标注弹层里说清这一点准不准. 老数据没有 accuracy /
    //   altitude 键 (新写路径"未知就不写那一键"), 这时整段不出现 —— 补个 "±0 m"
    //   会被读成"这个点极准", 那是假读数.
    function markPrecision(m) {
        var out = ""
        var acc = Number(m.accuracy)
        if (isFinite(acc) && acc > 0) out += " · ±" + Math.round(acc) + " m"
        var alt = (m.altitude === undefined || m.altitude === null)
                    ? Number.NaN : Number(m.altitude)
        if (isFinite(alt)) out += " · 高程 " + Math.round(alt) + " m"
        if (out === "") out = " · 该点没有精度/高程读数"
        return out
    }

    function annotateHere() {
        // 2026-10-26 A27 真机: 这颗按钮原来直接落盘一条 speciesId / name / category
        //   三个全空的标注, 后果是点开弹层只剩"物种标注 + 经纬度", ①营地方位条里堆
        //   一串「未命名标注」(机上 28 条全是这么来的) —— 用户按了等于没拿到任何可读
        //   信息. 它和长按选点本来就是同一件事, 所以改成把当前视野中心交给同一个
        //   「添加标注」对话框, 由对话框选类别/物种后再写 (那条路径实测是好的).
        // 坐标取 viewLat/viewLon: 这是"标注这里", 用户先把地图拖到目标再点, 所以不能用
        //   GPS 位置 (无权限时恒为写死的北京默认值). 两者由 viewportCommitTimer 同步.
        mapPage.pendingAnnotateCoord = map.center
        addAnnotateDialog.open()
    }

    function onPhotoTaken(uri) {
        if (uri && uri.length > 0) {
            lastCapturedPhoto = uri
            // 提取 EXIF GPS + 加到 mapService
            var exif = mapService.extractExif(uri.replace("file://", ""))
            if (exif && exif.lat && exif.lon) {
                // 照片 EXIF 里只有经纬度, 没有 ± 精度也没有可信高程 —— 传 NaN,
                // 那一键整条不写 (2026-10-26「精度到 1 m」; 原来这里写死 0)
                mapService.addSpeciesLocation("", "", "", exif.lat, exif.lon,
                                              Number.NaN, "field_guide", Number.NaN)
            } else if (mapPage.hasFix) {
                // 没 EXIF 就用自己的定位; 两者都没有就不写 —— currentLat/Lon 在无授权时
                // 是写死的北京默认值, 标上去等于给用户攒一批假点 (同 ③ 详情页规则②).
                // 这条走的是 GPS, 高程与 ± 精度都是实测值, 原样带给 C++.
                mapService.addSpeciesLocation("", "", "", currentLat, currentLon,
                                              mapPage.altM, "field_guide", mapPage.accM)
            } else {
                console.warn("onPhotoTaken: 无 EXIF 且无定位, 不写标注")
            }
        }
    }

    // 2026-09-15: 灰色底色, 瓦片未加载时不至于全黑
    Rectangle {
        anchors.fill: parent
        color: CommonOptions.colorText
        z: -1
    }

    // 2026-10-22 #98: 本页自己的 PositionSource 已删, 位置只从 emergencyService 读
    // (见文件头那组属性绑定). 起流在 Component.onCompleted 里调 requestLocationUpdate().

    // 2026-10-09: 底图「真多源切换」. Qt6 OSM plugin 只在 Map.plugin 赋值瞬间
    //   读取 PluginParameter, 运行期改 .value 无效; 且 OSM plugin 通常只有 1 个
    //   supportedMapType (旧 activeMapType[Math.min(...)] 是假切换根因).
    //   2026-10-20 修正这条说法: Map.plugin 不只是「只在赋值瞬间读参数」, 它压根
    //   只允许赋一次 (write-once), 造新 Plugin 再换进去会被 Qt 直接忽略 → 切底图
    //   从来没生效过. 现在切换走 _rebuildForBaseMap 重建本页, 只依赖
    //   osm.mapping.host 的 path base. 五源见 mapPage._baseMaps.
    //   !!! 注意: Map 初值必须是非空 Plugin (见 Map 内注释), 否则 setPlugin 空指针崩.
    // 2026-10-19 白底真根因 (容器内离线复现, 探针见 D:\build_docker\_scratch_debug\
    //   maptest_20261019\ —— 仓库外的调试沙盒, 不在 app/ 下 + doc 记录):
    //   QtLocation 6.7 的 OSM 插件 **不会** 替换 osm.mapping.host 里的
    //   {z}/{x}/{y} —— 它把花括号原样百分号编码, 然后在整串 URL 末尾 **追加**
    //   "<z>/<x>/<y>.png". 本地探针实测 (http://127.0.0.1:8099/ 日志):
    //     模板 ".../{z}/{x}/{y}.png" → 实际请求 "/%7Bz%7D/%7Bx%7D/%7By%7D.png5/25/11.png"
    //     模板 ".../base/"           → 实际请求 "/base/5/25/11.png"   ← 唯一正确写法
    //   所以旧列表里所有带占位符的模板 (Esri / 高德 / opentopomap) 拼出来全是 404,
    //   而 Map.error 又不因单张瓦片失败置位 (err=0) → 整屏白底且无任何报错.
    //   结论: host 只能是 "以 / 结尾的 base", 且源必须支持 z/x/y(.png) 路径.
    //   由此排除: Esri (要 z/y/x, 顺序反了会取到另一块的合法瓦片, 图是错的),
    //             高德 / 天地图 (要 ?x=&y=&z= 查询串, 追加路径后 URL 非法).
    //   保留并实测可达 (简中网络, 2026-10-19 curl 全部 200 image/png):
    //     tile.openstreetmap.de / basemaps.cartocdn.com 三个图层.
    //     ^^^ 这行到 2026-11-02 已经不作数了, CARTO 那三个见下面.
    //   想要卫星图: 需在自己 CDN 上铺一个 z/x/y → Esri z/y/x 的反向代理, 再回来加源.
    //
    // 2026-11-02 换源 (模拟器复核六项时撞出来的): CARTO 三个图层**全部失效**.
    //   它现在对免费 rastertiles 强制要 API key, 但**不返回 4xx** —— 返回
    //   HTTP 200 + image/png + 一张 2049 字节的 "API KEY REQUIRED /
    //   carto.com/basemaps/apikey" 水印瓦片 (本机 curl 实测并肉眼看过那张图).
    //   后果比"源挂了"更糟: _probeBaseMap 只看 tileProbe 的 Image.Ready,
    //   200 即 _probeOk=true → failover 以为探过了, 永远停在水印源上, 用户看到
    //   一张永久灰底带英文水印的地图, 且**没有任何报错提示**.
    //   只要 0 号源不可达就会稳定落到这里 (模拟器 guest 网络受限, 实测就是这么中的).
    //   → 三枚 CARTO 源摘掉. 「彩色路网」换成 2026-11-02 实测 200 / 32071 字节的
    //     真瓦片源 tile.openstreetmap.fr/osmfr; 「浅色底图」「暗色底图」暂无免 key
    //     且实测可达的等价替代 (opentopomap 连不上, Stadia/Thunderforest/MapTiler
    //     一律要 key, Esri 是 z/y/x 顺序不兼容), 宁缺不滥 —— 留一个只会吐水印的源
    //     在菜单里, 比少两个选项伤害大得多. 等拿到 CARTO key 再按原样加回.
    readonly property var _baseMaps: [
        { name: "标准地图",
          // OSM 德国镜像, 带中文地名。2026-11-02 本机复测 z5/5/12 仍 200 / 25502 字节。
          host: "https://tile.openstreetmap.de/",
          copyright: "© OpenStreetMap contributors (tile.openstreetmap.de)" },
        { name: "彩色路网",
          // 原为 CARTO Voyager (见上, 已失效). osmfr 同为 OSM 数据 + 彩色渲染,
          // 户外看路/看水系够用. 注意 openstreetmap.fr 是社区志愿者机器, 官方不
          // 欢迎高频抓取 —— 它排在德国镜像之后, 只在 failover / 手动选时才会用到.
          host: "https://a.tile.openstreetmap.fr/osmfr/",
          copyright: "© OpenStreetMap contributors (tile.openstreetmap.fr)" },
        { name: "OSM 主站(需代理)",
          host: "https://tile.openstreetmap.org/",
          copyright: "© OpenStreetMap contributors" }
    ]
    // _rebuildForBaseMap: 把选择写进窗口级「底图会话」, 然后重建本页 (见 Main.qml).
    //   defaultPlugin 在 attach 前就按会话里的索引取 host, 所以新页天然用新源.
    //
    // 2026-10-16 白底根因修复: Qt6 OSM 插件里 `osm.mapping.host` 只对名为
    //   "Custom URL Map" 的 mapType 生效; 插件默认激活的是 index 0 的 "Street Map"
    //   (走内置 MapTiler 源, 而 providersrepository.disabled=true 又把它关掉) →
    //   host 被完全忽略 → 瓦片永远拉不到 → 白底 (且 Map.error 不触发, err=0).
    //   截图证据: 诊断横幅 mapTypes=7 [...,Custom URL Map] active=Street Map.
    //   旧注释误以为 "OSM plugin 通常只有 1 个 mapType", 实测有 7 个.
    //   修法: 每次 plugin 赋值后把 activeMapType 切到 "Custom URL Map".
    function _selectCustomMapType() {
        var types = map.supportedMapTypes
        if (!types || types.length === 0) return false
        var pick = null
        for (var i = 0; i < types.length; i++) {
            var n = (types[i].name || "").toLowerCase()
            if (n.indexOf("custom url") >= 0) { pick = types[i]; break }
        }
        // 兜底: OSM 插件把 Custom URL Map 放最后, 名称匹配不到时取末项
        if (!pick) pick = types[types.length - 1]
        if (map.activeMapType !== pick) {
            map.activeMapType = pick
            console.log("[map] activeMapType -> " + (pick ? pick.name : "null"))
        }
        return true
    }
    // 换底图 = 重建这一页. 2026-10-20 查明 (#14/#21 真根因, 两层叠在一起):
    //   ① Plugin 类型上从来没有 setParameter() —— plugins.qmltypes 里
    //      QDeclarativeGeoServiceProvider 的 parameters 是 isReadonly 列表
    //      (defaultProperty), 只能由声明式写进去。原来三行 p.setParameter(...)
    //      抛 TypeError 直接中断函数, 紧跟其后的 map.plugin = p 根本没执行。
    //      qmllint 实测: Member "setParameter" not found on type "Plugin"
    //   ② 改成声明式造 Plugin 也不管用: Qt6 的 Map.plugin 是 write-once ——
    //      QDeclarativeGeoMap::setPlugin() 开头就 `if (m_plugin) { qmlWarning
    //      ("Plugin is a write-once property, and cannot be set again."); return; }`
    //      (v6.7.2 源码 + 容器内最小用例实测一致). 运行期换 Plugin 永远无反应.
    //   结论: 新的 osm.mapping.host 只能在「新 Map 第一次 attach plugin」时生效,
    //   而 Map 内联在本页里 → 只能重建本页。Map 挪进 Loader/独立文件要重接 27 处
    //   map.xxx 引用和 4 个 MapItemView, 收益不比代价大, 不走。
    function _rebuildForBaseMap(idx) {
        var w = mapPage._appWin
        if (!w) return
        w.mapBaseMapIndex = idx
        w.mapFailoverTries = mapPage._tileFailover
        // 记下正在看的那块视野, 重建后落回同一处 (中心/缩放是命令式给的, 见 #43)
        w.mapViewLat = mapPage.viewLat
        w.mapViewLon = mapPage.viewLon
        w.mapViewZoom = map.zoomLevel
        // 不能在本页自己的点击回调里同步销毁自己: stackView.clear(Immediate) 会
        //   当场 delete 掉此刻还在 JS 调用栈上的这个 Page → callLater 等本轮返回.
        Qt.callLater(function () { w.restartBand("map") })
    }

    // 2026-10-16: 底图可达性探测 (真正的白底兜底).
    //   Map.error 只在 GeoServiceProvider 出错时置位, 单张瓦片 HTTP 失败不会触发,
    //   所以原先挂在 onErrorChanged 上的 failover 实际是死代码 —— 源不可达时
    //   永远白底且无任何信号. 这里用 Image 直接拉一张当前视野的真实瓦片探测
    //   (与 QtLocation 走同一套 QNAM/系统 CA), 失败或超时即自动切下一个源.
    function _tileUrlAt(src, z, lat, lon) {
        // 必须与 OSM 插件的拼法逐字一致, 否则探测的是插件根本不会请求的 URL:
        //   插件把 host 参数当纯 base, 在末尾追加 "<z>/<x>/<y>.png" (2026-10-19 实测).
        var n = Math.pow(2, z)
        var x = Math.floor((lon + 180.0) / 360.0 * n)
        var rad = lat * Math.PI / 180.0
        var y = Math.floor((1.0 - Math.log(Math.tan(rad) + 1.0 / Math.cos(rad)) / Math.PI) / 2.0 * n)
        return src.host + z + "/" + x + "/" + y + ".png"
    }

    function _probeBaseMap() {
        var src = mapPage._baseMaps[mapPage.currentBaseMap]
        if (!src) return
        mapPage._probeOk = false
        // z=5 覆盖国内主要区域, 各源该层级均有瓦片
        mapPage._probeUrl = mapPage._tileUrlAt(src, 5, mapPage.currentLat, mapPage.currentLon)
        tileProbeTimer.restart()
        console.log("[map] probe " + src.name + " " + mapPage._probeUrl)
    }

    function _failoverToNext(reason) {
        if (mapPage._probeOk) return
        if (mapPage._tileFailover >= mapPage._baseMaps.length - 1) {
            // 不加 "[诊断]" 前缀 → 不会被 diagAutoHideTimer 自动清掉, 常驻提示
            mapPage._mapErrorMsg = "[底图] " + reason + ": 已遍历全部 "
                    + mapPage._baseMaps.length + " 个源, 当前网络均不可达"
            console.warn("[map] " + reason + ", 无更多源可切")
            return
        }
        mapPage._tileFailover++
        var next = (mapPage.currentBaseMap + 1) % mapPage._baseMaps.length
        console.warn("[map] " + reason + " → 自动切底图 " + next
                     + " (" + mapPage._baseMaps[next].name + ")")
        mapPage.currentBaseMap = next
        mapPage._rebuildForBaseMap(next)
    }
    // 没有 onCurrentBaseMapChanged: 换底图统一由 baseMapMenu (手动) 与
    //   _failoverToNext (自动) 显式调 _rebuildForBaseMap. 挂在 changed 上会有
    //   一条隐蔽的循环 —— currentBaseMap 的初值是「窗口级会话」的活绑定, 万一
    //   ApplicationWindow.window 晚一步才解析出来, 它会从 0 变成用户上次挑的索引,
    //   于是「进页 → 重建 → 再进页」无限重建.

    // 探测用的隐形瓦片 (1x1, 不显示). 见 _probeBaseMap.
    Image {
        id: tileProbe
        source: mapPage._probeUrl
        visible: false
        width: 1
        height: 1
        asynchronous: true
        onStatusChanged: {
            if (mapPage._probeUrl === "") return
            if (status === Image.Ready) {
                mapPage._probeOk = true
                tileProbeTimer.stop()
                console.log("[map] probe OK")
            } else if (status === Image.Error) {
                tileProbeTimer.stop()
                mapPage._failoverToNext("瓦片探测失败")
            }
        }
    }
    Timer {
        id: tileProbeTimer
        interval: 8000
        onTriggered: {
            if (!mapPage._probeOk)
                mapPage._failoverToNext("瓦片探测超时")
        }
    }

    // 拖动/捏合停下来 260ms 后提交一次可视中心, 供「目标」半径查询与标注使用.
    Timer {
        id: viewportCommitTimer
        interval: 260
        onTriggered: {
            var c = map.center
            mapPage.viewLat = c.latitude
            mapPage.viewLon = c.longitude
            mapPage.viewZoom = map.zoomLevel
        }
    }

    Map {
        id: map
        anchors.fill: parent
        // 2026-10-09 修复启动崩溃 (SIGSEGV in QDeclarativeGeoServiceProvider::
        //   isAttached, fault addr 0x20, x0=0, tombstone 见 run.txt L4134-4152):
        //   Qt6 QDeclarativeGeoMap::setPlugin() 在 p==null 时不解引用 m_plugin,
        //   而当 p==null && m_plugin==null 时会在「disconnect 旧对象」处对空
        //   m_plugin 调 isAttached() → 空指针崩溃. 所以 plugin 初值绝不可为 null,
        //   必须挂一个非空 Plugin (此前写 plugin: null + onCompleted 里造新 Plugin,
        //   那两次赋值会在「非空→null」和「null→非空」两个方向都踩中该崩溃路径).
        // 2026-10-20: Map.plugin 是 write-once, 换底图只能重建本页 (见
        //   _rebuildForBaseMap), 每次都是「新 Map + 它的第一个 plugin」, 不存在
        //   null 与二次赋值, 崩溃路径整体消失.
        Plugin {
            id: defaultPlugin
            name: "osm"
            PluginParameter {
                name: "osm.mapping.host"
                // 2026-10-16 修复: 原硬编码 _baseMaps[1] (OSM 路网), 与 currentBaseMap
                //   默认值 0 不一致 → 首屏白底. 现在按索引取, 重建后自动跟着会话走.
                // 注意: 这一行是活绑定, 但 attach 只在 Map 首次拿到 plugin 时发生,
                //   之后改它没有效果 (engine 已用旧 host 建好) —— 换源请重建本页.
                value: mapPage._baseMaps[mapPage.currentBaseMap].host
            }
            PluginParameter {
                name: "osm.mapping.copyright"
                value: mapPage._baseMaps[mapPage.currentBaseMap].copyright
            }
            PluginParameter {
                name: "osm.mapping.providersrepository.disabled"
                value: true
            }
        }
        plugin: defaultPlugin
        // 2026-09-16: Qt 6.7 Map 控件没有 statusChanged signal
        // 改用 Component.onCompleted 一次性查 supportedMapTypes 数量
        // 2026-09-28: 增强诊断 (用户授权 "先只加诊断, 不改行为").
        //   目的: 地图白底时区分 3 种可能 — ①plugin 没加载 (mapTypes=0)
        //   ②plugin 加载但 host/regexp 不匹配 (mapTypes>0 但仍白底)
        //   ③瓦片服务不可达 (有 error 信号). 把 plugin/supportsMapping/
        //   每个 mapType 的 name/active 全打出来 + 写到屏幕上 (截图可带证据).
        // 2026-10-09: 删除原「onCompleted 首次重建 plugin」— plugin 初值已是有效源,
        //   无需再重建. 2026-10-20: 换源改走 _rebuildForBaseMap 重建本页 (见上).
        Component.onCompleted: {
            var _names = []
            for (var _i = 0; _i < supportedMapTypes.length; _i++) {
                _names.push(supportedMapTypes[_i].name)
            }
            var _activeName = activeMapType ? activeMapType.name : "null"
            // 2026-09-30 诊断: 把 actual host 打出来 (host 取自 defaultPlugin 的参数).
            // 2026-10-09: 已删除 osm.mapping.regexp, 诊断串同步去掉 tileRegexp.
            console.log("[map] speciesMarkers=" + mapPage.speciesLocations.length)
            var _diag = "[诊断] plugin=" + plugin.name
                      + " supportsMapping=" + plugin.supportsMapping
                      + " availProviders=" + plugin.availableServiceProviders.length
                      + " mapTypes=" + supportedMapTypes.length
                      + " [" + _names.join(",") + "]"
                      + " active=" + _activeName
                      + " err=" + error
            // 2026-09-30: 关键 —— console.log 走 qDebug, release 下易被过滤;
            //   故同时写 _mapErrorMsg (红色横幅) 让截图上带证据.
            console.log("[map onCompleted] " + _diag)
            // 2026-10-19: 不再把诊断串写到屏幕上. 之前白底查因需要截图取证才写横幅,
            //   根因已定位 (见 _baseMaps 注释), 常驻红块反而成了 3.jpg 里最扎眼的问题,
            //   还压住右下角 +/- 缩放按钮. 诊断只留 console.log, 横幅只服务真错误.
            // 2026-10-16 白底修复: 首屏默认 plugin 也要把 activeMapType 切到
            //   "Custom URL Map", 否则 osm.mapping.host 不生效 (见 _selectCustomMapType).
            mapPage._selectCustomMapType()
            // 2026-10-16: 首屏不走换底图重建 (见上), 所以可达性探测要在这里起一次;
            //   默认源若在当前网络不可达, 探测会自动切到下一个可达源.
            Qt.callLater(mapPage._probeBaseMap)
            // center / zoomLevel 已无声明式绑定 (见上), 初值在这里命令式给一次.
            // 优先级: 导航带进来的 pendingFocus* > 上一次看的位置 (换底图重建时
            //   由窗口级会话恢复) > GPS 位置.
            map.center = isFinite(mapPage.pendingFocusLat) && isFinite(mapPage.pendingFocusLon)
                         ? QtPositioning.coordinate(mapPage.pendingFocusLat, mapPage.pendingFocusLon)
                         : QtPositioning.coordinate(mapPage.viewLat, mapPage.viewLon)
            map.zoomLevel = mapPage.currentZoom
            // 2026-10-23 #103: 首档区间要预热 (上面 zoomLevel 若与初值相同不会发 changed,
            // 就轮不到 onZoomLevelChanged 里那次 reset). 官方同理, MapView.qml:52.
            map.resetPinchMinMax()
        }
        // 2026-10-16: supportedMapTypes 在 plugin 赋值后异步重建 → 每次刷新都兜底
        //   把激活类型切到 Custom URL Map (覆盖 callLater 时序未命中的情况).
        onSupportedMapTypesChanged: mapPage._selectCustomMapType()
        // 2026-10-09: 删除 activeMapType 表达式 — 多源由 host 切换承担,
        //   不再依赖 supportedMapTypes 索引 (OSM plugin 通常只有 1 个 mapType,
        //   这正是旧「假切换」的根因). 保持默认 activeMapType.
        onErrorChanged: {
            if (error !== null && error !== undefined) {
                // 2026-09-28: 增强诊断 — 打全 plugin 状态 (之前只 console.warn(error)).
                var _errDiag = "地图错误 err=" + error
                             + " | plugin=" + plugin.name
                             + " supportsMapping=" + plugin.supportsMapping
                             + " mapTypes=" + supportedMapTypes.length
                             + " active=" + (activeMapType ? activeMapType.name : "null")
                console.warn("[map onErrorChanged] " + _errDiag)
                // 2026-10-16: 改走统一的 _failoverToNext (原内联切源逻辑与探测重复).
                //   遍历完仍失败时由它写入常驻横幅.
                // L12: error 是 Qt Location 自己的英文原文, 只留在上面那行日志;
                //   横幅是给用户看的, 只写中文那一句 (英文串进屏幕不需要经过 src/, 这一路以前漏了).
                mapPage._failoverToNext("底图瓦片读取失败")
            }
        }
        // 2026-10-19 (用户反馈"地图需要可以手动移动"): 这里原来写
        //   center: QtPositioning.coordinate(mapPage.currentLat, mapPage.currentLon)
        //   zoomLevel: mapPage.currentZoom
        // 声明式绑定会把视图锁死: Map 拖拽走 C++ setCenter, 不会解除 QML 绑定,
        // 于是每帧拖完又被绑定拉回原位, 表现就是"地图推不动". 初值改到
        // Component.onCompleted 里命令式设置 (见 mapViewport 注释), 反向同步走
        // onCenterChanged / onZoomLevelChanged.
        minimumZoomLevel: 3
        maximumZoomLevel: 18
        // 2026-10-22 #98: 原来这里写 hasFix ? currentHeading : 0, 而 currentHeading 只由
        // 本页那个从没出过数的 PositionSource 提供 → 真机上恒为 0, 地图一直是正北朝上.
        // 删掉 PositionSource 之后保持这个观感 (用户评审的截图就是正北朝上): 让地图跟着
        // 罗盘转是另一件事, 要改得先出稿看过再定, 不在这一轮顺手改.
        bearing: 0

        // 可视范围 → mapPage.viewLat/viewLon/viewZoom. 用定时器合并一次连续拖动/捏合,
        // 只在一阵操作停下来之后提交一次, 避免「目标」Tab 每帧重查.
        onCenterChanged: viewportCommitTimer.restart()
        onZoomLevelChanged: {
            viewportCommitTimer.restart()
            // 2026-10-23 #103: 档位一变就重算捏合的倍率区间 (官方 MapView.qml:67 同一件事).
            // 捏合轴是"相对当前 zoom 的倍率", 不重算的话下一次捏合还拿着上一档的区间.
            // pinchAdjustingZoom 用来跳过"捏合自己改 zoom"的那一帧 —— 否则手势进行中
            // 每帧被 resetPinchMinMax 把 persistentScale 打回 1, 地图会在两指下一跳一停.
            if (!map.pinchAdjustingZoom) map.resetPinchMinMax()
        }

        // 2026-10-23 #103 真机 ("可以手动移动, 但不能双指缩放"): 搬 MapView 的时候只搬了
        //   两个处理器, 没搬它这套区间初始化 —— 原来只在 onActiveChanged 里算
        //   scaleAxis.minimum/maximum, 而捏合轴在**手势开始前**就要有合法区间
        //   (官方是 Component.onCompleted + onZoomLevelChanged 两处算, MapView.qml:52/67).
        //   区间没预热时, 处理器算不出可用的 scale 变化, 表现正是"两指按下地图不动".
        property bool pinchAdjustingZoom: false

        function resetPinchMinMax() {
            mapZoomHandler.persistentScale = 1
            // 与官方的唯一差别: 官方在指数上加了 ±1 的余量 (MapView.qml:74~75).
            // 这里不加 —— 倍率轴的 1.0 是"两指没动"的中性值, 地图已经顶到档位边界时
            // (zoom == minimumZoomLevel) 带余量的 minimum 会变成 2, 轴把中性值夹到 2 上,
            // 手指刚按下还没捏就白跳一档. 越界由 onScaleChanged 里的显式夹取兜住.
            mapZoomHandler.scaleAxis.minimum = Math.pow(2, map.minimumZoomLevel - map.zoomLevel)
            mapZoomHandler.scaleAxis.maximum = Math.pow(2, map.maximumZoomLevel - map.zoomLevel)
        }

        // 2026-09-21: 地图错误提示条. 之前白底时用户看不到任何反馈.
        // 2026-10-19 改版 (3.jpg): 原来底部通栏实心红 + 200 字诊断串, 既压住右下
        //   角 +/- 缩放按钮, 又把调试信息当产品文案暴露给用户. 现在:
        //   ① 移到顶部 (紫色页头下方), 不再与任何控件重叠;
        //   ② 半透明 danger 底 + 描边, 不再是整块大红;
        //   ③ 图标走 IconLabel (原来这里混排裸 \ue002 + 中文, 正是"图标方框"的老坑).
        Rectangle {
            id: mapErrorBanner
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: styles.spMd
            anchors.leftMargin: styles.pageMargin
            anchors.rightMargin: styles.pageMargin
            radius: styles.rMd
            color: CommonOptions.withAlpha(CommonOptions.colorDangerBg, 0.92)
            border.color: CommonOptions.colorDanger
            border.width: styles.lineHair
            opacity: 0
            visible: opacity > 0
            height: errRow.implicitHeight + styles.spMd
            z: 999
            Behavior on opacity { NumberAnimation { duration: 250 } }

            MouseArea {
                anchors.fill: parent
                // 2026-09-28: 手动关闭 (替代原 4s 自动消失)
                onClicked: mapErrorBanner.opacity = 0
            }

            RowLayout {
                id: errRow
                anchors.fill: parent
                anchors.margins: styles.spSm
                spacing: styles.spSm

                IconLabel {
                    name: "warning"
                    size: styles.icSm
                    tintColor: CommonOptions.colorDanger
                    Layout.alignment: Qt.AlignTop
                }
                Text {
                    id: errText
                    Layout.fillWidth: true
                    text: mapPage._mapErrorMsg
                    color: CommonOptions.colorDanger
                    font.pixelSize: styles.fsSm
                    wrapMode: Text.WordWrap
                }
            }
        }
        // 2026-10-16: 诊断横幅自动隐藏. 白底根因已定位 (activeMapType 未切到
        //   Custom URL Map), 修好后地图正常渲染, 常驻红框反而是新「地图问题」.
        //   保留 8s 供截图取证; 真正错误 (onErrorChanged 写入) 不启动本定时器 → 常驻.
        Timer {
            id: diagAutoHideTimer
            interval: 8000
            onTriggered: {
                if (mapPage._mapErrorMsg.indexOf("[诊断]") === 0)
                    mapPage._mapErrorMsg = ""
            }
        }
        Connections {
            target: mapPage
            // 2026-10-08 修复: 原函数名 on_mapErrorMsgChanged 大小写错.
            //   Qt 属性变更信号规则是 on<Prop>Changed, 而属性 _mapErrorMsg 去掉
            //   前导下划线后首字母大写 → 正确名字是 on_MapErrorMsgChanged.
            //   run.txt L3548 实证 Qt6 运行时告警:
            //   ""on_mapErrorMsgChanged" is not a properly capitalized signal handler
            //    name. "on_MapErrorMsgChanged" would be correct."
            //   旧名只是兼容触发, 名字本身是错的, 改为正确名消除告警.
            function on_MapErrorMsgChanged() {
                console.log("[map] banner update len=" + mapPage._mapErrorMsg.length)
                mapErrorBanner.opacity = mapPage._mapErrorMsg.length > 0 ? 1 : 0
                // 仅对纯诊断串排程自动隐藏; 真错误保持常驻
                if (mapPage._mapErrorMsg.indexOf("[诊断]") === 0) {
                    diagAutoHideTimer.restart()
                }
            }
        }

        // 2026-10-09: 监听 MapService 全局 dataChanged → 刷新物种标注 (MapItemView).
        //   修复旧 Repeater 一次性绑定「永不刷新」问题 (新增标注需重进页面才出现).
        Connections {
            target: mapService
            function onDataChanged() {
                mapPage._reloadSpecies()
            }
            // 0.0.9 真机: 删一条已加载的轨迹后, 列表计数回 0 而地图上的「已选 1」还列着
            //   那条死轨迹 (分析图/× 都还能点)。dataChanged 只管标注, 删除要按 id 摘画线。
            function onTrackDeleted(trackId) {
                mapPage.removeTrack(trackId)
            }
        }

        // 2026-10-20 #61: 中心的 DirectionCompassOverlay 删除 —— 右上已经有一枚迷你盘,
        //   同一屏两个罗盘互相抢读法, 而中心环跟着平移缩放走, 低 zoom 下字号糊.
        //   朝向读数只保留 MapInstrumentOverlay 里那一个 Dial.

        // 当前位置 (2026-10-26 真机: "个人位置原点无方向指示 / 移动不能实时变化"):
        //   原来这颗点是一颗 14px 实心 Rectangle —— 既没有朝向, 也不说"这个点有多准".
        //   现在三层: 精度圈 (±acc 按当前比例尺换算成像素) + 方向楔 (罗盘优先, 罗盘
        //   不出数时用 GPS 航向) + 蓝点本体. 两个附加层只在真有这个数时才画: 没精度
        //   读数不画圈, 罗盘与航向都没有就不画楔 (规则: 不给一个 0° 的假方向).
        MapQuickItem {
            id: meMarker
            coordinate: QtPositioning.coordinate(mapPage.currentLat, mapPage.currentLon)
            anchorPoint.x: meItem.width / 2
            anchorPoint.y: meItem.height / 2
            sourceItem: Item {
                id: meItem

                // ±acc (米) → 屏幕像素. 中心点纬度算的比例尺, 点位与中心差几屏宽度
                //   以内误差不到 1%, 不值得为此再引一层投影.
                readonly property real ringPx: {
                    if (!isFinite(mapPage.accM) || mapPage.accM <= 0) return 0
                    if (!isFinite(mapPage._metersPerPixel) || mapPage._metersPerPixel <= 0) return 0
                    return Math.min(400, mapPage.accM / mapPage._metersPerPixel)
                }
                readonly property bool showRing: ringPx >= 4
                readonly property real dirDeg: mapPage.effHeadingDeg
                readonly property bool showDir: mapPage.hasEffHeading

                // 56 = 装下 26px 长的方向楔; Canvas 会把超出自身边界的绘制裁掉,
                //   所以Item 要在"只画楔不画圈"时也大过那颗 14px 的点.
                width: Math.max(14, showDir ? 56 : 0, 2 * ringPx)
                height: width

                Canvas {
                    id: meCanvas
                    anchors.fill: parent
                    antialiasing: true

                    // Canvas 只因为它"自己的"属性变化而重画. dirDeg/ringPx 挂在
                    //   meItem 上, 必须在本地引一份再各自 requestPaint —— 直接 onPaint
                    //   里读 meItem 会画一次就再也不刷 (同 Dial.qml 的 Connections 那条坑).
                    property real dir: meItem.dirDeg
                    property real ring: meItem.ringPx
                    property bool hasRing: meItem.showRing
                    property bool hasDir: meItem.showDir
                    onDirChanged: requestPaint()
                    onRingChanged: requestPaint()
                    onHasRingChanged: requestPaint()
                    onHasDirChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Component.onCompleted: requestPaint()

                    function pt(deg, r) {
                        // 屏幕 y 向下, "北=上"要减 90° (与方位盘同一套换算)
                        var a = (deg - 90) * Math.PI / 180
                        return [width / 2 + r * Math.cos(a), height / 2 + r * Math.sin(a)]
                    }

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var cx0 = width / 2
                        var cy0 = height / 2

                        // 1. 精度圈
                        if (hasRing && ring > 0) {
                            ctx.beginPath()
                            ctx.arc(cx0, cy0, ring, 0, 2 * Math.PI)
                            ctx.fillStyle = CommonOptions.css(CommonOptions.colorAccent, 0.14)
                            ctx.fill()
                            ctx.lineWidth = 1
                            ctx.strokeStyle = CommonOptions.css(CommonOptions.colorAccent, 0.55)
                            ctx.stroke()
                        }

                        // 2. 方向楔: 信号橙, 与盘上的指针同色 —— 同一个"朝向"语义
                        if (hasDir) {
                            var tip = pt(dir, 26)
                            var left = pt(dir - 34, 7)
                            var right = pt(dir + 34, 7)
                            ctx.beginPath()
                            ctx.moveTo(tip[0], tip[1])
                            ctx.lineTo(left[0], left[1])
                            ctx.lineTo(right[0], right[1])
                            ctx.closePath()
                            ctx.fillStyle = CommonOptions.css(CommonOptions.colorBlaze)
                            ctx.fill()
                        }

                        // 3. 点本体 (2px 描边保证压在浅色底图上还看得清)
                        ctx.beginPath()
                        ctx.arc(cx0, cy0, 7, 0, 2 * Math.PI)
                        ctx.fillStyle = CommonOptions.css(CommonOptions.colorAccent)
                        ctx.fill()
                        ctx.lineWidth = 2
                        ctx.strokeStyle = CommonOptions.css(CommonOptions.colorTextOnAccent)
                        ctx.stroke()
                    }
                }
            }
        }

        // 物种标注 - 点击看详情 (按 dangerLevel 着色, 危险的高亮红色)
        // 2026-10-09: Repeater → MapItemView (视口虚拟化, 只为可见元素建 delegate),
        //   model 绑 mapPage.speciesLocations (NOTIFY-able), dataChanged 时整体替换触发刷新.
        MapItemView {
            id: speciesMarkerView
            model: mapPage.speciesLocations
            delegate: MapQuickItem {
                required property var modelData
                coordinate: QtPositioning.coordinate(modelData.lat, modelData.lon)
                anchorPoint.x: 12
                anchorPoint.y: 12
                sourceItem: Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    // 2026-09-15: 按危险等级着色 - 查 speciesId 反查 dangerLevel
                    // (species_locations 没存 dangerLevel, 这里查 speciesService 反推)
                    // 2026-09-20 修: 缓存初始化放到 mapPage.onCompleted, _dangerLevel
                    //   不再写 mapPage 属性, 避免 binding loop
                    // 2026-10-23 #82①: 这段反查体 (含类别/关键词兜底) 原样搬进
                    //   mapPage.dangerLevelOf(), 盘与「目标」Tab 同读一份 —— 以前它只有
                    //   圆点有, 于是同一条毒蛇在盘上是"无危险"灰.
                    readonly property int _lvl: mapPage.dangerLevelOf(modelData)
                    color: {
                        // 缓存未就绪时用灰色, 避免 binding loop
                        if (_lvl < 0) return CommonOptions.colorTextDisabled
                        if (_lvl >= 4) return CommonOptions.colorDanger
                        if (_lvl >= 3) return CommonOptions.colorWarn
                        if (_lvl >= 1) return CommonOptions.colorAmber
                        return CommonOptions.colorSuccess
                    }
                    border.color: CommonOptions.colorTextOnAccent
                    border.width: 2
                    // 2026-10-19: 原 Text 整块走 Material Icons, 里面却返回 ASCII
                    //   "?" / "!" —— 本字体没有 ASCII 字形, 真机上这两种 marker 是空的.
                    //   改 IconLabel 语义名, 未知等级用省略号而不是问号.
                    IconLabel {
                        anchors.centerIn: parent
                        name: {
                            var lvl = parent._lvl
                            if (lvl < 0) return "more_horiz"
                            if (lvl >= 4) return "error"
                            if (lvl >= 1) return "warning"
                            return "place"
                        }
                        size: 12
                        tintColor: CommonOptions.colorTextOnAccent
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            mapPage.markerDetailKind = "species"
                            // 2026-10-19: Dialog.title 走应用默认字体, PUA 码位在这里是方框;
                            //   而且该串还会被 encodeURIComponent 拼进 geo: URI. 只留纯文字.
                            // 2026-10-26 A27: 标题原来硬写 "物种标注" —— 用户点开只看到
                            //   类别名而看不到是哪个物种. 有名报名, 没名如实说没名
                            //   (不给假读数, 也不硬套一个物种名).
                            mapPage.markerDetailTitle = modelData.speciesName
                                                        || "未命名标注"
                            mapPage.markerDetailSub = "经纬度: " +
                                modelData.lat.toFixed(5) + ", " +
                                modelData.lon.toFixed(5)
                                + mapPage.markPrecision(modelData)
                            mapPage.markerDetailSpeciesId = modelData.speciesId || ""
                            mapPage.markerDetailCategory = modelData.speciesCategory || ""
                            mapPage.markerDetailDanger = mapPage.dangerLevelOf(modelData)
                            // 2026-10-29 (问题6): 弹层要能删掉"这一条标注", 句柄是
                            //   species_<id>.json 的 id, 不是图鉴的 speciesId.
                            mapPage.markerDetailLocationId = modelData.id || ""
                            mapPage.markerDetailRouteId = ""
                            mapPage.markerDetailCoord = QtPositioning.coordinate(
                                modelData.lat, modelData.lon)
                            // 记录里没有 source 字段 (src/map/MapService_species.cpp:43-55
                            // 写的是 id/speciesId/speciesName/speciesCategory/lat/lon/
                            // altitude/note/takenAt/dangerLevel), 而两条旧写路径把内部键
                            // ("manual" / "field_guide") 塞进了 addSpeciesLocation 的第 7
                            // 参 = note. 所以这一层把它们翻回人话, 真备注与内部键不混排;
                            // 「来源」那行以前读 modelData.source (恒 undefined) → 永远显示
                            // "(手动)", 那是假读数, 现在按 note 里的实际内部键报.
                            var noteRaw = modelData.note || ""
                            var internal = noteRaw === "field_guide" || noteRaw === "camera"
                                           ? "拍照记录"
                                           : (noteRaw === "manual" ? "手动标注" : "")
                            mapPage.markerDetailNote = internal.length > 0 ? "" : noteRaw
                            mapPage.markerDetailSource = internal
                            mapPage.markerDetailTime = modelData.takenAt || ""
                            markerDetailDialog.open()
                        }
                    }
                }
            }
        }

        // 2026-09-15: 路线 polyline 多选叠加 (selectedRouteIds 对应的所有路线)
        Repeater {
            model: mapPage.routeOverlays
            delegate: MapPolyline {
                required property var modelData
                line.color: modelData.color
                line.width: 5
                path: modelData.path
            }
        }

        // 2026-09-15: 路线 起终点 marker (S / E) - 点击看路线详情
        Repeater {
            model: mapPage.routeMarkers
            delegate: MapQuickItem {
                required property var modelData
                coordinate: modelData.coord
                anchorPoint.x: 11
                anchorPoint.y: 11
                sourceItem: Rectangle {
                    width: 22; height: 22; radius: 11
                    color: modelData.color
                    border.color: CommonOptions.colorTextOnAccent; border.width: styles.lineHair * 2
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: CommonOptions.colorTextOnAccent
                        font.pixelSize: styles.fsMd
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            mapPage.markerDetailKind = "route_endpoint"
                            mapPage.markerDetailTitle = (modelData.label === "S" ? "起点" : "终点") +
                                ": " + (mapPage._routeNameById(modelData.routeId) || "")
                            mapPage.markerDetailSub = "经纬度: " +
                                modelData.coord.latitude.toFixed(5) + ", " +
                                modelData.coord.longitude.toFixed(5)
                            mapPage.markerDetailRouteId = modelData.routeId
                            mapPage.markerDetailCoord = modelData.coord
                            mapPage.markerDetailLocationId = ""
                            markerDetailDialog.open()
                        }
                    }
                }
            }
        }

        // 2026-09-15: 路线 危险点 marker (红色警示) - 点击看危险详情
        Repeater {
            model: mapPage.dangerMarkers
            delegate: MapQuickItem {
                required property var modelData
                coordinate: modelData.coord
                anchorPoint.x: 9
                anchorPoint.y: 9
                sourceItem: Rectangle {
                    width: 18; height: 18; radius: 9
                    color: CommonOptions.colorDanger
                    border.color: CommonOptions.colorTextOnAccent; border.width: styles.lineHair
                    Text {
                        anchors.centerIn: parent
                        text: "!"
                        color: CommonOptions.colorTextOnAccent
                        font.pixelSize: styles.fsSm
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            mapPage.markerDetailKind = "danger"
                            mapPage.markerDetailTitle = (modelData.name || "危险点")
                            mapPage.markerDetailSub = "经纬度: " +
                                modelData.coord.latitude.toFixed(5) + ", " +
                                modelData.coord.longitude.toFixed(5)
                            mapPage.markerDetailRouteId = modelData.routeId
                            mapPage.markerDetailCoord = modelData.coord
                            mapPage.markerDetailLocationId = ""
                            markerDetailDialog.open()
                        }
                    }
                }
            }
        }

        // 2026-09-15: 路径点 (营地/垭口等) - 半透明白底小方块
        Repeater {
            model: mapPage.waypointMarkers
            delegate: MapQuickItem {
                required property var modelData
                coordinate: modelData.coord
                anchorPoint.x: 5
                anchorPoint.y: 5
                sourceItem: Rectangle {
                    width: 10; height: 10; radius: 2
                    color: CommonOptions.colorTextOnAccent
                    border.color: CommonOptions.colorDivider
                    border.width: 1
                    opacity: 0.8
                }
            }
        }

        // 2026-09-15: 轨迹 polyline
        Repeater {
            model: mapPage.trackOverlays
            delegate: MapPolyline {
                required property var modelData
                line.color: modelData.color
                line.width: 4
                path: modelData.path
            }
        }

        // 2026-10-29 (问题2): 单点轨迹的落点. MapPolyline 少于 2 点不画, 而只有 1 个
        //   有效点的轨迹在列表里照样是"已加载" —— 不给这颗点就真的什么都没有.
        //   形状同路线 S/E 标记 (圆点 + 白描边), 小了半档: 它是一个点, 不是一个端点.
        Repeater {
            model: mapPage.trackMarkers
            delegate: MapQuickItem {
                required property var modelData
                coordinate: modelData.coord
                anchorPoint.x: 6
                anchorPoint.y: 6
                sourceItem: Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: modelData.color
                    border.color: CommonOptions.colorTextOnAccent
                    border.width: styles.lineHair * 2
                }
            }
        }

    }

    // ── Map 的手势层 (长按 / 捏合 / 平移) ─────────────────────────────────
    // 2026-10-23 #105: 这三件原来直接挂在 Map 里, 而 Map 铺满整页 —— 抽屉拉开后
    // 它仍然"包含"落在卡片上的触点. qquickdeliveryagent.cpp:2002 pointerTargets()
    // 会把树里**所有**含该触点的 item 拍平成按绘制序优先的列表, 卡片上没人接手的那
    // 次按下会继续往下命中地图的处理器; 之后 deliverUpdatedPoints (:2078) 只把后续
    // move 发给独占抓握者 → 谁先抢到这一笔, 谁拿走整笔手势. 真机实测: 手指在卡片上
    // 滑, 盘心 36.4157→36.3040, 列表一行没动.
    // 处理器唯一的"占地"开关是 parentItem 的几何 (qquickpointerhandler.cpp:786
    // wantsEventPoint → parentContains; handler 自己 0×0 不参与判断), 所以把它们挪
    // 进这块与 Map 同原点、同尺寸的手势层, 抽屉一开就让开抽屉的高度: 卡片里的触点
    // 根本不进候选表, 列表与按钮按自己的规则保住抓握, 地图只剩上面那块.
    // 长按一并挪进来 —— 之前按住卡片空白 0.5 秒也会弹「添加标注」, 同一个因.
    // 换算不用跟着改: centroid.position / point.position 是 parentItem 坐标, 而本层
    // 与 Map 同原点 (只减底边高, 不动原点). offscreen 探针实测 Map::toCoordinate 吃的
    // 正是 item 坐标 —— 400×400 的 Map 放在 scene(60,200), fromCoordinate(center) 得
    // 200,200 而不是 260,400.
    Item {
        id: mapGestureLayer
        anchors.fill: parent
        anchors.bottomMargin: bottomSheet.opened ? bottomSheet.height : 0

        // 2026-09-15: 长按地图 → 在长按点添加物种标注
        // 2026-10-21 #78 (A6 真因): 原来这行写的是 `gesturePolicy: TapHandler.ReleaseWithinBounds`,
        //   而 Qt 6 的 QQuickPointerTapHandler::wantsGrab() 里只有默认的 DragThreshold 走
        //   setPassiveGrab, 其余三种 (WithinBounds / ReleaseWithinBounds / DragWithinBounds)
        //   一律在**按下时**就 setExclusiveGrab —— 独占抓取消解前, Map 内置的平移 DragHandler
        //   拿不到同一个触点, 于是"地图怎么拖都不动, 但 +/- 和程序改 center 都正常".
        //   去掉这一行回到 DragThreshold (被动抓握): 长按照样出 onLongPressed, 拖动交还给地图.
        // 2026-10-20 #61 修参数: longPressed() 这个信号在 Qt 6 是**无参**的, 原来写
        //   `function(eventPoint, button)` → eventPoint 恒 undefined, 一点长按就
        //   "Cannot read property position of undefined", 长按标注从来没通过.
        //   触点要读 TapHandler.point.
        TapHandler {
            id: longPressHandler
            onLongPressed: {
                var p = longPressHandler.point
                if (!p) return
                var coord = map.toCoordinate(p.position)
                if (coord && coord.isValid) {
                    mapPage.pendingAnnotateCoord = coord
                    addAnnotateDialog.open()
                }
            }
        }

        // 2026-10-23 #78 (A1 收口): 平移与捏合的手势引擎.
        // 为什么前两轮修完现象不变: Qt 6.7 的 `Map` 类型自己一个手势件都没有 ——
        // 官方那个"可交互地图" MapView.qml 就是在 Map 里面手写 DragHandler +
        // PinchHandler 拼出来的 (见 /opt/Qt/6.7.2/gcc_64/qml/QtLocation/MapView.qml).
        // #43 解的是 center/zoomLevel 声明式绑定锁死, #78 解的是 TapHandler 独占抓握
        // 饿死地图, 两条都只是在清障, 引擎一直没人补 → "只有手指拖不动, +/- 与程序
        // 改 center 都正常". 下面两块照 MapView 的写法搬过来.
        //
        // 没搬的三样, 都不是嫌麻烦:
        //   - 惯性动画: 要额外 import Qt.labs.animation;
        //   - BoundaryRule on zoomLevel: MapView 用它兜档位, 但 **BoundaryRule 就注册在
        //     Qt.labs.animation 里** (QtLabsAnimation/private/qquickboundaryrule_p.h 的
        //     QML_NAMED_ELEMENT), 而这个模块在 Android Qt 安装目录里根本没有
        //     (容器实测 `ls /opt/Qt/6.7.2/android_arm64_v8a/qml | grep -i labs` = 空),
        //     所以搬不过来. 而 offscreen 探针证实 `Map` 自己**不**夹档位
        //     (maximumZoomLevel: 18 时赋 25 仍是 25), 越界档位的直接后果就是取不存在
        //     的瓦片层级 → 白屏, 与 #14/#21 是同一个观感. 于是下面 onScaleChanged 里
        //     显式夹一次. 另外两条写 zoomLevel 的路本来就夹过: stepZoom() 越界直接
        //     return, CommonOptions::fitBounds 用 qBound(minZoom, z, maxZoom).
        //   - tilt / 旋转: 本页 bearing 固定正北 (见上), 两指旋转是另一件事, 要改先出稿评审.
        // 2026-10-23 真机 (用户: "可以手动移动, 但不能双指缩放") #103. 当时改了两处, 只有
        //   ① 是在 Qt 6.7 源码里证实的, ② 如实标成未证实:
        //   ① 证实: 倍率区间从来没在手势之外预热过 —— 官方 MapView.qml 是在
        //      Component.onCompleted(:52) 与 onZoomLevelChanged(:67) 两处算
        //      resetPinchMinMax 的, 搬过来时这两处全漏了, 只在 onActiveChanged 里算.
        //      现在补成 map.resetPinchMinMax() (见上面 bearing: 0 之后那段).
        //   ② 未证实: 把 PinchHandler 挪到 DragHandler 前面, 与官方 78/128 行的顺序一致.
        //
        // 2026-10-26 A32 真机复验: 用户手动捏合后, stage0.log 里 **一条 [pinch] 都没有**
        //   (同会话有 `[map] speciesMarkers=28`, 证明 console.log 是入库的) → active 从未
        //   翻转, 也就是两指从来没凑成一次合格的多点抓握. ① 早就在码里却现象不变, ② 换
        //   顺序也没换来结果 —— 真因是当年那行 grabPermissions 写反了方向:
        //   PointerHandler.TakeOverForbidden 的含义是"**本**处理器不许去抢别人", 不是
        //   "别人不许来抢本处理器" (原注释理解反了). 于是第一根手指被 DragHandler 独占
        //   平移之后, PinchHandler 抢不回来, eligiblePoints 永远停在 1, 与
        //   qquickmultipointhandler.cpp 里"已被独占抓握的触点直接跳过"那条完全对得上.
        //   现在删掉这行回到默认权限 (CanTakeOverFromItems | CanTakeOverFromHandlersOf
        //   DifferentType), 与官方 MapView.qml 的 PinchHandler 一致 —— 它也没写这项.
        //   担心的"长按标注打断捏合"不成立: 长按走的是 TapHandler.onLongPressed, 默认
        //   权限下反过来是捏合能接管它, 方向是对的.
        //   判据不变, 仍是下面这行日志: 复验必须看到 `active=true pts=2`, 看不到就说明
        //   还有第二个拦路点 (往 parentItem 几何与上层浮层查, 见 #105 抽屉让位).
        PinchHandler {
            id: mapZoomHandler
            target: null
            // 捏合中心对应的经纬度: 一放大就以它为准把地图挪回去, 手指底下的地物不跑偏
            // (类型名是 `geoCoordinate` 不是 C++ 的 QGeoCoordinate —— QtPositioning 就注册
            //  了小写那一个, 写大写是加载期硬错误 "QGeoCoordinate is not a type", 整页白屏)
            property geoCoordinate startCoord
            onActiveChanged: {
                if (active)
                    mapZoomHandler.startCoord = map.toCoordinate(centroid.position, false)
                // 真机查案用的唯一线索: 这个日志决定"两指到底有没有被送到处理器".
                // 只在 active 翻转时打一行, 不在 onScaleChanged 里打 (那是逐帧的).
                // 2026-10-28 A32 复盘: 这里原来写 activeTouchPoints —— Qt 6 没这个属性
                //   (MultiPointHandler 的是 activeTouches). 整条表达式在 console.log 求值
                //   阶段就抛 ReferenceError, 一行都出不来. 于是上一轮把"stage0.log 里 0 条
                //   [pinch]"读成"handler 从未 active", 顺着这个假信号去改 grabPermissions,
                //   而真机上手捏本来就能缩放 (用户 2026-10-27 复验). 判据要成立, 先得保证
                //   这行日志本身打得出来.
                console.log("[pinch] active=" + active + " pts=" + mapZoomHandler.activeTouches.length
                            + " zoom=" + map.zoomLevel)
            }
            onScaleChanged: (delta) => {
                // 与官方同款守卫: 这一步改 zoomLevel 不能反过来触发 onZoomLevelChanged
                // 去 resetPinchMinMax —— 那会在手势进行中把 persistentScale 打回 1,
                // 地图在两指下一跳一停.
                map.pinchAdjustingZoom = true
                var z = map.zoomLevel + Math.log2(delta)
                map.zoomLevel = Math.min(Math.max(z, map.minimumZoomLevel), map.maximumZoomLevel)
                map.alignCoordinateToPoint(mapZoomHandler.startCoord, centroid.position)
                map.pinchAdjustingZoom = false
            }
        }

        DragHandler {
            id: mapPanHandler
            target: null
            onTranslationChanged: (delta) => map.pan(-delta.x, -delta.y)
        }
    }

    // 2026-09-15: 长按地图后弹的"添加标注"对话框
    property var pendingAnnotateCoord: null

    // 2026-09-15: 添加标注对话框 - 类别 + 物种 + 备注 + 自动 dangerLevel
    Dialog {
        id: addAnnotateDialog
        modal: true   // L8 三件套之一: Qt6 的 Popup.modal 默认 false, 不写就是能点穿 (真机 F6)
        title: "添加标注"
        anchors.centerIn: parent
        width: Math.min(420, mapPage.width - 2 * styles.pageMargin)
        // 2026-10-20 #41: Material 风格的 OK/Cancel 没有中文译文, 真机上就是两个英文
        //   钮. 全站弹窗统一收口: standardButtons 关掉, 自己写中文 footer, 背景/前景
        //   显式绑 token (否则继承窗口的 colorBg, 弹层和内容分不出层).
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        padding: styles.spMd

        // 类别 - 用 SpeciesService.Category 枚举 (0=Snake,1=Mushroom,2=Insect,3=Plant,4=Animal)
        property int selectedCategory: 3   // 默认 Plant
        property var speciesList: []
        property string selectedSpeciesId: ""
        property string selectedSpeciesName: ""
        property int computedDangerLevel: 0
        // 2026-10-20: 中文名与存盘的英文键原来是两份并排硬编码的数组, 注释还得提醒
        //   "顺序要对齐". 合成一份: combo 用 labels, 写盘用 keys, 索引同一处.
        readonly property var categoryLabels: ["蛇类", "蘑菇", "昆虫", "植物", "动物"]
        readonly property var categoryKeys: ["snake", "mushroom", "insect", "plant", "animal"]

        onAboutToShow: {
            noteField.text = ""
            // 默认 Plant 类
            selectedCategory = 3
            selectedSpeciesId = ""
            selectedSpeciesName = ""
            computedDangerLevel = 0
            refreshSpeciesList()
            // 2026-11-03 (L11): 原来这里还写了一句 catCombo.currentIndex = 3 —— QML 侧的
            //   命令式赋值会**打断**声明式绑定, 那次复位之后 combo 就再也不跟
            //   selectedCategory 走了, 于是"看着是动物、存进去是植物"又回来. 现在
            //   currentIndex 绑的就是 selectedCategory, 上面那句复位自己会把下拉拽回默认.
            speciesCombo.currentIndex = -1
        }

        function refreshSpeciesList() {
            try {
                speciesList = speciesService.getByCategory(selectedCategory)
            } catch (e) {
                speciesList = []
                toast.warn("加载物种列表失败: " + e)  // 2026-09-20: 切 Toast
            }
            // 类别 +1 (Plant=3 对应植物, 但 Q_ENUM 默认从 0 开始)
            // 上面枚举: Snake=0, Mushroom=1, Insect=2, Plant=3, Animal=4
        }

        function recomputeDanger() {
            // 如果选了物种, 用物种的 dangerLevel; 否则按类别查表
            if (selectedSpeciesId && speciesList && speciesList.length > 0) {
                for (var i = 0; i < speciesList.length; i++) {
                    if (speciesList[i].id === selectedSpeciesId) {
                        computedDangerLevel = speciesList[i].dangerLevel || 0
                        selectedSpeciesName = speciesList[i].commonName || ""
                        return
                    }
                }
            }
            // 类别默认值
            if (selectedCategory === 0) computedDangerLevel = 5  // 蛇
            else if (selectedCategory === 1) computedDangerLevel = 4  // 蘑菇
            else if (selectedCategory === 2) computedDangerLevel = 3  // 昆虫
            else if (selectedCategory === 3) computedDangerLevel = 0  // 植物
            else if (selectedCategory === 4) computedDangerLevel = 2  // 动物
            selectedSpeciesName = ""
        }

        contentItem: ColumnLayout {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                // 2026-10-19: 原来是一个 Text 里 "\ue0c8 坐标" + font.family Material
                //   Icons. 本字体无数字/ASCII 字形 → 坐标数字在真机上直接消失.
                //   图标与文案必须拆成两个节点.
                IconLabel {
                    name: "place"
                    size: 12
                    tintColor: CommonOptions.colorWarn
                }
                Text {
                    Layout.fillWidth: true
                    text: mapPage.pendingAnnotateCoord ?
                          mapPage.pendingAnnotateCoord.latitude.toFixed(6) + ", " +
                          mapPage.pendingAnnotateCoord.longitude.toFixed(6) : ""
                    color: CommonOptions.colorWarn
                    font.pixelSize: styles.fsMd
                    font.bold: true
                    elide: Text.ElideRight
                }
            }

            // 类别
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "类别:"; color: CommonOptions.colorText; font.pixelSize: styles.fsMd; Layout.preferredWidth: 50 }
                ComboBox {
                    id: catCombo
                    Layout.fillWidth: true
                    // 2026-10-19: 本字体没有 snake / mushroom / insect / plant / animal
                    //   专用字形 (\ue92b 实为垃圾桶之类), 原 "码位 + 中文" 混排整串走
                    //   Material Icons → 中文全方框. 类别改成纯文字.
                    model: addAnnotateDialog.categoryLabels
                    delegate: ItemDelegate {
                        id: catItem
                        required property var modelData
                        required property int index
                        width: catCombo.width
                        height: styles.touchMin
                        contentItem: Text {
                            text: modelData
                            font.pixelSize: styles.fsLg
                            color: CommonOptions.colorText
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        highlighted: catCombo.highlightedIndex === index
                        background: Rectangle {
                            // 2026-10-20: 原来写 parent.highlighted —— background 的
                            //   parent 在 qmllint 眼里只是 QQuickItem, 拿不到 highlighted
                            //   (真机靠运行时的动态查找侥幸). 高底色原来是白@12% 压在浅色
                            //   popup 上等于没画, 换成墨@12%.
                            color: catItem.highlighted
                                   ? CommonOptions.withAlpha(CommonOptions.colorText, 0.12)
                                   : "transparent"
                        }
                    }
                    currentIndex: addAnnotateDialog.selectedCategory
                    onActivated: (index) => {
                        addAnnotateDialog.selectedCategory = index
                        addAnnotateDialog.refreshSpeciesList()
                        addAnnotateDialog.selectedSpeciesId = ""
                        addAnnotateDialog.recomputeDanger()
                    }
                }
            }

            // 物种
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "物种:"; color: CommonOptions.colorText; font.pixelSize: styles.fsMd; Layout.preferredWidth: 50 }
                ComboBox {
                    id: speciesCombo
                    Layout.fillWidth: true
                    model: addAnnotateDialog.speciesList
                    textRole: "commonName"
                    valueRole: "id"
                    enabled: addAnnotateDialog.speciesList.length > 0
                    onActivated: {
                        addAnnotateDialog.selectedSpeciesId = currentValue
                        addAnnotateDialog.recomputeDanger()
                    }
                }
            }

            // 备注
            TextField {
                id: noteField
                Layout.fillWidth: true
                placeholderText: "备注 (可选): 如 毒蛇 / 危险水源 / 营地等"
            }

            // 危险等级预览
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                color: addAnnotateDialog.computedDangerLevel >= 4 ? CommonOptions.colorDanger :
                       addAnnotateDialog.computedDangerLevel >= 3 ? CommonOptions.colorWarn :
                       addAnnotateDialog.computedDangerLevel >= 1 ? CommonOptions.colorAmber : CommonOptions.colorSuccess
                radius: 4
                Text {
                    anchors.centerIn: parent
                    // 必须自己限宽: 这条串最长能到"高危 (Lv4) - 某某某 · 按类别估, 未取物种记录",
                    //   不限宽时它按自然宽度画出去, 两端溢出 36 高的色条压住弹层边框.
                    width: parent.width - 2 * styles.spSm
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    color: CommonOptions.colorTextOnAccent
                    font.pixelSize: styles.fsMd
                    font.bold: true
                    text: {
                        var lvl = addAnnotateDialog.computedDangerLevel
                        var label = ""
                        if (lvl >= 4) label = "高危"
                        else if (lvl >= 3) label = "中危"
                        else if (lvl >= 1) label = "低危"
                        else label = "安全"
                        // 2026-10-20: 没选物种时 lvl 来自 recomputeDanger 的类别默认表,
                        //   不是这条记录的 danger_level —— 必须标"估", 否则用户会把它
                        //   当成数据读走.
                        return label + " (Lv" + lvl + ")" +
                               (addAnnotateDialog.selectedSpeciesName ?
                                "  -  " + addAnnotateDialog.selectedSpeciesName
                                : "  ·  按类别估, 未取物种记录")
                    }
                }
            }
        }

        // 2026-10-20 #41: 原来这段挂在 onAccepted 上, 触发它的是那颗英文 OK.
        //   现在由中文 footer 的「保存标注」直接调, 并且写失败不再只 console.warn
        //   后把表单留着不动 —— 明确告诉用户没存上, 他才不会以为已经记好了.
        function saveAndClose() {
            var c = mapPage.pendingAnnotateCoord
            if (!c) {
                toast.error("坐标没取到, 请重新在图上选点")
                return
            }
            // speciesId + speciesName 来自 selection, category 存类别名
            // 2026-10-26「精度到 1 m」: 第 6/8 参 (altitude/accuracy) 原来一个都不传,
            //   C++ 默认 0 直接落盘成"海平面 0 米 / 精度 0 米". 图上手选的点**没有**
            //   高程也没有 ± 精度 (它不是 GPS 读数), 传 NaN 让那一键整条不写.
            var catKey = addAnnotateDialog.categoryKeys[addAnnotateDialog.selectedCategory] || "manual"
            var res = mapService.addSpeciesLocation(
                addAnnotateDialog.selectedSpeciesId,
                addAnnotateDialog.selectedSpeciesName,
                catKey,
                c.latitude, c.longitude, Number.NaN,
                noteField.text, Number.NaN,
                addAnnotateDialog.computedDangerLevel)
            if (res && res.ok) {
                addAnnotateDialog.close()
                toast.success("已标注: " + (addAnnotateDialog.selectedSpeciesName
                                            || addAnnotateDialog.categoryLabels[
                                                addAnnotateDialog.selectedCategory]))
            } else {
                console.warn("addAnnotate failed:",
                             res && res.error ? res.error.message : res)
                toast.error("标注没写进去: "
                            + ((res && res.error && res.error.message) || "接口没给原因"))
            }
        }

        footer: DialogFooter {
            cancelText: "取消"
            confirmText: "保存标注"
            kind: "primary"
            onCancel: addAnnotateDialog.close()
            onConfirm: addAnnotateDialog.saveAndClose()
        }
    }

    // 2026-09-15: marker 点击详情对话框 (复用, 根据 markerDetailKind 切换内容)
    Dialog {
        id: markerDetailDialog
        modal: true   // L8 三件套之一: Qt6 的 Popup.modal 默认 false, 不写就是能点穿 (真机 F6)
        title: mapPage.markerDetailTitle
        anchors.centerIn: parent
        width: Math.min(420, mapPage.width - 2 * styles.pageMargin)
        // 2026-10-20 #41: 见 addAnnotateDialog 的同一处说明 (英文 Close → 中文 footer).
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        padding: styles.spMd
        footer: DialogFooter {
            // 纯查看型弹层: 只有一个"关掉", 没有需要确认的代价 → 不占色口也不做实心
            kind: "plain"
            cancelText: ""
            confirmText: "关闭"
            onConfirm: markerDetailDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 8

            Text {
                text: mapPage.markerDetailSub
                color: CommonOptions.colorText
                font.pixelSize: styles.fsMd
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // 物种标注: 类别 + 危险档 + note / source
            // 2026-10-26 A27: 名称在标题里, 类别与危险档以前根本没往弹层传 (数据里有),
            //   所以点毒蛇也只剩"物种标注 + 经纬度". 未知就整行不出现, 不填"未知"占位.
            // 下面这些单行项一律配 elide: Layout.fillWidth 只定宽度不折行时,
            //   Qt 不自动截断, 长路线名/长来源串会画出弹层边框压住下一条 (2026-10-29 字号收口时一并补).
            Text {
                visible: mapPage.markerDetailKind === "species"
                         && mapPage.markerDetailCategory.length > 0
                text: "类别: " + CommonOptions.speciesCategoryLabel(
                          mapPage.markerDetailCategory)
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsMd
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: mapPage.markerDetailKind === "species"
                         && CommonOptions.dangerLevelLabel(mapPage.markerDetailDanger).length > 0
                text: "危险度: " + CommonOptions.dangerLevelLabel(mapPage.markerDetailDanger)
                // 文字与地图圆点/盘上的点同一条 dangerColor, 不能红点配绿字
                color: CommonOptions.dangerColor(mapPage.markerDetailDanger)
                font.pixelSize: styles.fsMd
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            // 备注 / 来源 / 记录时刻: 没有就不出现这一行 ("(无)"/"(手动)" 是占位读数,
            //   看着像数据真这么写着 —— 与「不给假读数」冲突, 2026-10-26 去掉).
            Text {
                visible: mapPage.markerDetailKind === "species"
                         && mapPage.markerDetailNote.length > 0
                text: "备注: " + mapPage.markerDetailNote
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsMd
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Text {
                visible: mapPage.markerDetailKind === "species"
                         && mapPage.markerDetailSource.length > 0
                text: "来源: " + mapPage.markerDetailSource
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsSm
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: mapPage.markerDetailKind === "species"
                         && mapPage.markerDetailTime.length > 0
                // takenAt 是 ISODate 串 (数据侧原样), 只截到分钟 —— 标注精度到秒没意义,
                //   而全串在一行里会挤掉上一条
                text: "记录于: " + mapPage.markerDetailTime.substring(0, 16)
                color: CommonOptions.colorTextDim
                font.pixelSize: styles.fsSm
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // 危险点: 这一份数据只有 type / description / 坐标, 没有"应对措施"字段.
            //   2026-10-20: 删掉原来那行硬写的 "应对: 携带蛇毒吸附器, 高帮鞋, 注意落石"
            //   —— 它挂在每一个危险点上, 一条蛇的点位会被告知"注意落石". 真实说明已经
            //   在标题里 (d.description || d.type), 处置去下面的「查看路线详情」.
            Text {
                visible: mapPage.markerDetailKind === "danger"
                text: "所属路线: " + (mapPage._routeNameById(mapPage.markerDetailRouteId) || "")
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsMd
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // 起终点: 所属路线名 (与上面危险点那一行同角色, 字号必须同档)
            Text {
                visible: mapPage.markerDetailKind === "route_endpoint"
                text: "所属路线: " + (mapPage._routeNameById(mapPage.markerDetailRouteId) || "")
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsMd
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // 操作: 路线起终点 / 危险点 → 跳到路线详情
            RowLayout {
                visible: mapPage.markerDetailKind === "route_endpoint" ||
                         mapPage.markerDetailKind === "danger"
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 8

                PrimaryButton {
                    text: "查看路线详情"
                    Layout.fillWidth: true
                    tone: CommonOptions.colorAccent
                    textSize: styles.fsMd
                    // L11: 老数据 (手工标的点没有路线号) 会走到这里 —— 与其摆一枚点不动的
                    //   按钮, 不如整枚收起, 用户看到的是"这里只有一件事可做".
                    visible: !!mapPage.markerDetailRouteId
                    onClicked: {
                        if (mapPage.markerDetailRouteId) {
                            mapPage.ApplicationWindow.window.navBus.navigateTo(
                                "RouteDetailPage", { routeId: mapPage.markerDetailRouteId })
                        }
                    }
                }
                // 外链地图走 CommonOptions (dev=1 + geo: 兜底), 与路线/自驾详情页同一套
                OutlineButton {
                    text: "导航到此"
                    Layout.fillWidth: true
                    tone: CommonOptions.colorText
                    // L11 免: 这一枚只在已经点开某个图上的点时出现, 那一刻 coord 必然有值
                    //   (markerDetailCoord 就是从被点的标记里取来的), 禁用态实际到不了。
                    enabled: mapPage.markerDetailCoord !== null
                    onClicked: {
                        if (mapPage.markerDetailCoord) {
                            var c = mapPage.markerDetailCoord
                            CommonOptions.openMapMarker(c.latitude, c.longitude,
                                                        mapPage.markerDetailTitle || "目标")
                        }
                    }
                }
            }

            // 物种标注: 跳图鉴 / 导航
            RowLayout {
                visible: mapPage.markerDetailKind === "species"
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 8

                // 2026-10-26 A27: 标注是物种库里某条物种的"在哪儿见过"的记录, 野外看到
                //   一个点却查不到它长什么样/怎么处理, 等于白标. speciesId 为空的老数据
                //   (旧「标注这里」写进来的那批) 没有可跳的对象, 按钮不出现.
                PrimaryButton {
                    text: "看图鉴详情"
                    Layout.fillWidth: true
                    tone: CommonOptions.colorAccent
                    textSize: styles.fsMd
                    visible: mapPage.markerDetailSpeciesId.length > 0
                    onClicked: {
                        mapPage.ApplicationWindow.window.navBus.navigateTo(
                            "FieldGuideDetailPage",
                            { speciesId: mapPage.markerDetailSpeciesId })
                    }
                }

                OutlineButton {
                    text: "导航到此"
                    Layout.fillWidth: true
                    tone: CommonOptions.colorText
                    // L11 免: 同上 —— 物种那一枚标记也一定带坐标, 禁用态到不了。
                    enabled: mapPage.markerDetailCoord !== null
                    onClicked: {
                        if (mapPage.markerDetailCoord) {
                            var c = mapPage.markerDetailCoord
                            // 传读数而不是硬编码"物种标注": 外链地图的标题就是用户
                            //   在高德里看到的那一行, 报"物种标注"等于什么都没报.
                            CommonOptions.openMapMarker(c.latitude, c.longitude,
                                                       mapPage.markerDetailTitle || "标注点")
                        }
                    }
                }
            }

            // 2026-10-29 (问题6): 标注点错了/物种认错了, 以前只能去别处找入口删,
            //   弹层里连"删除"两个字都没有. 单占一行靠右 —— 不可撤的操作不与
            //   「看图鉴详情/导航到此」并排, 免得拇指够导航时点穿到删除上.
            RowLayout {
                visible: mapPage.markerDetailKind === "species"
                         && mapPage.markerDetailLocationId.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                Item { Layout.fillWidth: true }

                OutlineButton {
                    text: "删除这条标注"
                    tone: CommonOptions.colorDanger
                    onClicked: confirmDeleteMark.open()
                }
            }
        }
    }

    // 2026-10-29 (问题6): 删除标注前的确认. 删的是本机那一条记录文件, 不能撤,
    //   所以走 DialogFooter 的危险档 (描边 + 红字 + 「不可撤」).
    Dialog {
        id: confirmDeleteMark
        title: "删除这条标注?"
        anchors.centerIn: parent
        modal: true
        width: Math.min(360, mapPage.width - 2 * styles.pageMargin)
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        padding: styles.spMd

        // L15: Dialog 的 contentItem 是裸 Item, 不把宽度传给子项 —— 正文要有宽度约束才 wrap。
        contentItem: ColumnLayout {
            spacing: styles.spSm

            Text {
                Layout.fillWidth: true
                text: "从本机删掉「" + (mapPage.markerDetailTitle || "标注点") +
                      "」? 删掉后图上和盘上都不再有这个点, 物种本身不受影响."
                color: CommonOptions.colorText
                font.pixelSize: styles.fsMd
                wrapMode: Text.WordWrap
            }
        }
        footer: DialogFooter {
            kind: "danger"   // 真删本机记录 —— 不靠 DialogFooter 的默认值兜 (改默认就会悄悄失守)
            cancelText: "留着"
            confirmText: "删除"
            confirmCode: "不可撤"
            onCancel: confirmDeleteMark.close()
            onConfirm: {
                mapPage.deleteMarkedSpecies(mapPage.markerDetailLocationId)
                confirmDeleteMark.close()
            }
        }
    }

    // 顶部工具条
    // 2026-09-15: 概览对话框 - 显示选中路线/轨迹的海拔/速度/距离分析
    Dialog {
        id: summaryDialog
        title: name + " - 概览"
        anchors.centerIn: parent
        width: Math.min(460, mapPage.width - 2 * styles.pageMargin)
        height: Math.min(parent.height * 0.92, 760)
        modal: true
        // 2026-10-20 #41: 英文 Close → 中文 footer (见 addAnnotateDialog 的说明).
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        footer: DialogFooter {
            kind: "plain"
            cancelText: ""
            confirmText: "关闭"
            onConfirm: summaryDialog.close()
        }

        // 入口参数 (由 openSummary 注入)
        property string kind: "route"     // route | travel | track
        // 2026-09-15: 用 itemId, 避开 QML 'id' 关键字
        property string itemId: ""
        property string name: ""

        // 每次打开时重置 panel (避免上次内容残留)
        onAboutToShow: {
            summaryPanel.kind = kind
            summaryPanel.itemId = itemId
            summaryPanel.name = name
            summaryPanel.load()
        }

        contentItem: RouteSummaryPanel {
            id: summaryPanel
            kind: summaryDialog.kind
            // 2026-09-15: 用 binding 表达式直接绑 itemId (避开 id 关键字)
            itemId: summaryDialog.itemId
            name: summaryDialog.name
        }
    }

    // 2026-09-15: 已选列表 - 单击 chip 弹出, 列出全部选中 + 单项删除
    Dialog {
        id: selectedListDialog
        modal: true   // L8 三件套之一: Qt6 的 Popup.modal 默认 false, 不写就是能点穿 (真机 F6)
        // 2026-10-23 真机 (A5 假读数): 标题原来数 selectedRouteIds+selectedTrackIds,
        //   列表却画 routeOverlays+trackOverlays —— 缺点位的那条路线进了前者没进后者,
        //   于是「已选 2 项」下面只有一行. 现在标题与列表同源, 数得出来的就一定删得掉.
        title: "已选 " + (mapPage.routeOverlays.length + mapPage.trackOverlays.length) + " 项"
        anchors.centerIn: parent
        width: Math.min(420, mapPage.width - 2 * styles.pageMargin)
        // 2026-10-23 真机 (A6): height 原来写死 min(0.7h, 520), 两个毛病一起出 ——
        //   ① header + 1 行 + footer 远不到 520, 中间一大片空白, 行被顶在弹层正中;
        //   ② footer 排在 contentItem 之下, 内容一高过 520 就被推到弹层背景外面,
        //      真机上「全部清空」的右边框和下半截直接没了 (crop_k1_footer).
        //   改成按内容自适应: Dialog.implicitHeight 已含 header/footer, 上限仍收 0.7 屏,
        //   列表自己有 260 的 preferredHeight 天花板, 不会顶穿.
        padding: styles.spMd
        height: Math.min(parent.height * 0.7, implicitHeight)
        // 2026-10-20 #41: 两个动作从 contentItem 末尾挪进 footer —— 弹层里"操作"和
        //   "读数"分栏, 列表滚到底也不会把按钮挤出可视区.
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        footer: DialogFooter {
            // 这一格只是"打开确认框", 一个字节都不改 —— 危险档(红口+红字)留给真删数据的那扇门。
            kind: "plain"
            cancelText: "关闭"
            confirmText: "全部清空"
            // 清空选中只是视图状态, 重新点一行就回来了 —— 不写「不可撤」的附注
            confirmCode: ""
            onCancel: selectedListDialog.close()
            // 清空只擦画线, 存储里的轨迹一条不少。那张确认框本来就写好了, 只是
            // 唯一的入口 (浮层 chip 的 selectedClearClicked) 从没被发出过 —— #82 复盘
            // 把这里接成唯一出口. 先关清单再弹确认, 免得两层叠住确认那句"已选 N 项".
            onConfirm: {
                selectedListDialog.close()
                confirmClearDialog.open()
            }
        }

        // 2026-09-15: 用 ListView 内的 Repeater 实时绑定 mapPage 状态, 不用 property var cache
        contentItem: ColumnLayout {
            spacing: 8

            // 路线/自驾 列表
            ListView {
                visible: mapPage.routeOverlays.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(
                    mapPage.routeOverlays.length * 64 + 8, 260)
                spacing: 6
                clip: true
                model: mapPage.routeOverlays

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view ? ListView.view.width : 0
                    height: 56
                    color: hoverArea.hovered ? CommonOptions.colorSurfaceDim : CommonOptions.colorSurface
                    radius: 4

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 10
                            Layout.fillHeight: true
                            color: modelData.color
                            radius: 2
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            // 2026-09-19: \ue52f (bicycle) 改成 \ue536 (hiking) - 徒步路线图标
                            // 2026-10-19: 图标与名称拆成两个节点 (本字体无 CJK 字形)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                IconLabel {
                                    name: modelData.kind === "travel" ? "car" : "hiking"
                                    size: 14
                                    // 2026-10-20: 这行底色是 colorSurface (浅色卡), 原来用
                                    //   colorTextOnAccent (#F6F8F6) → 白底白字, 标题看不见.
                                    tintColor: CommonOptions.colorText
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name || "(未命名)"
                                    color: CommonOptions.colorText
                                    font.pixelSize: styles.fsLg
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                text: {
                                    var label = modelData.kind === "travel" ? "自驾游" : "徒步路线"
                                    // 「N 个点」只在真有路径点时才是轨迹读数; 起终点
                                    // 直线写「2 个点」会被当成一条测过的轨迹, 违反
                                    // 「不给假读数」. 示意线就如实说它是示意,
                                    // 另外把坐标量化误差与点的性质一起报出来 (#131).
                                    return label + mapPage._pathNote(modelData)
                                            + mapPage._precisionNote(modelData.precisionM,
                                                                    modelData.coordSource)
                                }
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: styles.fsSm
                                elide: Text.ElideRight
                            }
                        }

                        // 2026-09-15: 概览按钮 - 弹出 RouteSummaryPanel
                        // 2026-10-28 控件盘点: 原来是裸 Button + Material.background,
                        //   圆角走 Material.buttonRadius, 与全站方角卡片的 rSm 不是一个形状;
                        //   换成行内动作方块母版 (与「轨迹」Tab 的分析格、③页删除格同一枚).
                        IconActionCell {
                            iconName: "equalizer"
                            filled: true
                            onTriggered: {
                                mapPage.openSummary(modelData.kind === "travel" ? "travel" : "route",
                                                     modelData.id, modelData.name)
                            }
                        }
                        IconActionCell {
                            iconName: "close"
                            filled: true
                            // 2026-10-21 #65: 原来是 colorDanger. 这个叉只是把线从当前
                            //   地图上摘掉 (routeOverlays/selectedRouteIds 少一项), 库里
                            //   数据一条没动, 重新勾选就回来了 —— 不配占用危险红.
                            onTriggered: mapPage.removeRoute(modelData.id)
                        }
                    }

                    // 2026-10-23 (A4 同族): 这里只是要一个悬停高亮, 原来用
                    //   MouseArea{anchors.fill; hoverEnabled} —— 桌面悬停能亮, 但触屏上
                    //   它按下即独占抓握, 清单超过 260px 上限时那一小段也拖不动.
                    //   HoverHandler 只处理悬停, 从不参与触摸抓握.
                    HoverHandler { id: hoverArea }
                }
            }

            // 轨迹 列表
            ListView {
                visible: mapPage.trackOverlays.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(
                    mapPage.trackOverlays.length * 64 + 8, 260)
                spacing: 6
                clip: true
                model: mapPage.trackOverlays

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view ? ListView.view.width : 0
                    height: 56
                    // 2026-10-27 #134: 原先这里读的是 hoverArea —— 那个 id 声明在**路线**
                    //   delegate 里. QML 的 id 作用域只在声明它的组件内, 跨 delegate 引用
                    //   是悬空引用: 整条绑定抛 ReferenceError 后被吞, Rectangle 停在类型
                    //   默认的 #FFFFFF → 轨迹行永远白底, 看着像"色彩标注不对".
                    //   本 delegate 自己的 hoverArea2 从来没被读过, 现在接上.
                    color: hoverArea2.hovered ? CommonOptions.colorSurfaceDim : CommonOptions.colorSurface
                    radius: 4

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 10
                            Layout.fillHeight: true
                            color: modelData.color
                            radius: 2
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                IconLabel {
                                    name: "route"
                                    size: 14
                                    tintColor: CommonOptions.colorText
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name || "(轨迹)"
                                    color: CommonOptions.colorText
                                    font.pixelSize: styles.fsLg
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                text: "轨迹  ·  " + (modelData.pointCount || modelData.path.length)
                                     + " 个点"
                                     + (modelData.thinned ? " · 画线已抽稀" : "")
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: styles.fsSm
                            }
                        }

                        // 2026-09-15: 概览按钮 (2026-10-28 控件盘点: 与路线行同一枚方块)
                        IconActionCell {
                            iconName: "equalizer"
                            filled: true
                            onTriggered: mapPage.openSummary("track", modelData.id, modelData.name)
                        }
                        IconActionCell {
                            iconName: "close"
                            filled: true
                            // 同路线行: 摘掉轨迹画线不是删数据 (轨迹还在本机库里, 从记录
                            //   Tab 重新勾选即恢复) → 墨底, 不用危险红.
                            onTriggered: mapPage.removeTrack(modelData.id)
                        }
                    }

                    HoverHandler { id: hoverArea2 }
                }
            }

            // 无选中提示
            Text {
                visible: mapPage.routeOverlays.length === 0 &&
                         mapPage.trackOverlays.length === 0
                Layout.fillWidth: true
                text: "当前无选中项"
                color: CommonOptions.colorTextDim
                font.pixelSize: styles.fsMd
                horizontalAlignment: Text.AlignHCenter
                topPadding: 30
                bottomPadding: 30
            }
        }
    }

    // 2026-10-20 #41: Yes/No → 中文 footer. 顺带修一处真机白字: 那句问话用
    //   colorTextOnAccent (#F6F8F6), 而弹层底继承窗口的浅色 colorBg → 整句话看不见,
    //   只剩两颗按钮. 现在文字走 colorText, 弹层底显式绑 colorSurface.
    Dialog {
        id: confirmClearDialog
        modal: true   // L8 三件套之一: Qt6 的 Popup.modal 默认 false, 不写就是能点穿 (真机 F6)
        title: "清空已选?"
        anchors.centerIn: parent
        width: Math.min(360, mapPage.width - 2 * styles.pageMargin)
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        padding: styles.spMd

        // L15: 裸 Text 子项拿不到宽度, wrapMode 会是死的。
        contentItem: ColumnLayout {
            spacing: styles.spSm

            Text {
                Layout.fillWidth: true
                text: "已选 " + (mapPage.routeOverlays.length + mapPage.trackOverlays.length) +
                      " 项 (路线/轨迹), 全部清空?"
                color: CommonOptions.colorText
                font.pixelSize: styles.fsMd
                wrapMode: Text.WordWrap
            }
        }
        footer: DialogFooter {
            // 清的是屏上的画线, 不是存储里的数据 —— 重新点一行就回来了, 所以不占危险档,
            // 也不写「不可撤」。(同一扇门另一侧 selectedListDialog 的口径要一致, #43 轮记录过相反写法)
            kind: "plain"
            cancelText: "返回"
            confirmText: "清空"
            confirmCode: ""
            onCancel: confirmClearDialog.close()
            onConfirm: {
                mapPage.clearSelections()
                confirmClearDialog.close()
            }
        }
    }

    // ④地图 丁仪表叠层 (2026-10-20 #61): 迷你盘 + 比例尺 + 搜索/图层/求助 + 回中.
    // 替掉三块旧浮层 —— MapRightButtonColumn (6 枚饱和色圆钮)、顶部 48px 深蓝标题栏
    // (和窗口自己的 header 叠成两条横杠)、右下 zoomControls. 6 个钮的功能没有丢:
    //   标注 → 抽屉主按钮 + 长按地图选点; 拍照 → 「记录」Tab; 轨迹 → 抽屉;
    //   危险/周边 → 「目标」Tab; 底图 → 图层钮; 居中 → 盘下那枚方块.
    // SOS 仍然要长按满 3 秒 (组件里计时), 短按不跳页.
    MapInstrumentOverlay {
        anchors.fill: parent

        heading: mapPage.effHeadingDeg
        hasHeading: mapPage.hasEffHeading
        calibrationPct: mapPage.calibPct
        headingNote: mapPage.headingNote
        accText: mapPage.accText
        targets: mapPage.dialTargets
        zoomLevel: mapPage.mapZoomInt
        scaleText: mapPage.scaleText
        scaleBarPx: mapPage.scaleBarPx
        markCount: mapPage.speciesLocations.length
        // 2026-10-23 (A5): chip / 清单 / 确认框三处计数改同一口径 —— 都以"清单里真列得出来、
        //   真删得掉"的 overlay 为准. 用 selectedRouteIds 数会把画不出线的路线算进去.
        selectedCount: mapPage.routeOverlays.length + mapPage.trackOverlays.length
        locateReady: mapPage.hasFix
        // 两档工作台 (2026-10-28): selChip 要浮在底栏顶上, 底栏现在是变高的
        //   (折叠 130 / 展开最多 409), 常量贴不住 —— 把抽屉实时高度喂给叠层.
        //   visible 而不是 opened: 开合动画途中 visible 先翻, height 已定, 不会闪.
        sheetHeight: bottomSheet.visible ? bottomSheet.height : 0

        onSearchClicked: bottomSheet.openTab(3)
        onLayersClicked: baseMapMenu.popup()
        onLocateClicked: mapPage.centerOnMe()
        onZoomInClicked: mapPage.stepZoom(1)
        onZoomOutClicked: mapPage.stepZoom(-1)
        onSelectedClicked: selectedListDialog.open()
        onSosConfirmed: mapPage.ApplicationWindow.window.navBus.navigateTo("SOSPage", {})
    }

    // 缩放一档 (+/-). 原来这段逻辑抄在 zoomControls 的两枚方块里, 现在收成一个函数:
    //   clamp 到 min/max 之后写 map.zoomLevel —— 赋值会解绑 (center 同理, 见文件头
    //   #43 的说明), 这正是想要的: 用户手动定的比例不该被任何绑定拉回去.
    function stepZoom(delta) {
        var z = map.zoomLevel + delta
        if (z < map.minimumZoomLevel || z > map.maximumZoomLevel) return
        map.zoomLevel = z
        mapPage.currentZoom = z
    }

    // 2026-10-09: 底图切换菜单. 选中项打勾.
    // 2026-10-20: 点选 → 写会话索引 → 重建本页 (Map.plugin write-once, 换 Plugin
    //   对象无效, 见 _rebuildForBaseMap). 重建会丢掉已画的路线/轨迹和抽屉状态,
    //   视野靠会话里的 mapView* 落回原处.
    // 2026-11-03 真机 (F6 / 定律 L8): 这块面板原来只有三个单选项 —— 无遮罩、无标题、无出口，
    //   用户只能"选一项"才能离开，等于把换底图变成一次强制改写。浮层三件套补齐：
    //   dim 遮罩 (点外面必关且不穿到底层地图) + 标题 (Menu 的 title 属性不画出来) +
    //   明确的「关闭」出口。
    // 2026-11-03 qml_load_check 抓出来的致命错: Menu 在 Qt6 是 **Popup 派生**, 没有
    //   header / footer (那两个属于 Pane / Dialog / ApplicationWindow)。写了不是警告,
    //   是 "Cannot assign to non-existent property" —— 整个 MapPage 编译不过, 而 MapPage
    //   被 Main.qml 引用, 于是**真机开局白屏**。qmllint 全树当时 0 Error, 只有 load check
    //   能抓到, 所以这三件套的标题/出口只能做成首尾两行 MenuItem。
    //   closePolicy 不写：Popup 的默认口径已经含
    //   点外部/Escape 关闭，而 `Popup.CloseOnPressOutside` 这个枚举要引基座 `Popup` 类型，
    //   与"只 import QtQuick.Controls.Material"的打包口径冲突 (controls_import_check.js)。
    Menu {
        id: baseMapMenu
        title: "选择底图"
        dim: true
        modal: true

        // 标题行与出口 (2026-11-03): Menu 没有 header/footer, 三件套里的"标题"和"出口"
        //   只能做成首尾两行 MenuItem。标题这行 enabled:false = 它不是一项可选动作, 但
        //   Material 的默认 contentItem 会把禁用行的字染成 hintTextColor
        //   (Material/MenuItem.qml:41), 所以自带一个 Text 指定 colorText, 别让它像灰掉的选项。
        MenuItem {
            // L11 免: 这一行是浮层的标题条, 不是一项被禁掉的动 —— 没有"为什么点不动"可答。
            //   enabled:false 只用来让它不参与选中/高亮。
            enabled: false
            text: ""
            contentItem: Text {
                text: "选择底图"
                font.pixelSize: styles.fsSm
                font.bold: true
                color: CommonOptions.colorText
                verticalAlignment: Text.AlignVCenter
            }
        }

        Repeater {
            model: mapPage._baseMaps
            delegate: MenuItem {
                required property var modelData
                required property int index
                text: modelData.name
                checkable: true
                checked: mapPage.currentBaseMap === index
                onTriggered: {
                    if (index === mapPage.currentBaseMap) return
                    mapPage.currentBaseMap = index
                    // 手动换源 = 给新源完整的重试机会 (自动 failover 才累加计数)
                    mapPage._tileFailover = 0
                    mapPage._rebuildForBaseMap(index)
                }
            }
        }

        MenuItem {
            text: "关闭"
            font.pixelSize: styles.fsSm
            onClicked: baseMapMenu.close()
        }
    }


    // 2026-09-15: 监听 androidPlatform 拍照完成, 走原有 onPhotoTaken
    Connections {
        // 2026-09-17: target 去掉 typeof 包装 (QML typeof 抛 ReferenceError → 永远 null)
        target: androidPlatform ? androidPlatform : null
        function onPhotoTaken(uri) {
            mapPage.onPhotoTaken(uri)
        }
    }

    // 底部 BottomSheet
    // 2026-11-02 反馈①: 这张工作台从 Drawer 改成了普通 Item (原因见 MapBottomSheet.qml
    //   开头那段 —— 底部 edge 的 Popup 矩形永远铺到窗口底, 会把 footer 那 48 逻辑的
    //   导航条整个吃掉, 于是"卡片让位了、导航条点不动"). Item 版本贴的是**内容区**底,
    //   内容区下沿本来就等于导航条上沿, 所以 anchors 现在既管绘制也管事件.
    MapBottomSheet {
        id: bottomSheet
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // 压在地图瓦片与所有 MapQuickItem 之上, 但仍在 sheetHandle/errRow 之下 (它们 z 更高)
        z: 900

        // 2026-10-16: 实时坐标改由这里绑 (mapPage 这个 id 在本文件可见).
        //   之前在 MapBottomSheet.qml 内部写 mapPage.currentLat 是跨文件 id 引用,
        //   恒为 undefined → 「目标」Tab 永远按 (0,0) 查.
        // 2026-10-19: 改用 viewLat/viewLon (地图可视中心) 而不是 currentLat/Lon
        //   (GPS 位置). 真机 GPS 权限被拒时 currentLat 一直停在默认北京, 用户把地图
        //   拖到厦门点半径, 查出来的还是北京的路线 —— 现在地图能手动移动了,
        //   盘心必须跟着看到的范围走.
        currentLat: mapPage.viewLat
        currentLon: mapPage.viewLon
        // 多选高亮透传给各 Tab (Tab 内部读不到 mapPage 这个 id)
        selectedRouteIds: mapPage.selectedRouteIds
        selectedTrackIds: mapPage.selectedTrackIds
        // 「目标」Tab 的物种标注行. 与叠层罗盘上的点同源 (mapTargets / dialTargets
        // 都是遍历 speciesLocations), 列表和盘上出现两套方位才是更难查的 bug.
        targets: mapPage.mapTargets

        // 2026-09-19: 用 QML6 信号 handler 形式 (onXxx: ...) 而不是
        // function onXxx(args){}, 后者在子组件实例化块里不被识别为 signal handler
        // (只有 Connections 元素才识别 function onXxx), 之前的注释搞反了
        onCaptureRequested: mapPage.onCaptureRequested()
        // 2026-10-20 #61: 原来这个动作在右侧浮动圆钮里, 圆钮被 MapInstrumentOverlay
        //   替掉后由抽屉底部主按钮接手.
        onAnnotateRequested: mapPage.annotateHere()
        onRouteSelected: function(routeId, route) { mapPage.onRouteSelected(routeId, route) }
        onTrackSelected: function(trackId, track) { mapPage.onTrackSelected(trackId, track) }
        onTargetClicked: function(target) { mapPage.focusTarget(target) }
        // 2026-10-27 #132: 「查找」地点模式的行 = 某条路线/某条自驾的一个端点,
        //   动作和「目标」行完全一样 (把地图挪过去 + 收抽屉), 所以复用 focusTarget,
        //   不新增第三种"地图怎么动"的语义.
        onPlaceSelected: function(place) { mapPage.focusTarget(place) }
        onTrackAnalyzeRequested: function(trackId) { mapPage.openTrackDetail(trackId) }
        // 2026-10-09: 导入入口打通 (此前 importDialog 无任何 .open() 触发点 → 死功能)
        onTrackImportRequested: importDialog.open()
        // 2026-10-23 #109: 轨迹 Tab 的「清空」—— 此前"已加载"(旧文案"已画线")只能逐条再点一次取消,
        //   多选之后没有任何批量出口.
        onTracksClearRequested: mapPage.clearTrackSelections()
    }

    // 2026-10-23 真机: 卡片收起时整个 Drawer 在屏外, 地图上**没有任何可见入口**,
    // 没人知道要上滑 (drawer 自己的 dragMargin 那 80px 又被底部 OSM attribution 和
    // App 的标签栏占着, 拖了也没反应). 补一颗常驻小把手: 点一下展开到上次的 Tab,
    // 按住往上拖同样展开; 卡片一开就让位给它自己那根抓条, 不出现两根.
    // 2026-10-28 两档改后这里的判定照旧成立: fold 不动 visible (只是 height 从 409
    //   收到 130, 抽屉还开着), bottomSheet.visible 变 false 只剩"整个关掉"这一种情况
    //   —— 折叠态那 130 入口条自己就是四格入口, 不需要也不该再叠一颗把手;
    //   把手只在用户把条也拖关后回来.
    Rectangle {
        id: sheetHandle
        z: 1000   // 与浮层同层, 压在 MapQuickItem 之上
        visible: !bottomSheet.visible
        x: (mapPage.width - width) / 2
        y: mapPage.height - height - styles.bottomSheetPeek
        width: sheetHandleCol.implicitWidth + 2 * styles.spMd
        height: sheetHandleCol.implicitHeight + 2 * styles.spSm
        radius: styles.rPill
        color: CommonOptions.colorSurface
        border.color: CommonOptions.colorDivider
        border.width: styles.lineHair

        Column {
            id: sheetHandleCol
            anchors.centerIn: parent
            spacing: styles.spXs
            // 抓条: 与卡片顶部那根同形同色, 让人认出是同一个东西的两态
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: styles.icSm
                height: styles.lineAccent
                radius: styles.lineAccent / 2
                color: CommonOptions.colorTextDim
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "地图工作台"
                color: CommonOptions.colorText
                font.pixelSize: styles.fsSm
            }
        }
        TapHandler { onTapped: bottomSheet.openTab(bottomSheet.currentTab) }
        DragHandler {
            target: null
            onTranslationChanged: (delta) => {
                // 两档工作台 (2026-10-28): 原来这里 open() —— 在旧单档抽屉里 open() 就
                //   等于"露出 480 面板"; 新抽屉默认 folded=true, 裸 open() 只把 130 的
                //   入口条顶出来, 上拉的人想要的却是面板本体. openTab(当前档) = 展开 +
                //   停在上次那一面, 与点把手 (上面 onTapped) 同一个落点, 两条手势不打架.
                if (translation.y < -40 && !bottomSheet.opened) bottomSheet.openTab(bottomSheet.currentTab)
            }
        }
    }

    function onCaptureRequested() {
        if (androidPlatform && androidPlatform.takePhoto) {
            androidPlatform.takePhoto(function(uri) {
                mapPage.onPhotoTaken(uri)
            })
        } else {
            console.log("takePhoto: androidPlatform not registered (desktop debug)")
        }
    }

    function onRouteSelected(routeId, route) {
        // 2026-09-15: 路线联动 - 多选叠加 / 再点取消
        var before = mapPage.selectedRouteIds.length
        mapPage.addOrToggleRoute(route)
        // 2026-10-23 真机 (A13): 点一条查找结果, 原来只有那一行换了描边, 地图纹丝不动
        //   (c4 取证: 日志只有一句 addOrToggleRoute 警告, 屏幕上看不到任何变化) ——
        //   用户既不知道"选中"发生了什么, 也看不到那条线在哪. 现在选上就把视野套到
        //   已选集合 (fitBoundsToRoutes 已经按展开的抽屉扣掉底部可视区), 并给一条回执.
        //   取消选中不动视野: 那是"擦掉一条线", 不是"换一块地方看".
        if (mapPage.selectedRouteIds.length > before) {
            mapPage.fitBoundsToRoutes()
            toast.success("已选中「" + (route.name || routeId) + "」, 视野套到已选 " +
                          (mapPage.routeOverlays.length + mapPage.trackOverlays.length) + " 项")
        }
    }

    // 2026-09-15: 新增: 加或取消一条路线
    // route: QVariantMap from getNearby/getById/getAll 等
    function addOrToggleRoute(route) {
        if (!route || !route.id) return
        var rid = route.id

        // 已选: 取消
        if (mapPage.selectedRouteIds.indexOf(rid) >= 0) {
            mapPage.removeRoute(rid)
            return
        }

        // 新选: 加入 (route 数据可能没 waypoints, 这时用 起终点画一条直线)
        var coords = []
        if (mapPage._validCoord(route.trailheadLat, route.trailheadLon)) {
            coords.push(QtPositioning.coordinate(route.trailheadLat, route.trailheadLon))
        }
        // 优先用 waypoints (多段路径)
        // getWaypoints 返回 [{name, type, lat, lon, elevation, description}]
        var wps = []
        try {
            wps = routeService.getWaypoints(rid)
        } catch (e) {
            wps = []
            toast.warn("加载路径点失败: " + e)  // 2026-09-20
        }
        if (wps && wps.length >= 2) {
            coords = []
            for (var i = 0; i < wps.length; i++) {
                var p = wps[i]
                var lat = (p.lat !== undefined) ? p.lat : p.latitude
                var lon = (p.lon !== undefined) ? p.lon : p.longitude
                if (mapPage._validCoord(lat, lon)) {
                    coords.push(QtPositioning.coordinate(lat, lon))
                }
            }
        } else if (mapPage._validCoord(route.trailendLat, route.trailendLon)) {
            // 起终点都在, 用 起→终 直线
            coords.push(QtPositioning.coordinate(route.trailendLat, route.trailendLon))
        }

        if (coords.length < 2) {
            // 至少要 2 个点才能画线, 没有就只标起点.
            // 2026-10-23 真机 (A5「已选 2 项却只列 1 行」): 这条分支原来只塞 routeMarkers
            //   就跳过 overlay, 可下面照样 selectedRouteIds.concat(rid) —— 缺点位的路线
            //   (route_mt_yi 那批) 选上之后在「已选清单」里数得到、画不出、也删不掉.
            //   现在"选上就一定在列表里": path 只有 1 个点时 MapPolyline 不画线, 但行数
            //   与计数一致, 行副标题如实写「1 个点」, 而不是假装这条线不存在.
            if (coords.length === 1) {
                var colorIdx = mapPage._freeColorIdx()
                mapPage.routeOverlays = mapPage.routeOverlays.concat([{
                    id: rid,
                    name: route.name || "(未命名)",
                    colorIdx: colorIdx,
                    color: mapPage._colorForIndex(colorIdx),
                    path: coords,
                    approx: true,
                    precisionM: route.coordPrecisionM,
                    coordSource: route.coordSource
                }])
                mapPage.routeMarkers = mapPage.routeMarkers.concat([{
                    routeId: rid,
                    coord: coords[0],
                    label: "S",
                    color: mapPage._colorForIndex(colorIdx)
                }])
            }
            console.warn("addOrToggleRoute: route " + rid + " 缺少路径点, 仅标注起点")
        } else {
            var ci = mapPage._freeColorIdx()
            mapPage.routeOverlays = mapPage.routeOverlays.concat([{
                id: rid,
                name: route.name || "(未命名)",
                colorIdx: ci,
                color: mapPage._colorForIndex(ci),
                path: coords,
                // 库里没有路径点时 coords 就是 起点→终点 两个端点, 画出来的是一条
                // 示意直线, 不是这条路线实际走过的轨迹. 如实带上这个标记, 列表行
                // 据此写「起终点示意」而不是「2 个点」—— 后者会被当成真轨迹读.
                approx: !(wps && wps.length >= 2),
                precisionM: route.coordPrecisionM,
                coordSource: route.coordSource
            }])
            // 起终点 marker
            var markers = []
            markers.push({ routeId: rid, coord: coords[0], label: "S", color: mapPage._colorForIndex(ci) })
            markers.push({ routeId: rid, coord: coords[coords.length - 1], label: "E", color: mapPage._colorForIndex(ci) })
            mapPage.routeMarkers = mapPage.routeMarkers.concat(markers)

            // 2026-09-15: 中间路径点 (营地/垭口等) - 仅 waypoints 模式有, 用半透明小方块
            // 2026-10-27 #131: 实测 GPS 轨迹灌进库后, 中间点里绝大多数是 type="track"
            // 的采样点(一条线 120~160 个)。它们是线的形状本身, 不是"地点" —— 逐点
            // 插方块会把图糊成一片, 所以只给有名字的路点(垭口/营地/泉眼)出标记。
            if (wps && wps.length > 2) {
                var wpMarkers = []
                for (var wp = 1; wp < wps.length - 1; wp++) {
                    var w = wps[wp]
                    if (w.type === "track") continue
                    var wlat = (w.lat !== undefined) ? w.lat : w.latitude
                    var wlon = (w.lon !== undefined) ? w.lon : w.longitude
                    if (mapPage._validCoord(wlat, wlon)) {
                        wpMarkers.push({
                            routeId: rid,
                            coord: QtPositioning.coordinate(wlat, wlon),
                            name: w.name || "路径点",
                            type: w.type || "waypoint"
                        })
                    }
                }
                if (wpMarkers.length > 0) {
                    mapPage.waypointMarkers = mapPage.waypointMarkers.concat(wpMarkers)
                }
            }
        }

        // 2026-10-23 (A5): 一个有效坐标都没有 → 不进选中集. 否则它既不在清单里也没法
        //   取消 (removeRoute 按 overlay 走), 变成一个只能靠「全部清空」收拾的幽灵项.
        if (coords.length >= 1) {
            mapPage.selectedRouteIds = mapPage.selectedRouteIds.concat([rid])
        } else {
            toast.warn("「" + (route.name || rid) + "」没有可用坐标, 画不到图上")
            return
        }

        // 危险点 (从 getDangers 拿, 多条路线叠加)
        // 注意: getDangers 返回的 QVariantMap 含 locations 字段, 是 JSON 字符串
        // 形如 '[[lat, lon], [lat, lon], ...]' 或 '[{"lat":..,"lon":..}]'
        try {
            var dangers = routeService.getDangers(rid)
            if (dangers && dangers.length > 0) {
                var dm = []
                for (var j = 0; j < dangers.length; j++) {
                    var d = dangers[j]
                    var locStr = d.locations
                    if (!locStr) continue
                    // 解析 locations JSON
                    var pts = null
                    try {
                        pts = JSON.parse(locStr)
                    } catch (e) {
                        console.warn("MapPage: JSON.parse 危险点位置失败:", locStr, e)
                        continue
                    }
                    if (!pts || !pts.length) continue
                    for (var k = 0; k < pts.length; k++) {
                        var pt = pts[k]
                        // 兼容 [lat, lon] 和 {lat, lon} 两种格式
                        var lat, lon
                        if (pt instanceof Array) {
                            lat = pt[0]; lon = pt[1]
                        } else if (pt && typeof pt === "object") {
                            lat = pt.lat || pt.latitude
                            lon = pt.lon || pt.lng || pt.longitude
                        }
                        // 2026-10-09: 校验经 _validCoord 收口 (typeof 先挡 null/undefined,
                        //   isFinite 因 Number(null)=0 会误判, 故保留 typeof 前哨).
                        if (typeof lat === "number" && typeof lon === "number" &&
                            mapPage._validCoord(lat, lon)) {
                            dm.push({
                                routeId: rid,
                                coord: QtPositioning.coordinate(lat, lon),
                                name: d.description || d.type || "危险"
                            })
                        }
                    }
                }
                if (dm.length > 0) {
                    mapPage.dangerMarkers = mapPage.dangerMarkers.concat(dm)
                }
            }
        } catch (e) {
            toast.warn("加载路线危险点失败: " + e)  // 2026-09-20: 切 Toast
        }

        // 自动 fit bounds
        mapPage.fitBoundsToRoutes()
    }

    // 2026-09-15: 取消一条路线
    function removeRoute(rid) {
        var ids = []
        for (var i = 0; i < mapPage.selectedRouteIds.length; i++) {
            if (mapPage.selectedRouteIds[i] !== rid) ids.push(mapPage.selectedRouteIds[i])
        }
        mapPage.selectedRouteIds = ids
        var newOverlays = []
        for (var k = 0; k < mapPage.routeOverlays.length; k++) {
            if (mapPage.routeOverlays[k].id !== rid) newOverlays.push(mapPage.routeOverlays[k])
        }
        mapPage.routeOverlays = newOverlays
        var newMarkers = []
        for (var m = 0; m < mapPage.routeMarkers.length; m++) {
            if (mapPage.routeMarkers[m].routeId !== rid) newMarkers.push(mapPage.routeMarkers[m])
        }
        mapPage.routeMarkers = newMarkers
        var newDangers = []
        for (var n = 0; n < mapPage.dangerMarkers.length; n++) {
            if (mapPage.dangerMarkers[n].routeId !== rid) newDangers.push(mapPage.dangerMarkers[n])
        }
        mapPage.dangerMarkers = newDangers
        // 2026-09-15: 同步清 waypointMarkers
        var newWp = []
        for (var wp = 0; wp < mapPage.waypointMarkers.length; wp++) {
            if (mapPage.waypointMarkers[wp].routeId !== rid) newWp.push(mapPage.waypointMarkers[wp])
        }
        mapPage.waypointMarkers = newWp
    }

    // 2026-09-15: 自驾游 (TravelService) - 也支持多选叠加
    function addOrToggleTravel(travel) {
        if (!travel || !travel.id) return
        var tid = travel.id
        // 借用 selectedRouteIds 集合(语义相同, 都是地理线)
        if (mapPage.selectedRouteIds.indexOf(tid) >= 0) {
            mapPage.removeRoute(tid)
            return
        }

        var coords = []
        if (mapPage._validCoord(travel.startLat, travel.startLon)) {
            coords.push(QtPositioning.coordinate(travel.startLat, travel.startLon))
        }
        if (mapPage._validCoord(travel.endLat, travel.endLon)) {
            coords.push(QtPositioning.coordinate(travel.endLat, travel.endLon))
        }

        if (coords.length >= 2) {
            var ci = mapPage._freeColorIdx()
            mapPage.routeOverlays = mapPage.routeOverlays.concat([{
                id: tid,
                name: travel.name || "(自驾游)",
                colorIdx: ci,
                color: mapPage._colorForIndex(ci),
                path: coords,
                kind: "travel",
                // travel.json 只有 startLat/Lon 与 endLat/Lon, 没有任何路径点,
                // 所以自驾游在图上永远是一条示意直线.
                approx: true,
                precisionM: travel.coordPrecisionM,
                coordSource: travel.coordSource
            }])
            var markers = []
            markers.push({ routeId: tid, coord: coords[0], label: "S", color: mapPage._colorForIndex(ci) })
            markers.push({ routeId: tid, coord: coords[coords.length - 1], label: "E", color: mapPage._colorForIndex(ci) })
            mapPage.routeMarkers = mapPage.routeMarkers.concat(markers)
        } else if (coords.length === 1) {
            // 2026-10-27 #134: 原来这一支只塞 marker 就往下走 selectedRouteIds.concat,
            //   于是"只有一个端点能用"的自驾进了选中集却不在清单里 —— 画不出、也删不掉,
            //   和路线那边 A5「已选 2 项却只列 1 行」是同一个坑 (那边已按"选上就一定在
            //   列表里"修过, 这里补齐).
            var ci2 = mapPage._freeColorIdx()
            mapPage.routeOverlays = mapPage.routeOverlays.concat([{
                id: tid,
                name: travel.name || "(自驾游)",
                colorIdx: ci2,
                color: mapPage._colorForIndex(ci2),
                path: coords,
                kind: "travel",
                approx: true,
                precisionM: travel.coordPrecisionM,
                coordSource: travel.coordSource
            }])
            mapPage.routeMarkers = mapPage.routeMarkers.concat([{
                routeId: tid,
                coord: coords[0],
                label: "S",
                color: mapPage._colorForIndex(ci2)
            }])
        }
        mapPage.selectedRouteIds = mapPage.selectedRouteIds.concat([tid])
        mapPage.fitBoundsToRoutes()
    }

    // 2026-09-15: 自动 fit bounds - 包含所有选中的路线 + 轨迹
    // 2026-10-22 #82: 档位改由 CommonOptions.fitBounds 按 web-mercator 反推, 与本页
    //   比例尺同一个口径. 旧的"经验公式 z = round(9 - log2(km))"注释里自己写着
    //   "1 km → z15", 代码算出来却是 z≈10 (1 km 的视野在 z10 宽约 200 km), 差约 7 档:
    //   线被压到亚像素 → 用户报的"选了轨迹不画线"和"多选后比例尺跳到 200km"是同一个
    //   错的两处表现. 另外原逻辑按整块 Map 居中, 而底栏抽屉 (MapBottomSheet, 高
    //   min(0.6h, 480)) 就压在地图上, 居中的线有一段正好落在板子底下.
    // 2026-10-29 (问题2): 返回 false = 视野没能设上 (还没布局出宽高 / 坐标算不出来).
    //   调用方据此下一轮再试一次 —— 原来是静默 return, 页面初建时正好踩中"线加进去了
    //   但视野没动", 屏幕上看就是没画.
    function fitBoundsToRoutes() {
        var allCoords = []
        for (var i = 0; i < mapPage.routeOverlays.length; i++) {
            for (var p = 0; p < mapPage.routeOverlays[i].path.length; p++) {
                allCoords.push(mapPage.routeOverlays[i].path[p])
            }
        }
        for (var t = 0; t < mapPage.trackOverlays.length; t++) {
            for (var q = 0; q < mapPage.trackOverlays[t].path.length; q++) {
                allCoords.push(mapPage.trackOverlays[t].path[q])
            }
        }
        if (allCoords.length === 0) return false

        var minLat = allCoords[0].latitude, maxLat = allCoords[0].latitude
        var minLon = allCoords[0].longitude, maxLon = allCoords[0].longitude
        for (var j = 1; j < allCoords.length; j++) {
            var c = allCoords[j]
            if (c.latitude < minLat) minLat = c.latitude
            if (c.latitude > maxLat) maxLat = c.latitude
            if (c.longitude < minLon) minLon = c.longitude
            if (c.longitude > maxLon) maxLon = c.longitude
        }

        // 可视区 = Map 减掉展开的抽屉, 四周再留 pad 的呼吸位 (线不贴屏边/板边).
        var pad = 24
        var sheetH = bottomSheet.visible ? bottomSheet.height : 0
        if (!isFinite(sheetH) || sheetH < 0) sheetH = 0
        sheetH = Math.min(sheetH, map.height * 0.7)
        // 上限收到 16: 单条 200 m 的轨迹不该顶到 maximumZoomLevel (18) —— 那一档
        //   Esri/高德的瓦片经常没有, 视野对了但底图空白, 又变成"什么都没画".
        var f = CommonOptions.fitBounds(minLat, maxLat, minLon, maxLon,
                                        map.width, map.height,
                                        pad, pad,
                                        map.width - 2 * pad,
                                        map.height - sheetH - 2 * pad,
                                        map.minimumZoomLevel,
                                        Math.min(map.maximumZoomLevel, 16))
        if (!f || !isFinite(f.zoom) || !isFinite(f.centerLat) || !isFinite(f.centerLon))
            return false
        map.center = QtPositioning.coordinate(f.centerLat, f.centerLon)
        map.zoomLevel = f.zoom
        mapPage.currentZoom = f.zoom
        return true
    }

    function onTrackSelected(trackId, track) {
        // 2026-09-15: 轨迹联动 - 拉轨迹点, 画 polyline, 多选叠加
        mapPage.addOrToggleTrack(trackId, track)
    }

    // silent: 进页复原会话时为 true —— 那批失败只值得一条 console, 不该在用户刚打开
    //   地图时连弹三个提示.
    function addOrToggleTrack(trackId, track, silent) {
        if (!trackId) return
        if (mapPage.selectedTrackIds.indexOf(trackId) >= 0) {
            mapPage.removeTrack(trackId)
            return
        }
        var points = mapService.getTrackPoints(trackId)
        if (!points || points.length < 1) {
            console.warn("[map] 轨迹 " + trackId + " 没有任何点 (track_<id>_points.json 为空或不存在)")
            if (!silent) toast.warn("这条轨迹在本机没有存下任何点, 画不到图上")
            return
        }
        // 2026-10-29 (问题2): 逐点校验改成与 C++ 侧同一个坐标门 (_validCoord):
        //   原来只挡 NaN, 于是 (0,0) 这种"没填"的哨兵会一路进 path —— 抽稀后整条线可能
        //   落在几内亚湾, fitBounds 也跟着跑到那儿, 屏上就是"没有线". 另外兼容
        //   {lat,lon} 形状: 只有 QGeoCoordinate 才有 latitude/longitude.
        var coords = []
        var bad = 0
        for (var i = 0; i < points.length; i++) {
            var p = points[i]
            var la = Number.NaN, lo = Number.NaN
            if (p) {
                la = (p.latitude !== undefined) ? Number(p.latitude) : Number(p.lat)
                lo = (p.longitude !== undefined) ? Number(p.longitude) : Number(p.lon)
            }
            if (mapPage._validCoord(la, lo)) coords.push(QtPositioning.coordinate(la, lo))
            else ++bad
        }
        if (coords.length === 0) {
            console.warn("[map] 轨迹 " + trackId + ": " + points.length
                         + " 个点全部无效 (缺经纬度 / NaN / (0,0))")
            if (!silent) toast.error("这条轨迹的 " + points.length
                                     + " 个点都不是有效坐标, 画不到图上")
            return
        }

        // 2026-10-27 #134: 两步路一条徒步能给到 1.2 万~2.4 万个点 (手头文件实测
        //   12552 / 24075). MapPolyline 每帧要把整条 path 重投影, 这个量级上抽屉
        //   一开、地图一动就会卡成幻灯片. 画线按步长抽稀到 <=2000 顶点, 首末点必留
        //   (线头和线尾是用户认这条线的锚), 统计/剖面仍走 mapService 的全量点。
        //   行数照实写全量点, 并标一句"画线已抽稀", 不让人把抽稀后的折线当成原始轨迹。
        var drawn = coords
        var thinned = false
        if (coords.length > 2000) {
            var stride = Math.ceil(coords.length / 2000)
            drawn = []
            for (var s = 0; s < coords.length; s += stride) drawn.push(coords[s])
            if (drawn[drawn.length - 1] !== coords[coords.length - 1]) {
                drawn.push(coords[coords.length - 1])
            }
            thinned = true
        }

        // 2026-10-27 #134: 名称原来硬写 "(轨迹)". 导入进来的两步路轨迹标题就在
        //   track_<id>.json 里 (现在 importKml 也真的把它写进去了), 记录 Tab 那条
        //   又已经带在信号里 —— 两个都拿不到才回落到"未命名轨迹".
        //   不拿名字的话, 已选清单和概览面板标题一起塌成 "(轨迹)", 叠了两条就分不清.
        var trackName = (track && track.name) ? track.name : ""
        if (trackName.length === 0) {
            var meta = mapService.getTrackById(trackId)
            if (meta && meta.ok && meta.value && meta.value.name) trackName = meta.value.name
        }
        if (trackName.length === 0) trackName = "未命名轨迹"

        var ci = mapPage._freeColorIdx()
        mapPage.trackOverlays = mapPage.trackOverlays.concat([{
            id: trackId,
            name: trackName,
            colorIdx: ci,
            color: mapPage._colorForIndex(ci),
            path: drawn,
            pointCount: coords.length,
            thinned: thinned
        }])
        mapPage.selectedTrackIds = mapPage.selectedTrackIds.concat([trackId])
        // 2026-10-29 (问题2): 单点轨迹 MapPolyline 一个像素都不画 (它要 >=2 点), 但行上
        //   照样显示"已加载" —— 补一颗点, 至少能看见这条轨迹在哪儿.
        if (drawn.length < 2) {
            mapPage.trackMarkers = mapPage.trackMarkers.concat([{
                trackId: trackId,
                coord: drawn[0],
                color: mapPage._colorForIndex(ci)
            }])
        }
        // 2026-10-29 (问题2): 判据行: 点数/无效点/画几个顶点. 真机上"没有线"时,
        //   logcat 里这一行就能分清是数据没了、坐标坏了, 还是数据都在只是没画出来.
        console.log("[map] 轨迹 " + trackId + ": points=" + points.length
                    + " valid=" + coords.length + " bad=" + bad
                    + " drawn=" + drawn.length + (thinned ? " (已抽稀)" : "")
                    + " overlays=" + mapPage.trackOverlays.length)
        if (!mapPage.fitBoundsToRoutes()) {
            // 页面初建 / 抽屉刚展开时 Map 可能还没量出宽高, fitBounds 会"不动" ——
            //   下一轮事件循环再套一次视野, 线才不会留在上一块屏幕上.
            Qt.callLater(mapPage.fitBoundsToRoutes)
        }
    }

    function removeTrack(trackId) {
        var ids = []
        for (var i = 0; i < mapPage.selectedTrackIds.length; i++) {
            if (mapPage.selectedTrackIds[i] !== trackId) ids.push(mapPage.selectedTrackIds[i])
        }
        mapPage.selectedTrackIds = ids
        var newOverlays = []
        for (var k = 0; k < mapPage.trackOverlays.length; k++) {
            if (mapPage.trackOverlays[k].id !== trackId) newOverlays.push(mapPage.trackOverlays[k])
        }
        mapPage.trackOverlays = newOverlays
        // 单点轨迹的标记 (见 addOrToggleTrack) 跟着 overlay 一起走
        var newPts = []
        for (var m = 0; m < mapPage.trackMarkers.length; m++) {
            if (mapPage.trackMarkers[m].trackId !== trackId) newPts.push(mapPage.trackMarkers[m])
        }
        mapPage.trackMarkers = newPts
    }

    // 2026-09-15: 清空所有选择
    function clearSelections() {
        mapPage.selectedRouteIds = []
        mapPage.selectedTrackIds = []
        mapPage.routeOverlays = []
        mapPage.routeMarkers = []
        mapPage.waypointMarkers = []
        mapPage.dangerMarkers = []
        mapPage.trackOverlays = []
        mapPage.trackMarkers = []
    }

    // 2026-10-23 #109: 「轨迹」Tab 的清空只抹轨迹, 不动已选路线 —— 那颗按钮就在轨迹列表
    //   头上, 用户按它的预期是"把画出来的线擦掉", 顺手清路线等于越权删掉他另一屏的选择.
    function clearTrackSelections() {
        if (mapPage.selectedTrackIds.length === 0 && mapPage.trackOverlays.length === 0) {
            toast.info("盘上没有已画的轨迹")
            return
        }
        var n = mapPage.selectedTrackIds.length
        mapPage.selectedTrackIds = []
        mapPage.trackOverlays = []
        mapPage.trackMarkers = []
        toast.success("已擦掉 " + n + " 条轨迹线")
    }

    // 2026-09-15: 打开概览面板 (kind: route / travel / track)
    function openSummary(kind, id, name) {
        summaryDialog.kind = kind
        summaryDialog.itemId = id
        summaryDialog.name = name || ""
        summaryDialog.open()
    }

    // 2026-09-14: P1 跳转轨迹分析详情, 通过 signal 上抛, 不直接调外层 stackView
    function openTrackDetail(trackId) {
        if (!trackId) return
        mapPage.ApplicationWindow.window.navBus.trackDetail(trackId)
    }

    // 2026-09-11: 线路支持外部数据格式导入 (GPX/KML/CSV 三种, 复用 mapService
    // 现有 importGpx / importKml / importCsv 接口). 入口: 底栏「轨迹」Tab 的「导入」按钮
    // (2026-10-09 打通). 导入成功后 MapService emit dataChanged, NavigationTab 监听后自查刷新.
    //
    // 2026-10-28 (#148): 从"只有一颗系统选择器按钮"改成两条路 ——
    //   ① 搜本机: 用户在微信里收到的 .kml/.gpx 落在 com.tencent.mm 的下载目录, 那串
    //      路径人记不住、系统选择器也要翻好几层。C++ 侧 FileScanner 按候选根目录扫一遍,
    //      命中直接列在弹窗里, 点一行就导入。
    //   ② 系统选择器仍然留着: 没开"全部文件访问"时有些目录应用侧压根读不到,
    //      但系统那侧挑得进来 —— 挑回来的 content:// 走既有的"复制进沙盒"通道 (#134)。
    // 权限不在启动时要, 只有用户点「开启全部文件访问」才跳系统设置页。
    Dialog {
        id: importDialog
        modal: true   // L8 三件套之一: Qt6 的 Popup.modal 默认 false, 不写就是能点穿 (真机 F6)
        title: "导入外部轨迹"
        anchors.centerIn: parent
        width: Math.min(400, mapPage.width - 2 * styles.pageMargin)
        // 2026-10-20 #41: 取消按钮从正文里挪进 footer, 弹层底/前景显式绑 token.
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        // 上一次的结果不该在下一次打开时还挂在上面
        onAboutToShow: {
            mapPage._importStatus = ""
            mapPage._trackFindStatus = ""
        }
        footer: DialogFooter {
            kind: "plain"
            cancelText: ""
            confirmText: "关闭"
            onConfirm: importDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: styles.spMd

            Text {
                text: "支持 GPX (奥维/户外助手) / KML (Google Earth) / CSV (自建)。"
                      + "微信收到的文件可以按名字直接搜本机。"
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsSm
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // ① 搜本机
            RowLayout {
                spacing: styles.spSm
                Layout.fillWidth: true

                TextField {
                    id: trackFindField
                    Layout.fillWidth: true
                    Layout.preferredHeight: styles.fieldH
                    placeholderText: "按名字搜（可留空列全部）"
                    placeholderTextColor: CommonOptions.colorTextDim
                    color: CommonOptions.colorText
                    font.pixelSize: styles.fsMd
                    leftPadding: styles.spMd
                    rightPadding: styles.spSm
                    background: Rectangle {
                        radius: styles.rMd
                        color: CommonOptions.colorSurfaceDim
                        border.color: CommonOptions.colorDivider
                        border.width: styles.lineHair
                    }
                    onAccepted: mapPage.searchTrackFiles(text)
                }

                OutlineButton {
                    Layout.alignment: Qt.AlignVCenter
                    text: mapPage._trackSearching ? "搜索中" : "搜索本机"
                    enabled: !mapPage._trackSearching
                    onClicked: mapPage.searchTrackFiles(trackFindField.text)
                }
            }

            Text {
                visible: mapPage._trackFindStatus.length > 0
                text: mapPage._trackFindStatus
                      + (mapPage._trackFindStatus.length > 0
                         && !mapPage._allFilesReadable ? "\n微信等目录要系统里给「全部文件访问」才搜得到" : "")
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsSm
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            ListView {
                id: trackFileList
                Layout.fillWidth: true
                // 命中才占高; 没命中时这一格必须是 0, 否则弹窗里挂一片死空间 (#109 那一类)
                Layout.preferredHeight: mapPage._trackFileHits.length > 0
                    ? Math.min(contentHeight, 4 * (styles.rowHTall + styles.cardGap))
                    : 0
                visible: Layout.preferredHeight > 0
                clip: true
                spacing: styles.cardGap
                boundsBehavior: Flickable.StopAtBounds
                model: mapPage._trackFileHits

                delegate: Rectangle {
                    required property var modelData

                    width: trackFileList.width
                    height: styles.rowHTall
                    color: "transparent"

                    ListRow {
                        anchors.fill: parent
                        dense: true
                        showChevron: false
                        title: modelData.name
                        subtitle: mapPage._fileHitSubtitle(modelData)
                        subtitleColor: CommonOptions.colorTextDim
                        titleColor: CommonOptions.colorText
                        accent: CommonOptions.colorAccentSoft
                        bg: CommonOptions.colorSurface
                        onClicked: mapPage.importTrackFromPath(modelData.path)
                    }
                }
            }

            // ② 系统选择器 + 权限入口 (只在读不到时才出现, 不给已经能读的人多看一颗)
            RowLayout {
                spacing: styles.spSm

                OutlineButton {
                    Layout.alignment: Qt.AlignVCenter
                    text: "系统选择器…"
                    onClicked: importFileDialog.open()
                }
                OutlineButton {
                    visible: !mapPage._allFilesReadable
                    Layout.alignment: Qt.AlignVCenter
                    text: "开启全部文件访问"
                    onClicked: mapPage.openAllFilesAccess()
                }
            }

            Text {
                visible: mapPage._importStatus.length > 0
                text: mapPage._importStatus
                color: mapPage._importStatusColor
                font.pixelSize: styles.fsSm
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }

    property string _importStatus: ""
    property color _importStatusColor: CommonOptions.colorTextMuted

    // === #148 本机轨迹文件搜索的状态 ===
    property var _trackFileHits: []
    property string _trackFindStatus: ""
    property bool _trackSearching: false
    // 默认按"能读"处理: 这颗按钮只在实测读不到时才露面, 不预先吓用户一次。
    // 值来源是搜索那一次顺带问回来的, 所以进弹窗不搜东西时它是默认态 —— 正常。
    property bool _allFilesReadable: true
    property string _trackFindKeyword: ""

    // 扫描是同步的磁盘遍历, 放到下一轮事件循环再跑: 先把「搜索中」画出来,
    // 不然按钮点了像没反应 (野外设备上 FUSE 列目录可以到几百毫秒)。
    Timer {
        id: trackFindTimer
        interval: 50
        repeat: false
        onTriggered: mapPage._scanTrackFiles()
    }

    function searchTrackFiles(kw) {
        mapPage._trackFindKeyword = String(kw || "").trim()
        mapPage._trackSearching = true
        mapPage._trackFindStatus = "正在搜索本机…"
        mapPage._importStatus = ""
        trackFindTimer.restart()
    }

    function _scanTrackFiles() {
        if (!androidPlatform || typeof androidPlatform.searchTrackFiles !== "function") {
            mapPage._trackSearching = false
            mapPage._trackFindStatus = "这台设备没有本机文件搜索, 用系统选择器"
            return
        }
        var hits = androidPlatform.searchTrackFiles(mapPage._trackFindKeyword) || []
        mapPage._allFilesReadable = (typeof androidPlatform.canReadAllFiles === "function")
            ? androidPlatform.canReadAllFiles() : true
        mapPage._trackFileHits = hits
        mapPage._trackSearching = false
        mapPage._trackFindStatus = hits.length > 0
            ? ("找到 " + hits.length + " 个，点一行直接导入")
            : (mapPage._trackFindKeyword.length > 0
                ? ("没有文件名含「" + mapPage._trackFindKeyword + "」的 GPX/KML/CSV")
                : "没搜到可导入的 GPX/KML/CSV")
        // 判据行: 真机上"搜不到"分三种 (没那个目录 / 目录读不到 / 读了没匹配),
        // 逐根明细在 C++ 侧 [filescan] 已经打过, 这里只记这一条决定 UI 的结果。
        console.log("[trackfind] kw=" + mapPage._trackFindKeyword + " hits=" + hits.length
                    + " allFiles=" + mapPage._allFilesReadable)
    }

    function openAllFilesAccess() {
        if (androidPlatform && typeof androidPlatform.openAllFilesAccessSettings === "function")
            androidPlatform.openAllFilesAccessSettings()
    }

    function _fileHitSubtitle(hit) {
        var bytes = Number(hit.sizeBytes || 0)
        var size = bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + " MB"
                     : bytes >= 1024 ? Math.round(bytes / 1024) + " KB" : bytes + " B"
        var when = Qt.formatDateTime(new Date(Number(hit.mtimeMs || 0)), "yyyy-MM-dd hh:mm")
        // 目录只给末两段: 全路径在 400dp 宽的弹窗里必定折行成三行
        var parts = String(hit.dir || "").split("/")
        var tail = parts.length > 2 ? parts[parts.length - 2] + "/" + parts[parts.length - 1]
                                    : String(hit.dir || "")
        return size + " · " + when + (tail.length > 0 ? " · " + tail : "")
    }

    // 本地路径 → 解析入库 → 画线。系统选择器与本机搜索两条路都汇到这里。
    // hintUri: 复制进沙盒时源 URI 末段可能没带扩展名, 让调用方能回看它认格式 (#134)。
    function importTrackFromPath(localPath, hintUri) {
        var path = String(localPath || "").replace(/^file:\/\//, "")
        if (path.length === 0) {
            mapPage._importStatus = "没拿到文件地址"
            mapPage._importStatusColor = CommonOptions.colorLegendAmber
            return
        }
        var kind = mapPage._trackFileKind(path)
        if (kind.length === 0 && hintUri)
            kind = mapPage._trackFileKind(hintUri)
        var r = null
        if (kind === "gpx") {
            r = mapService.importGpx(path)
        } else if (kind === "kml") {
            r = mapService.importKml(path)
        } else if (kind === "csv") {
            r = mapService.importCsv(path)
        } else {
            // 2026-10-19: _importStatus 由默认字体的 Text 显示, PUA 码位是方框 → 去码位留文字.
            // 2026-10-20: colorRedBright 与 SOS 的危险红同值, 一次导入失败不配用
            //   危险色 → 常驻提示统一用 legend amber (同装备页口径).
            mapPage._importStatus = "不支持的文件格式: " + path.split("/").pop()
            mapPage._importStatusColor = CommonOptions.colorLegendAmber
            return
        }
        if (r && r.ok && r.value) {
            var trackId = r.value
            // 2026-09-15: 导入成功后, 在当前地图上自动画线 + fit
            // (不再 push TrackDetailPage; 用户随时可在「已选」浮卡里点该行右侧的
            //  等号柱图标按钮打开概览面板, 详情页从那儿进)
            var r2 = mapService.getTrackById(trackId)  // 2026-10-09: 契约切 Result, 读 .value
            var meta = (r2 && r2.ok) ? r2.value : null
            var trackName = (meta && meta.name) ? meta.name : "(导入轨迹)"
            mapPage._importStatus = "导入成功: " + trackName
            mapPage._importStatusColor = CommonOptions.colorSuccess
            // 2026-10-09: MapService 导入时已 emit dataChanged, NavigationTab 监听后自查刷新.
            importDialog.close()
            // 2026-10-27 #134: 把刚读到的 meta 一起递给 addOrToggleTrack ——
            //   它原来只拿 id, 名字要靠再查一次; 递过来就少一次磁盘读, 列表行
            //   也不会先闪 "未命名轨迹" 再改名.
            mapPage.addOrToggleTrack(trackId, meta)
        } else {
            // 2026-09-21: 失败时显示具体错误 (Result.error.message)
            var errMsg = (r && r.error && r.error.message) || "未知错误"
            mapPage._importStatus = "导入失败: " + errMsg
            mapPage._importStatusColor = CommonOptions.colorLegendAmber
        }
    }

    FileDialog {
        id: importFileDialog
        title: "选择轨迹文件"
        nameFilters: ["轨迹文件 (*.gpx *.kml *.csv)", "GPX (*.gpx)", "KML (*.kml)", "CSV (*.csv)"]
        onAccepted: {
            // 2026-09-21: Phase 5 - importXxx 返回 Result {ok, value=trackId, error}.
            // 2026-10-20: Qt 6.7 起 selectedFile 是废弃名, 与拍照检索页同一套写法 ——
            //   先 currentFile, 取不到再退回; 两个都空就说清楚, 不把 "undefined" 当路径
            //   送进 importGpx 然后报一个用户看不懂的解析错误.
            var url = ""
            if (currentFile && currentFile.toString().length > 0) {
                url = currentFile.toString()
            } else if (selectedFile && selectedFile.toString().length > 0) {
                url = selectedFile.toString()
            }
            if (url.length === 0) {
                mapPage._importStatus = "系统没回传文件地址"
                mapPage._importStatusColor = CommonOptions.colorLegendAmber
                return
            }
            // 2026-10-27 #134: Android 11+ 的文件选择器回的是 content:// URI, QFile
            //   打不开它 —— 原先这里只剥 file://, 于是真机上选完两步路 KML 直接
            //   "无法打开 KML 文件", 解析器根本没被跑到. 走拍照检索同一套"复制进沙盒"
            //   通道 (androidPlatform.importImage, 后缀现在会保留 .kml/.gpx/.csv).
            var local = url
            if (androidPlatform) {
                var copied = androidPlatform.importImage(url)
                if (copied && copied.length > 0) {
                    local = copied
                } else if (url.indexOf("content://") === 0) {
                    mapPage._importStatus = "这个文件应用复制不到本地, 换一次的下载目录或先存到本机"
                    mapPage._importStatusColor = CommonOptions.colorLegendAmber
                    return
                }
            }
            // 2026-10-28 (#148): 认格式 + 入库 + 画线这一段与"搜本机"那条路完全同构,
            //   收进 importTrackFromPath, 两处共用一份 (原来两份复制体各自漂移过).
            mapPage.importTrackFromPath(local, url)
        }
    }
}
