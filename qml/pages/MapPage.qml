/**
 * @file MapPage.qml
 * @brief ④地图 (2026-10-20 丁骨架: 满幅底图 + 仪表叠层 + 目标驱动的底部抽屉)
 *
 * 布局:
 *   - 满幅 Map (osm 瓦片, 北朝上), 可手动拖动/双击缩放 (#43)
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

    property real currentLat: 39.9087
    property real currentLon: 116.3975
    property real currentHeading: 0
    property bool hasFix: false
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
    //   回写; 定位更新不再自动抢中心 (见 PositionSource), 用户看哪儿地图就停哪儿.
    // 可视范围 (中心/缩放), 由 Map 拖拽与缩放回写. 「目标」半径查询与"标注这里"用它们,
    // 而不是 currentLat/Lon (那两个是 GPS 位置, 画蓝点用的).
    property real viewLat: mapPage._restoredView[0]
    property real viewLon: mapPage._restoredView[1]
    property real viewZoom: currentZoom
    // 换底图重建本页后要落回原来看的这块视野 (写进窗口级会话, 见 Main.qml).
    //   [0]=lat [1]=lon [2]=zoom; NaN/-1 = 没有可恢复的视野 → 用 GPS 位置与默认缩放.
    //   只做初值: Map 的 center/zoomLevel 没有声明式绑定 (见上 #43), 这里给一次命令式.
    readonly property var _restoredView: {
        var w = mapPage._appWin
        if (w && isFinite(w.mapViewLat) && isFinite(w.mapViewLon))
            return [w.mapViewLat, w.mapViewLon,
                    (isFinite(w.mapViewZoom) && w.mapViewZoom > 0) ? w.mapViewZoom : 11]
        return [currentLat, currentLon, 11]
    }

    // === ④地图 丁仪表 (2026-10-20 #61) =====================================
    // 朝向与 ①营地 同一个来源 (compassSensor), 两页读数不一致比没有读数更糟.
    readonly property bool hasHeading: compassSensor ? compassSensor.valid : false
    readonly property real headingDeg: hasHeading ? compassSensor.heading : 0
    readonly property int calibPct: compassSensor ? compassSensor.calibrationPercent : -1

    // 比例尺: 标准 web-mercator 反推 (156543.03·cos(lat)/2^z = 赤道每像素米数),
    //   不依赖 Map 的私有 API. 先按 62px 期望宽度取出档位, 再回算尺子真正的像素宽,
    //   这样 "500 m" 那句话和上面那条线永远是对齐的 —— 写死 62px 会谎报比例.
    readonly property int mapZoomInt: Math.round(viewZoom)
    readonly property real _metersPerPixel: 156543.03392
        * Math.cos(viewLat * Math.PI / 180) / Math.pow(2, mapZoomInt)
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
                tone: CommonOptions.dangerColor(Number(m.dangerLevel) || 0)
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
            var lvl = Number(m.dangerLevel) || 0
            rows.push({
                id: m.id || "",
                speciesId: m.speciesId || "",
                title: m.speciesName || CommonOptions.speciesCategoryLabel(m.speciesCategory || ""),
                sub: CommonOptions.speciesCategoryLabel(m.speciesCategory || ""),
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

    // 2026-09-15: 危险物种缓存 {speciesId: dangerLevel} - 一次性查全, 给 marker 颜色用
    property var _speciesCache: null
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
    // - routeOverlays: [{id, name, color, path: [coord,...]}]
    // - routeMarkers: [{routeId, coord, label, color}] 起点 S / 终点 E
    // - waypointMarkers: [{routeId, coord, name, type}] 路径点 (营地/垭口等)
    // - dangerMarkers: [{routeId, coord, name}] 危险点
    // - trackOverlays: [{id, name, color, path}]
    property var routeOverlays: []
    property var routeMarkers: []
    property var waypointMarkers: []
    property var dangerMarkers: []
    property var trackOverlays: []
    // 已选 id 集合 (避免重复)
    property var selectedRouteIds: []
    property var selectedTrackIds: []
    // 2026-09-15: 路线种类的颜色: 自驾/徒步 颜色不同, 便于视觉区分
    // 2026-10-16 改版: 删掉本地 8 色 _routePalette (它和 CommonOptions.categoryColor
    //   的 8 色板是同一份东西抄了两遍, 只是顺序不同 → 文档 B2 "颜色重复定义").
    //   统一走 categoryColor, 索引按选择顺序取模, 颜色顺序与全站分类色一致.
    function _colorForIndex(idx) {
        return CommonOptions.categoryColor(idx)
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
    function _validCoord(la, lo) {
        return isFinite(la) && isFinite(lo) &&
               Math.abs(la) <= 90 && Math.abs(lo) <= 180
    }

    // 2026-09-19: 启动时申请关键权限 (位置 + 相机). MapPage 是主页,
    //   PositionSource 需要 ACCESS_FINE_LOCATION 才能拿到 GPS,
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
        // 2026-09-19: 申请运行时权限 (ACCESS_FINE_LOCATION + CAMERA)
        // Qt.callLater 等 PositionSource 完成 active 切换再调, 避免启动期 Qt 主线程忙
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

    // 「目标」Tab 里点一行 → 把地图挪到那个点, 抽屉收起来让罗盘重新对上.
    //   只挪中心不改缩放档位太多: 用户可能已经在看全局, 跳到 z16 反而丢上下文.
    function focusTarget(t) {
        if (!t) return
        var la = Number(t.lat), lo = Number(t.lon)
        if (!mapPage._validCoord(la, lo)) return
        map.center = QtPositioning.coordinate(la, lo)
        map.zoomLevel = Math.max(map.zoomLevel, 14)
        bottomSheet.close()
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

    function annotateHere() {
        // 在地图中心插一个物种标注 (默认类别 photo, 物种 id 留空).
        // 2026-10-19: 改用 viewLat/viewLon —— 这是"标注这里"的按钮, 用户先把地图拖
        //   到目标位置再点, 原来取的是 GPS 位置 (无权限时恒为默认北京), 标的永远
        //   不是看的那个点.
        // 2026-10-20 #61 修参数: addSpeciesLocation 的签名是
        //   (speciesId, speciesName, category, lat, lon, altitude, note), 原来只传 5 个
        //   位置参数 → viewLat 落进 category, viewLon 落进 lat, "manual" 落进 lon 被转成
        //   0. 写出去的标注全在 (lon≈0) 大西洋上, ①营地 方位条因此指错方向.
        // 返回值也是 Result 信封 {ok,value}, 不是 bool —— 旧 `if (ok)` 恒真.
        var res = mapService.addSpeciesLocation("", "", "", viewLat, viewLon, 0, "manual")
        if (res && res.ok) {
            console.log("annotateHere: ok at", viewLat, viewLon)
        } else {
            console.warn("annotateHere failed:", res && res.error ? res.error.message : res)
        }
    }

    function onPhotoTaken(uri) {
        if (uri && uri.length > 0) {
            lastCapturedPhoto = uri
            // 提取 EXIF GPS + 加到 mapService
            var exif = mapService.extractExif(uri.replace("file://", ""))
            if (exif && exif.lat && exif.lon) {
                mapService.addSpeciesLocation("", "", "", exif.lat, exif.lon, 0,
                                              "field_guide")
            } else if (mapPage.hasFix) {
                // 没 EXIF 就用自己的定位; 两者都没有就不写 —— currentLat/Lon 在无授权时
                // 是写死的北京默认值, 标上去等于给用户攒一批假点 (同 ③ 详情页规则②).
                mapService.addSpeciesLocation("", "", "", currentLat, currentLon, 0,
                                              "field_guide")
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

    // 2026-09-19: 启动系统定位, 把实时经纬度/航向写回 mapPage 字段
    // 之前 currentLat/currentLon/currentHeading 只是默认值 (北京), 从未更新,
    // 所以 hasFix 永远 false, 中心点 marker 一直停在默认位置. 加 PositionSource
    // 后有 GPS 时自动 updatePosition, 没 GPS 时保持默认值 + 提示用户.
    PositionSource {
        id: positionSource
        active: true
        preferredPositioningMethods: PositionSource.AllPositioningMethods
        updateInterval: 2000
        onPositionChanged: {
            if (position.coordinate && position.coordinate.isValid) {
                mapPage.currentLat = position.coordinate.latitude
                mapPage.currentLon = position.coordinate.longitude
                if (position.direction >= 0) {
                    mapPage.currentHeading = position.direction
                }
                mapPage.hasFix = true
                // 2026-10-19: 这里不再自动把 map.center 拉过来. center 原来绑
                //   currentLat/Lon, 定位每 2s 写一次就把用户刚拖完的地图拽回原位.
                //   现在定位只更新蓝点 (currentLat/Lon), 要看自己位置就点"我的位置".
            }
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError) {
                console.log("MapPage PositionSource error:", sourceError)
            }
        }
    }

    // 2026-10-09: 底图「真多源切换」. Qt6 OSM plugin 只在 Map.plugin 赋值瞬间
    //   读取 PluginParameter, 运行期改 .value 无效; 且 OSM plugin 通常只有 1 个
    //   supportedMapType (旧 activeMapType[Math.min(...)] 是假切换根因).
    //   2026-10-20 修正这条说法: Map.plugin 不只是「只在赋值瞬间读参数」, 它压根
    //   只允许赋一次 (write-once), 造新 Plugin 再换进去会被 Qt 直接忽略 → 切底图
    //   从来没生效过. 现在切换走 _rebuildForBaseMap 重建本页, 只依赖
    //   osm.mapping.host 的 path base. 五源见 mapPage._baseMaps.
    //   !!! 注意: Map 初值必须是非空 Plugin (见 Map 内注释), 否则 setPlugin 空指针崩.
    // 2026-10-19 白底真根因 (容器内离线复现, 见 app/_maptest/ 探针 + doc 记录):
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
    //   想要卫星图: 需在自己 CDN 上铺一个 z/x/y → Esri z/y/x 的反向代理, 再回来加源.
    readonly property var _baseMaps: [
        { name: "标准地图",
          // OSM 德国镜像, 带中文地名. 实测简中直连 200 (主站 tile.openstreetmap.org 超时).
          host: "https://tile.openstreetmap.de/",
          copyright: "© OpenStreetMap contributors (tile.openstreetmap.de)" },
        { name: "彩色路网",
          // CARTO Voyager: OSM 数据 + 彩色渲染, 户外看路/看水系够用.
          host: "https://basemaps.cartocdn.com/rastertiles/voyager/",
          copyright: "© OpenStreetMap contributors, © CARTO" },
        { name: "浅色底图",
          // CARTO Positron: 低饱和灰白, 叠轨迹/POI 时最不容易糊.
          host: "https://basemaps.cartocdn.com/light_all/",
          copyright: "© OpenStreetMap contributors, © CARTO" },
        { name: "暗色底图",
          // CARTO Dark Matter: 夜间模式省眼.
          host: "https://basemaps.cartocdn.com/dark_all/",
          copyright: "© OpenStreetMap contributors, © CARTO" },
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
        Qt.callLater(function () { w.restartBand("route") })
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
                mapPage._failoverToNext(_errDiag)
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
        bearing: mapPage.hasFix ? mapPage.currentHeading : 0

        // 可视范围 → mapPage.viewLat/viewLon/viewZoom. 用定时器合并一次连续拖动/捏合,
        // 只在一阵操作停下来之后提交一次, 避免「目标」Tab 每帧重查.
        onCenterChanged: viewportCommitTimer.restart()
        onZoomLevelChanged: viewportCommitTimer.restart()

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
        }

        // 2026-10-20 #61: 中心的 DirectionCompassOverlay 删除 —— 右上已经有一枚迷你盘,
        //   同一屏两个罗盘互相抢读法, 而中心环跟着平移缩放走, 低 zoom 下字号糊.
        //   朝向读数只保留 MapInstrumentOverlay 里那一个 Dial.

        // 当前点
        MapQuickItem {
            coordinate: QtPositioning.coordinate(mapPage.currentLat, mapPage.currentLon)
            sourceItem: Rectangle {
                width: 14
                height: 14
                radius: 7
                color: CommonOptions.colorAccent
                border.color: CommonOptions.colorTextOnAccent
                border.width: 2
            }
        }

        // 物种标注 - 点击看详情 (按 dangerLevel 着色, 危险的高亮红色)
        // 2026-10-09: Repeater → MapItemView (视口虚拟化, 只为可见元素建 delegate),
        //   model 绑 mapPage.speciesLocations (NOTIFY-able), dataChanged 时整体替换触发刷新.
        MapItemView {
            id: speciesMarkerView
            model: mapPage.speciesLocations
            delegate: MapQuickItem {
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
                    readonly property int _lvl: {
                        if (mapPage._speciesCache === null) return -1  // 缓存未就绪
                        var spId = modelData.speciesId
                        if (spId && mapPage._speciesCache[spId] !== undefined) {
                            return mapPage._speciesCache[spId]
                        }
                        // 按类别 + 名称关键词估算
                        var cat = (modelData.speciesCategory || "").toLowerCase()
                        var name = (modelData.speciesName || "") + " " + (modelData.note || "")
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
                            mapPage.markerDetailTitle = "物种标注"
                            mapPage.markerDetailSub = "经纬度: " +
                                modelData.lat.toFixed(5) + ", " +
                                modelData.lon.toFixed(5)
                            mapPage.markerDetailRouteId = ""
                            mapPage.markerDetailCoord = QtPositioning.coordinate(
                                modelData.lat, modelData.lon)
                            mapPage.markerDetailNote = modelData.note || ""
                            mapPage.markerDetailSource = modelData.source || ""
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
                line.color: modelData.color
                line.width: 5
                path: modelData.path
            }
        }

        // 2026-09-15: 路线 起终点 marker (S / E) - 点击看路线详情
        Repeater {
            model: mapPage.routeMarkers
            delegate: MapQuickItem {
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
                        font.pixelSize: 11
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
                        font.pixelSize: 10
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
                line.color: modelData.color
                line.width: 4
                path: modelData.path
            }
        }

        // 2026-09-15: 长按地图 → 在长按点添加物种标注
        // TapHandler 不会与 Map 的 pan/pinch 冲突
        // 2026-10-20 #61 修参数: longPressed() 这个信号在 Qt 6 是**无参**的, 原来写
        //   `function(eventPoint, button)` → eventPoint 恒 undefined, 一点长按就
        //   "Cannot read property position of undefined", 长按标注从来没通过.
        //   触点要读 TapHandler.point.
        TapHandler {
            id: longPressHandler
            gesturePolicy: TapHandler.ReleaseWithinBounds
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

        // 2026-09-17: 双指缩放 - Qt 6.7 Map 控件自身已支持双指缩放手势, 无需自定义
        // 之前自定义 PinchHandler + onPinchUpdated/Finished 在 qmlcachegen 静态编译下
        // 报 "non-existent property" 让 MapPage 加载失败, 现在彻底删除
    }

    // 2026-09-15: 长按地图后弹的"添加标注"对话框
    property var pendingAnnotateCoord: null

    // 2026-09-15: 添加标注对话框 - 类别 + 物种 + 备注 + 自动 dangerLevel
    Dialog {
        id: addAnnotateDialog
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
            // 2026-10-20: ComboBox 的 currentIndex 在用户点选后就被控件自己打断了,
            //   上面把 selectedCategory 复位而 combo 还显示上一轮那一类 → "看着是动物、
            //   存进去是植物". 两个都必须在这里按回默认.
            catCombo.currentIndex = 3
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
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                }
            }

            // 类别
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "类别:"; color: CommonOptions.colorText; font.pixelSize: 12; Layout.preferredWidth: 50 }
                ComboBox {
                    id: catCombo
                    Layout.fillWidth: true
                    // 2026-10-19: 本字体没有 snake / mushroom / insect / plant / animal
                    //   专用字形 (\ue92b 实为垃圾桶之类), 原 "码位 + 中文" 混排整串走
                    //   Material Icons → 中文全方框. 类别改成纯文字.
                    model: addAnnotateDialog.categoryLabels
                    delegate: ItemDelegate {
                        id: catItem
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
                    currentIndex: 3
                    onActivated: {
                        addAnnotateDialog.selectedCategory = currentIndex
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
                Text { text: "物种:"; color: CommonOptions.colorText; font.pixelSize: 12; Layout.preferredWidth: 50 }
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
                    color: CommonOptions.colorTextOnAccent
                    font.pixelSize: 12
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
                toast.error("坐标没取到, 请重新长按地图")
                return
            }
            // speciesId + speciesName 来自 selection, category 存类别名
            var catKey = addAnnotateDialog.categoryKeys[addAnnotateDialog.selectedCategory] || "manual"
            var res = mapService.addSpeciesLocation(
                addAnnotateDialog.selectedSpeciesId,
                addAnnotateDialog.selectedSpeciesName,
                catKey,
                c.latitude, c.longitude, 0,
                noteField.text)
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

        footer: RowLayout {
            spacing: styles.spSm
            Item { Layout.fillWidth: true }
            OutlineButton {
                text: "取消"
                tone: CommonOptions.colorTextMuted
                onClicked: addAnnotateDialog.close()
            }
            PrimaryButton {
                text: "保存标注"
                tone: CommonOptions.colorAccent
                textSize: styles.fsMd
                onClicked: addAnnotateDialog.saveAndClose()
            }
        }
    }

    // 2026-09-15: marker 点击详情对话框 (复用, 根据 markerDetailKind 切换内容)
    Dialog {
        id: markerDetailDialog
        title: mapPage.markerDetailTitle
        anchors.centerIn: parent
        width: Math.min(420, mapPage.width - 2 * styles.pageMargin)
        // 2026-10-20 #41: 见 addAnnotateDialog 的同一处说明 (英文 Close → 中文 footer).
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        padding: styles.spMd
        footer: RowLayout {
            spacing: styles.spSm
            Item { Layout.fillWidth: true }
            OutlineButton {
                text: "关闭"
                tone: CommonOptions.colorTextMuted
                onClicked: markerDetailDialog.close()
            }
        }

        contentItem: ColumnLayout {
            spacing: 8

            Text {
                text: mapPage.markerDetailSub
                color: CommonOptions.colorText
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // 物种标注: 显示 note / source
            Text {
                visible: mapPage.markerDetailKind === "species"
                text: "备注: " + (mapPage.markerDetailNote || "(无)")
                color: CommonOptions.colorTextMuted
                font.pixelSize: 12
                Layout.fillWidth: true
            }
            Text {
                visible: mapPage.markerDetailKind === "species"
                text: "来源: " + (mapPage.markerDetailSource || "(手动)")
                color: CommonOptions.colorTextMuted
                font.pixelSize: 11
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
                font.pixelSize: 11
                Layout.fillWidth: true
            }

            // 起终点: 所属路线名
            Text {
                visible: mapPage.markerDetailKind === "route_endpoint"
                text: "所属路线: " + (mapPage._routeNameById(mapPage.markerDetailRouteId) || "")
                color: CommonOptions.colorTextMuted
                font.pixelSize: 12
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
                    enabled: !!mapPage.markerDetailRouteId
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

            // 物种标注: 删除 / 导航
            RowLayout {
                visible: mapPage.markerDetailKind === "species"
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 8

                OutlineButton {
                    text: "导航到此"
                    Layout.fillWidth: true
                    tone: CommonOptions.colorText
                    enabled: mapPage.markerDetailCoord !== null
                    onClicked: {
                        if (mapPage.markerDetailCoord) {
                            var c = mapPage.markerDetailCoord
                            CommonOptions.openMapMarker(c.latitude, c.longitude, "物种标注")
                        }
                    }
                }
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
        footer: RowLayout {
            spacing: styles.spSm
            Item { Layout.fillWidth: true }
            OutlineButton {
                text: "关闭"
                tone: CommonOptions.colorTextMuted
                onClicked: summaryDialog.close()
            }
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
        title: "已选 " + (mapPage.selectedRouteIds.length + mapPage.selectedTrackIds.length) + " 项"
        anchors.centerIn: parent
        width: Math.min(420, mapPage.width - 2 * styles.pageMargin)
        height: Math.min(parent.height * 0.7, 520)
        // 2026-10-20 #41: 两个动作从 contentItem 末尾挪进 footer —— 弹层里"操作"和
        //   "读数"分栏, 列表滚到底也不会把按钮挤出可视区.
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        footer: RowLayout {
            spacing: styles.spSm
            Item { Layout.fillWidth: true }
            OutlineButton {
                text: "关闭"
                tone: CommonOptions.colorTextMuted
                onClicked: selectedListDialog.close()
            }
            OutlineButton {
                text: "全部清空"
                tone: CommonOptions.colorDanger
                onClicked: {
                    mapPage.clearSelections()
                    selectedListDialog.close()
                }
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
                    width: ListView.view ? ListView.view.width : 0
                    height: 56
                    color: hoverArea.containsMouse ? CommonOptions.colorSurfaceDim : CommonOptions.colorSurface
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
                                    font.pixelSize: 14
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                text: (modelData.kind === "travel" ? "自驾游" : "徒步路线") +
                                      "  ·  " + modelData.path.length + " 个点"
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: 11
                            }
                        }

                        // 2026-09-15: 概览按钮 - 弹出 RouteSummaryPanel
                        Button {
                            contentItem: IconLabel {
                                name: "equalizer"
                                size: 18
                                tintColor: CommonOptions.colorTextOnAccent
                            }
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            Material.background: CommonOptions.colorAccent
                            Material.foreground: CommonOptions.colorTextOnAccent
                            onClicked: {
                                mapPage.openSummary(modelData.kind === "travel" ? "travel" : "route",
                                                     modelData.id, modelData.name)
                            }
                        }
                        Button {
                            contentItem: IconLabel {
                                name: "close"
                                size: 18
                                tintColor: CommonOptions.colorTextOnAccent
                            }
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            // 2026-10-21 #65: 原来是 colorDanger. 这个叉只是把线从当前
                            //   地图上摘掉 (routeOverlays/selectedRouteIds 少一项), 库里
                            //   数据一条没动, 重新勾选就回来了 —— 不配占用危险红.
                            Material.background: CommonOptions.colorAccent
                            Material.foreground: CommonOptions.colorTextOnAccent
                            onClicked: mapPage.removeRoute(modelData.id)
                        }
                    }

                    MouseArea { id: hoverArea; anchors.fill: parent; hoverEnabled: true }
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
                    width: ListView.view ? ListView.view.width : 0
                    height: 56
                    color: hoverArea.containsMouse ? CommonOptions.colorSurfaceDim : CommonOptions.colorSurface
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
                                    font.pixelSize: 14
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                text: "轨迹  ·  " + modelData.path.length + " 个点"
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: 11
                            }
                        }

                        // 2026-09-15: 概览按钮
                        Button {
                            contentItem: IconLabel {
                                name: "equalizer"
                                size: 18
                                tintColor: CommonOptions.colorTextOnAccent
                            }
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            Material.background: CommonOptions.colorAccent
                            Material.foreground: CommonOptions.colorTextOnAccent
                            onClicked: mapPage.openSummary("track", modelData.id, modelData.name)
                        }
                        Button {
                            contentItem: IconLabel {
                                name: "close"
                                size: 18
                                tintColor: CommonOptions.colorTextOnAccent
                            }
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            // 同路线行: 摘掉轨迹画线不是删数据 (轨迹还在本机库里, 从记录
                            //   Tab 重新勾选即恢复) → 墨底, 不用危险红.
                            Material.background: CommonOptions.colorAccent
                            Material.foreground: CommonOptions.colorTextOnAccent
                            onClicked: mapPage.removeTrack(modelData.id)
                        }
                    }

                    MouseArea { id: hoverArea2; anchors.fill: parent; hoverEnabled: true }
                }
            }

            // 无选中提示
            Text {
                visible: mapPage.routeOverlays.length === 0 &&
                         mapPage.trackOverlays.length === 0
                Layout.fillWidth: true
                text: "当前无选中项"
                color: CommonOptions.colorTextDim
                font.pixelSize: 14
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
        title: "清空已选?"
        anchors.centerIn: parent
        width: Math.min(360, mapPage.width - 2 * styles.pageMargin)
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        padding: styles.spMd

        Text {
            text: "已选 " + (mapPage.selectedRouteIds.length + mapPage.selectedTrackIds.length) +
                  " 项 (路线/轨迹), 全部清空?"
            color: CommonOptions.colorText
            font.pixelSize: styles.fsMd
            wrapMode: Text.WordWrap
        }
        footer: RowLayout {
            spacing: styles.spSm
            Item { Layout.fillWidth: true }
            OutlineButton {
                text: "留着"
                tone: CommonOptions.colorTextMuted
                onClicked: confirmClearDialog.close()
            }
            PrimaryButton {
                text: "清空"
                tone: CommonOptions.colorDanger
                textSize: styles.fsMd
                onClicked: {
                    mapPage.clearSelections()
                    confirmClearDialog.close()
                }
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

        heading: mapPage.headingDeg
        hasHeading: mapPage.hasHeading
        calibrationPct: mapPage.calibPct
        targets: mapPage.dialTargets
        zoomLevel: mapPage.mapZoomInt
        scaleText: mapPage.scaleText
        scaleBarPx: mapPage.scaleBarPx
        markCount: mapPage.speciesLocations.length
        selectedCount: mapPage.selectedRouteIds.length + mapPage.selectedTrackIds.length
        locateReady: mapPage.hasFix

        onSearchClicked: bottomSheet.openTab(3)
        onLayersClicked: baseMapMenu.popup()
        onLocateClicked: mapPage.centerOnMe()
        onZoomInClicked: mapPage.stepZoom(1)
        onZoomOutClicked: mapPage.stepZoom(-1)
        onSelectedClicked: selectedListDialog.open()
        onSelectedClearClicked: confirmClearDialog.open()
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
    Menu {
        id: baseMapMenu
        title: "选择底图"
        Repeater {
            model: mapPage._baseMaps
            delegate: MenuItem {
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
    MapBottomSheet {
        id: bottomSheet
        // 2026-09-15: Drawer 不接受 anchors (Drawer/Popup 父容器已由 edge 自动贴底),
        // 之前写 anchors.left/right/bottom 触发 "Cannot assign to non-existent property"
        x: 0
        y: parent ? parent.height - height : 0
        width: parent ? parent.width : 360

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
        onTrackAnalyzeRequested: function(trackId) { mapPage.openTrackDetail(trackId) }
        // 2026-10-09: 导入入口打通 (此前 importDialog 无任何 .open() 触发点 → 死功能)
        onTrackImportRequested: importDialog.open()
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
        mapPage.addOrToggleRoute(route)
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
            // 至少要 2 个点才能画线, 没有就只标起点
            if (coords.length === 1) {
                var colorIdx = mapPage.selectedRouteIds.length
                mapPage.routeMarkers = mapPage.routeMarkers.concat([{
                    routeId: rid,
                    coord: coords[0],
                    label: "S",
                    color: mapPage._colorForIndex(colorIdx)
                }])
            }
            console.warn("addOrToggleRoute: route " + rid + " 缺少路径点, 仅标注起点")
        } else {
            var ci = mapPage.selectedRouteIds.length
            mapPage.routeOverlays = mapPage.routeOverlays.concat([{
                id: rid,
                name: route.name || "(未命名)",
                color: mapPage._colorForIndex(ci),
                path: coords
            }])
            // 起终点 marker
            var markers = []
            markers.push({ routeId: rid, coord: coords[0], label: "S", color: mapPage._colorForIndex(ci) })
            markers.push({ routeId: rid, coord: coords[coords.length - 1], label: "E", color: mapPage._colorForIndex(ci) })
            mapPage.routeMarkers = mapPage.routeMarkers.concat(markers)

            // 2026-09-15: 中间路径点 (营地/垭口等) - 仅 waypoints 模式有, 用半透明小方块
            if (wps && wps.length > 2) {
                var wpMarkers = []
                for (var wp = 1; wp < wps.length - 1; wp++) {
                    var w = wps[wp]
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

        mapPage.selectedRouteIds = mapPage.selectedRouteIds.concat([rid])

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
            var ci = mapPage.selectedRouteIds.length
            mapPage.routeOverlays = mapPage.routeOverlays.concat([{
                id: tid,
                name: travel.name || "(自驾游)",
                color: mapPage._colorForIndex(ci),
                path: coords,
                kind: "travel"
            }])
            var markers = []
            markers.push({ routeId: tid, coord: coords[0], label: "S", color: mapPage._colorForIndex(ci) })
            markers.push({ routeId: tid, coord: coords[coords.length - 1], label: "E", color: mapPage._colorForIndex(ci) })
            mapPage.routeMarkers = mapPage.routeMarkers.concat(markers)
        } else if (coords.length === 1) {
            var ci2 = mapPage.selectedRouteIds.length
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
        if (allCoords.length === 0) return

        var minLat = allCoords[0].latitude, maxLat = allCoords[0].latitude
        var minLon = allCoords[0].longitude, maxLon = allCoords[0].longitude
        for (var j = 1; j < allCoords.length; j++) {
            var c = allCoords[j]
            if (c.latitude < minLat) minLat = c.latitude
            if (c.latitude > maxLat) maxLat = c.latitude
            if (c.longitude < minLon) minLon = c.longitude
            if (c.longitude > maxLon) maxLon = c.longitude
        }
        var cLat = (minLat + maxLat) / 2
        var cLon = (minLon + maxLon) / 2
        map.center = QtPositioning.coordinate(cLat, cLon)

        // 估算 zoom: 用 lat/lon 跨度, 经度 1° ≈ 111km * cos(lat)
        var latSpan = Math.max(maxLat - minLat, 0.005)
        var lonSpan = Math.max(maxLon - minLon, 0.005)
        var kmPerLat = 111.0
        var kmPerLon = 111.0 * Math.cos(cLat * Math.PI / 180)
        var heightKm = latSpan * kmPerLat
        var widthKm = lonSpan * kmPerLon
        var maxKm = Math.max(heightKm, widthKm, 0.5)  // 至少 0.5km
        // 经验公式: zoom ≈ 8 - log2(km)
        // 1 km → z15, 10 km → z12, 100 km → z9, 1000 km → z5
        var zoom = Math.max(4, Math.min(16, Math.round(9 - Math.log2(maxKm))))
        map.zoomLevel = zoom
        mapPage.currentZoom = zoom
    }

    function onTrackSelected(trackId, track) {
        // 2026-09-15: 轨迹联动 - 拉轨迹点, 画 polyline, 多选叠加
        mapPage.addOrToggleTrack(trackId)
    }

    function addOrToggleTrack(trackId) {
        if (!trackId) return
        if (mapPage.selectedTrackIds.indexOf(trackId) >= 0) {
            mapPage.removeTrack(trackId)
            return
        }
        var points = mapService.getTrackPoints(trackId)
        if (!points || points.length < 1) {
            console.warn("addOrToggleTrack: track " + trackId + " 无轨迹点")
            return
        }
        var coords = []
        for (var i = 0; i < points.length; i++) {
            var p = points[i]
            if (p && !isNaN(p.latitude) && !isNaN(p.longitude)) {
                coords.push(QtPositioning.coordinate(p.latitude, p.longitude))
            }
        }
        if (coords.length < 1) return

        var ci = mapPage.trackOverlays.length
        mapPage.trackOverlays = mapPage.trackOverlays.concat([{
            id: trackId,
            name: "(轨迹)",
            color: mapPage._colorForIndex(mapPage.selectedRouteIds.length + ci),
            path: coords
        }])
        mapPage.selectedTrackIds = mapPage.selectedTrackIds.concat([trackId])
        mapPage.fitBoundsToRoutes()
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
    // 现有 importGpx / importKml / importCsv 接口). 用 FileDialog 选文件,
    // onAccepted 根据扩展名分发. 入口: 底栏「导航」Tab 的「导入」按钮 (2026-10-09 打通).
    // 导入成功后 MapService emit dataChanged, NavigationTab 监听后自查刷新.
    Dialog {
        id: importDialog
        title: "导入外部轨迹"
        anchors.centerIn: parent
        width: Math.min(400, mapPage.width - 2 * styles.pageMargin)
        // 2026-10-20 #41: 取消按钮从正文里挪进 footer, 弹层底/前景显式绑 token.
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        // 上一次的结果不该在下一次打开时还挂在上面
        onAboutToShow: mapPage._importStatus = ""
        footer: RowLayout {
            spacing: styles.spSm
            Item { Layout.fillWidth: true }
            OutlineButton {
                text: "关闭"
                tone: CommonOptions.colorTextMuted
                onClicked: importDialog.close()
            }
        }

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: "支持 GPX (奥维/户外助手) / KML (Google Earth) / CSV (自建)"
                color: CommonOptions.colorTextMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            PrimaryButton {
                Layout.fillWidth: true
                // 2026-10-19: 原 "\ue2c6 选择文件…" 是图标字体混文案 → 中文缺字;
                //   且 \ue2c6 (file_download) 不在 IconLabel 实测表内, 本字体也没有
                //   "下载文件"字形, 所以只留文案.
                text: "选择文件 (GPX / KML / CSV)"
                textSize: styles.fsMd
                onClicked: importFileDialog.open()
            }

            Text {
                visible: mapPage._importStatus.length > 0
                text: mapPage._importStatus
                color: mapPage._importStatusColor
                font.pixelSize: 12
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }

    property string _importStatus: ""
    property color _importStatusColor: CommonOptions.colorTextMuted

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
            var path = url.replace(/^file:\/\//, "")
            if (path.length === 0) {
                mapPage._importStatus = "系统没回传文件地址"
                mapPage._importStatusColor = CommonOptions.colorLegendAmber
                return
            }
            var lower = path.toLowerCase()
            var r = null
            if (lower.endsWith(".gpx")) {
                r = mapService.importGpx(path)
            } else if (lower.endsWith(".kml")) {
                r = mapService.importKml(path)
            } else if (lower.endsWith(".csv")) {
                r = mapService.importCsv(path)
            } else {
                // 2026-10-19: _importStatus 由默认字体的 Text 显示, PUA 码位是方框 → 去码位留文字.
                mapPage._importStatus = "不支持的文件格式: " + path
                // 2026-10-20: colorRedBright 与 SOS 的危险红同值, 一次导入失败不配用
                //   危险色 → 常驻提示统一用 legend amber (同装备页口径).
                mapPage._importStatusColor = CommonOptions.colorLegendAmber
                return
            }
            if (r && r.ok && r.value) {
                var trackId = r.value
                // 2026-09-15: 导入成功后, 在当前地图上自动画线 + fit
                // (不再 push TrackDetailPage; 用户随时可在「已选」浮卡里点该行右侧的
                //  等号柱图标按钮打开概览面板, 详情页从那儿进)
                var r2 = mapService.getTrackById(trackId)  // 2026-10-09: 契约切 Result, 读 .value
                var trackName = (r2 && r2.ok && r2.value && r2.value.name) || "(导入轨迹)"
                mapPage._importStatus = "导入成功: " + trackName
                mapPage._importStatusColor = CommonOptions.colorSuccess
                // 2026-10-09: 删除未定义的 mapPage.refreshData() (TypeError);
                //   MapService 导入时已 emit dataChanged, NavigationTab 监听后自查 refresh.
                importDialog.close()
                mapPage.addOrToggleTrack(trackId)
            } else {
                // 2026-09-21: 失败时显示具体错误 (Result.error.message)
                var errMsg = (r && r.error && r.error.message) || "未知错误"
                mapPage._importStatus = "导入失败: " + errMsg
                mapPage._importStatusColor = CommonOptions.colorLegendAmber
            }
        }
    }
}
