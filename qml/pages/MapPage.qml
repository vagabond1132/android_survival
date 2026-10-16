/**
 * @file MapPage.qml
 * @brief 地图主页 - 2026-09-15 改版 (作为应用主页)
 *
 * 布局:
 *   - 顶部地图 (osm 瓦片, 默认前进方向朝上)
 *   - 中心: DirectionCompassOverlay (旋转指针)
 *   - 右侧浮动: MapRightButtonColumn (标注/拍照/居中/轨迹/危险标记)
 *   - 底部: MapBottomSheet (4 Tab: 记录/导航/周边/查找)
 *   - 2026-09-15: 取代 HomePage 作为 Main.qml initialItem
 */
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
    title: "户外地图"

    // 2026-09-15: 路由入口支持 - 从 RouteListPage 选路线后"在地图查看"
    // 可传 routeId 进来, MapPage 进入时自动选中该路线
    property string pendingRouteId: ""
    property string pendingTravelId: ""

    property real currentLat: 39.9087
    property real currentLon: 116.3975
    property real currentHeading: 0
    property bool hasFix: false
    // 底图索引: 0=地形 / 1=路网 / 2=卫星 (osm plugin 仅一种, 实际切换受限)
    property int currentBaseMap: 0
    // 2026-09-15: 当前缩放 (受 fit bounds 控制)
    property real currentZoom: 11

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
    // 路线配色 (按选择顺序循环)
    readonly property var _routePalette: [
        "#1976D2",  // 蓝
        "#388E3C",  // 绿
        "#D32F2F",  // 红
        "#7B1FA2",  // 紫
        "#F57C00",  // 橙
        "#0097A7",  // 青
        "#5D4037",  // 棕
        "#C2185B"   // 玫
    ]

    // 2026-09-15: 路线种类的颜色: 自驾/徒步 颜色不同, 便于视觉区分
    function _colorForIndex(idx, type) {
        var c = mapPage._routePalette[idx % mapPage._routePalette.length]
        return c
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
        // 2026-09-16: nearbyTab 在 MapBottomSheet 内部, 跨组件 id 引用不到
        // 改用 openTab(2) 触发 NearbyTab.onCompleted, 让它自己拉一次
        bottomSheet.currentTab = 2
        // 注意: currentTab 改变会触发 NearbyTab reload, 但它是懒加载, 不会立即跑
        // 改用 Qt.callLater 异步调用 openTab
        Qt.callLater(function() { bottomSheet.openTab(2) })
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

    function centerOnMe() {
        map.center = QtPositioning.coordinate(currentLat, currentLon)
        map.zoomLevel = Math.max(map.zoomLevel, 13)
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
        // 在当前位置插一个物种标注 (默认类别 photo, 物种 id 留空)
        var ok = mapService.addSpeciesLocation("", "", currentLat, currentLon, "manual")
        if (ok) {
            console.log("annotateHere: ok at", currentLat, currentLon)
        }
    }

    function onPhotoTaken(uri) {
        if (uri && uri.length > 0) {
            lastCapturedPhoto = uri
            // 提取 EXIF GPS + 加到 mapService
            var exif = mapService.extractExif(uri.replace("file://", ""))
            if (exif && exif.lat && exif.lon) {
                mapService.addSpeciesLocation("", "", exif.lat, exif.lon, "field_guide")
            } else {
                // 无 GPS, 用当前位置
                mapService.addSpeciesLocation("", "", currentLat, currentLon, "field_guide")
            }
        }
    }

    // 2026-09-15: 灰色底色, 瓦片未加载时不至于全黑
    Rectangle {
        anchors.fill: parent
        color: "#E0E0E0"
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
    //   切换时用 _applyBaseMap 造新 Plugin 再赋给 map.plugin, 只依赖
    //   osm.mapping.host 的 path 模板 (.../{z}/{x}/{y}.png). 三源见 mapPage._baseMaps.
    //   !!! 注意: 全程不可把 map.plugin 置 null. Map 初值必须是非空 Plugin,
    //   切换也必须「非空→非空」(见 Map 内注释), 否则 setPlugin 空指针崩溃.
    readonly property var _baseMaps: [
        { name: "地形",
          host: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
          copyright: "© OpenTopoMap (CC-BY-SA)" },
        { name: "路网",
          host: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          copyright: "© OpenStreetMap contributors" },
        { name: "卫星",
          // Esri World Imagery: 注意顺序是 {z}/{y}/{x} (与 OSM 的 {z}/{x}/{y} 不同),
          //   plugin 只做占位串替换, 与在模板中的位置无关.
          host: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
          copyright: "© Esri, Maxar, Earthstar Geographics" }
    ]
    // _applyBaseMap: createQmlObject 造新 Plugin, setParameter 三参数后
    //   赋给 map.plugin (赋值瞬间被读取). 不置 null (见上).
    function _applyBaseMap(idx) {
        var src = mapPage._baseMaps[idx] || mapPage._baseMaps[0]
        // 2026-10-09 修复启动崩溃: 绝不 `map.plugin = null` (会崩, 见 Map 内注释).
        //   直接构造新 Plugin 再「非空 → 非空」赋给 map.plugin, setPlugin 内部
        //   自己 disconnect 旧对象 / attach 新对象, 全程无空指针.
        var p = Qt.createQmlObject(
            'import QtLocation; Plugin { name: "osm" }', map)
        p.setParameter("osm.mapping.host", src.host)
        p.setParameter("osm.mapping.copyright", src.copyright)
        p.setParameter("osm.mapping.providersrepository.disabled", true)
        map.plugin = p                         // 赋值瞬间读取参数
        console.log("[map] tileHost=" + src.host)
        mapPage._mapErrorMsg = ""
    }
    onCurrentBaseMapChanged: mapPage._applyBaseMap(currentBaseMap)

    Map {
        id: map
        anchors.fill: parent
        // 2026-10-09 修复启动崩溃 (SIGSEGV in QDeclarativeGeoServiceProvider::
        //   isAttached, fault addr 0x20, x0=0, tombstone 见 run.txt L4134-4152):
        //   Qt6 QDeclarativeGeoMap::setPlugin() 在 p==null 时不解引用 m_plugin,
        //   而当 p==null && m_plugin==null 时会在「disconnect 旧对象」处对空
        //   m_plugin 调 isAttached() → 空指针崩溃. 所以 plugin 初值绝不可为 null,
        //   必须挂一个非空 Plugin (此前写 plugin: null + onCompleted 里
        //   _applyBaseMap 造新对象, 但 _applyBaseMap 内部先置 null 的两次赋值
        //   会在「非空→null」和「null→非空」两个方向都踩中该崩溃路径).
        //   现在: 初值给默认源(路网 OSM)的内联 Plugin; 切底图走 _applyBaseMap,
        //   全程保持非空→非空, 由 setPlugin 自己 disconnect/attach.
        Plugin {
            id: defaultPlugin
            name: "osm"
            PluginParameter {
                name: "osm.mapping.host"
                value: mapPage._baseMaps[1].host
            }
            PluginParameter {
                name: "osm.mapping.copyright"
                value: mapPage._baseMaps[1].copyright
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
        // 2026-10-09: 删除原「onCompleted 首次 _applyBaseMap」— plugin 初值已是
        //   有效源, 无需再重建 (重建反而多一次 plugin swap). 切换仍走
        //   onCurrentBaseMapChanged → _applyBaseMap.
        Component.onCompleted: {
            var _names = []
            for (var _i = 0; _i < supportedMapTypes.length; _i++) {
                _names.push(supportedMapTypes[_i].name)
            }
            var _activeName = activeMapType ? activeMapType.name : "null"
            // 2026-09-30 诊断: 把 actual host 打出来 (现 host 由 _applyBaseMap 写入).
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
            // 2026-09-28: 同时写入 _mapErrorMsg → 横幅显示 (横幅已改为不自动消失).
            //   即使无 error 信号 (静默白底), 截图上也能看到诊断串.
            mapPage._mapErrorMsg = _diag
        }
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
                // 2026-09-28: 错误信息覆盖诊断串 (优先级更高), 且不自动消失.
                mapPage._mapErrorMsg = _errDiag
            }
        }
        center: QtPositioning.coordinate(mapPage.currentLat, mapPage.currentLon)
        zoomLevel: mapPage.currentZoom
        minimumZoomLevel: 3
        maximumZoomLevel: 18
        bearing: mapPage.hasFix ? mapPage.currentHeading : 0

        // 2026-09-21: 地图错误提示条 (顶部, 红色背景 + 错误文本).
        // 之前白底时用户看不到任何反馈, 不知道是网络问题还是配置问题.
        // 2026-09-28: 诊断模式 — 不再 4s 自动消失 (用户授权 "错误横幅改成
        //   不自动消失"), 否则截图时来不及捕获. 高度随文本自适应 (诊断串
        //   较长), 点一下横幅可手动关闭.
        Rectangle {
            id: mapErrorBanner
            // 2026-10-08: 横幅从顶部 (topMargin 8) 往下移到地图底部上方.
            //   放顶部会盖住罗盘/地图上部核心区, 且贴系统状态栏; 下移后能完整
            //   展示 203 字符诊断串 (见 _mapErrorMsg), 又只占边缘.
            //   bottomMargin 取 96 (> MapBottomSheet 的 dragMargin 80), 避免
            //   横幅 MouseArea 压住底部 BottomSheet 的上拉手势区.
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottomMargin: 96
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            radius: 6
            color: "#D32F2F"
            opacity: 0
            visible: opacity > 0
            height: errText.implicitHeight + 16
            z: 999
            Behavior on opacity { NumberAnimation { duration: 250 } }

            MouseArea {
                anchors.fill: parent
                // 2026-09-28: 手动关闭 (替代原 4s 自动消失)
                onClicked: mapErrorBanner.opacity = 0
            }

            Text {
                id: errText
                anchors.fill: parent
                anchors.margins: 6
                text: "\ue002  " + mapPage._mapErrorMsg + "\n(点击关闭)"
                font.family: "Material Icons"
                color: "white"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
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
                // 2026-09-28: 去掉 mapErrorTimer.start() — 横幅不自动消失.
                console.log("[map] banner update len=" + mapPage._mapErrorMsg.length)
                mapErrorBanner.opacity = mapPage._mapErrorMsg.length > 0 ? 1 : 0
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

        // 中心罗盘叠加
        DirectionCompassOverlay {
            heading: mapPage.currentHeading
            hasFix: mapPage.hasFix
        }

        // 当前点
        MapQuickItem {
            coordinate: QtPositioning.coordinate(mapPage.currentLat, mapPage.currentLon)
            sourceItem: Rectangle {
                width: 14
                height: 14
                radius: 7
                color: "#1976D2"
                border.color: "white"
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
                        if (_lvl < 0) return "#607D8B"
                        if (_lvl >= 4) return "#D32F2F"
                        if (_lvl >= 3) return "#F57C00"
                        if (_lvl >= 1) return "#FBC02D"
                        return "#388E3C"
                    }
                    border.color: "white"
                    border.width: 2
                    Text {
                        anchors.centerIn: parent
                        text: {
                            var lvl = parent._lvl
                            if (lvl < 0) return "?"
                            if (lvl >= 4) return "!"
                            if (lvl >= 1) return "\ue002"
                            return "\ue0c8"
                        }
                        font.family: "Material Icons"
                        color: "white"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            mapPage.markerDetailKind = "species"
                            mapPage.markerDetailTitle = "\ue0c8 物种标注"
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
                    border.color: "white"; border.width: 2
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: "white"
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
                    color: "#D32F2F"
                    border.color: "white"; border.width: 1.5
                    Text {
                        anchors.centerIn: parent
                        text: "!"
                        color: "white"
                        font.pixelSize: 10
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            mapPage.markerDetailKind = "danger"
                            mapPage.markerDetailTitle = "\ue002 " + (modelData.name || "危险点")
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
                    color: "#FFFFFF"
                    border.color: "#37474F"
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
        TapHandler {
            id: longPressHandler
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onLongPressed: function(eventPoint, button) {
                // 把屏幕坐标转成经纬度
                var coord = map.toCoordinate(eventPoint.position)
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
        width: Math.min(parent.width * 0.92, 440)
        standardButtons: Dialog.Ok | Dialog.Cancel

        // 类别 - 用 SpeciesService.Category 枚举 (0=Snake,1=Mushroom,2=Insect,3=Plant,4=Animal)
        property int selectedCategory: 3   // 默认 Plant
        property var speciesList: []
        property string selectedSpeciesId: ""
        property string selectedSpeciesName: ""
        property int computedDangerLevel: 0

        onAboutToShow: {
            noteField.text = ""
            // 默认 Plant 类
            selectedCategory = 3
            refreshSpeciesList()
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

            Text {
                text: "\ue0c8 " + (mapPage.pendingAnnotateCoord ?
                      mapPage.pendingAnnotateCoord.latitude.toFixed(6) + ", " +
                      mapPage.pendingAnnotateCoord.longitude.toFixed(6) : "")
                font.family: "Material Icons"
                color: CommonOptions.colorWarn
                font.pixelSize: 12
                font.bold: true
            }

            // 类别
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "类别:"; color: CommonOptions.colorText; font.pixelSize: 12; Layout.preferredWidth: 50 }
                ComboBox {
                    id: catCombo
                    Layout.fillWidth: true
                    model: ["\ue92b 蛇类", "\ue239 蘑菇", "\ue1b9 昆虫", "\ue406 植物", "\ue91a 动物"]
                    // 2026-09-30: 同 FieldGuidePage - model 项是 PUA 码位, 必须显式
                    //   指定 Material Icons 字体, 否则真机默认字体无字形 → 方框.
                    font.family: "Material Icons"
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
                color: addAnnotateDialog.computedDangerLevel >= 4 ? "#D32F2F" :
                       addAnnotateDialog.computedDangerLevel >= 3 ? "#F57C00" :
                       addAnnotateDialog.computedDangerLevel >= 1 ? "#FBC02D" : "#388E3C"
                radius: 4
                Text {
                    anchors.centerIn: parent
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                    text: {
                        var lvl = addAnnotateDialog.computedDangerLevel
                        var label = ""
                        if (lvl >= 4) label = "\ue002 高危"
                        else if (lvl >= 3) label = "中危"
                        else if (lvl >= 1) label = "低危"
                        else label = "安全"
                        return label + " (Lv" + lvl + ")" +
                               (addAnnotateDialog.selectedSpeciesName ?
                                "  -  " + addAnnotateDialog.selectedSpeciesName : "")
                    }
                }
            }
        }

        onAccepted: {
            if (mapPage.pendingAnnotateCoord) {
                var c = mapPage.pendingAnnotateCoord
                // 2026-09-15: 完整 7 参数
                // speciesId + speciesName 来自 selection, category 存类别名
                var catName = ["snake", "mushroom", "insect", "plant", "animal"][addAnnotateDialog.selectedCategory] || "manual"
                var ok = mapService.addSpeciesLocation(
                    addAnnotateDialog.selectedSpeciesId,
                    addAnnotateDialog.selectedSpeciesName,
                    catName,
                    c.latitude, c.longitude, 0,
                    noteField.text)
                if (ok) {
                    noteField.text = ""
                    addAnnotateDialog.selectedSpeciesId = ""
                    addAnnotateDialog.selectedSpeciesName = ""
                }
            }
        }
    }

    // 2026-09-15: marker 点击详情对话框 (复用, 根据 markerDetailKind 切换内容)
    Dialog {
        id: markerDetailDialog
        title: mapPage.markerDetailTitle
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, 420)
        standardButtons: Dialog.Close

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

            // 危险点: 显示应对措施
            Text {
                visible: mapPage.markerDetailKind === "danger"
                text: "应对: 携带蛇毒吸附器, 高帮鞋, 注意落石"
                color: CommonOptions.colorWarn
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
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

                Button {
                    text: "查看路线详情"
                    Layout.fillWidth: true
                    Material.background: CommonOptions.colorAccent
                    Material.foreground: "white"
                    enabled: !!mapPage.markerDetailRouteId
                    onClicked: {
                        if (mapPage.markerDetailRouteId) {
                            mapPage.ApplicationWindow.window.navBus.navigateTo(
                                "RouteDetailPage", { routeId: mapPage.markerDetailRouteId })
                        }
                    }
                }
                Button {
                    text: "导航到此"
                    Layout.fillWidth: true
                    Material.background: CommonOptions.colorSuccess
                    Material.foreground: "white"
                    enabled: mapPage.markerDetailCoord !== null
                    onClicked: {
                        if (mapPage.markerDetailCoord) {
                            var c = mapPage.markerDetailCoord
                            Qt.openUrlExternally("geo:" + c.latitude + "," + c.longitude +
                                "?q=" + encodeURIComponent(mapPage.markerDetailTitle || "目标"))
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

                Button {
                    text: "导航到此"
                    Layout.fillWidth: true
                    Material.background: CommonOptions.colorSuccess
                    Material.foreground: "white"
                    onClicked: {
                        if (mapPage.markerDetailCoord) {
                            var c = mapPage.markerDetailCoord
                            Qt.openUrlExternally("geo:" + c.latitude + "," + c.longitude +
                                "?q=物种标注")
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
        width: Math.min(parent.width * 0.95, 460)
        height: Math.min(parent.height * 0.92, 760)
        modal: true

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

        standardButtons: Dialog.Close
    }

    // 2026-09-15: 附近信息对话框 - 中心点周边 5km 内的 路线 + 物种 + 危险物种
    Dialog {
        id: nearbyInfoDialog
        title: "附近信息 (中心点 ±5km)"
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, 420)
        height: Math.min(parent.height * 0.8, 580)
        modal: true

        property real centerLat: 0
        property real centerLon: 0

        // 实时拉数据 (打开时计算)
        property var nearbyRoutes: []
        property var nearbySpecies: []
        property var nearbyDangers: []

        onAboutToShow: {
            // 拉附近路线 (5km)
            try {
                nearbyRoutes = routeService.getNearby(centerLat, centerLon, 5.0)
            } catch (e) {
                nearbyRoutes = []
                toast.warn("加载附近路线失败: " + e)  // 2026-09-20
            }

            // 2026-09-15: 附近物种位置 (5km 矩形) - 用 getSpeciesLocationsInBounds
            // 5km 跨度数: 1° lat ≈ 111km, 1° lon ≈ 111 * cos(lat) km
            var deltaLat = 5.0 / 111.0
            var deltaLon = 5.0 / (111.0 * Math.max(0.1, Math.cos(centerLat * 3.14159 / 180)))
            try {
                nearbySpecies = mapService.getSpeciesLocationsInBounds(
                    centerLat - deltaLat, centerLat + deltaLat,
                    centerLon - deltaLon, centerLon + deltaLon)
            } catch (e) {
                nearbySpecies = []
                toast.warn("加载附近物种失败: " + e)  // 2026-09-20
            }

            // 2026-09-15: 附近危险物种 - species_locations 不存 species id/dangerLevel,
            // 没法精确匹配. 用 note 关键词 (毒/危险/攻击/蛇/蜂/蝎) 判断
            try {
                var dangerKeywords = ["毒", "危险", "攻击", "蛇", "蜂", "蝎",
                                       "狼蛛", "蜈蚣", "蚂蚁", "黄蜂", "水母"]
                var dm = []
                for (var si = 0; si < nearbySpecies.length; si++) {
                    var s = nearbySpecies[si]
                    var note = (s.note || "") + " " + (s.speciesName || "") +
                               " " + (s.speciesCategory || "")
                    var isDanger = false
                    for (var ki = 0; ki < dangerKeywords.length; ki++) {
                        if (note.indexOf(dangerKeywords[ki]) >= 0) {
                            isDanger = true
                            break
                        }
                    }
                    if (isDanger) dm.push(s)
                }
                nearbyDangers = dm
            } catch (e) {
                nearbyDangers = []
                toast.warn("过滤附近危险物种失败: " + e)  // 2026-09-20
            }
        }

        contentItem: ColumnLayout {
            spacing: 8

            // 中心点信息
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                color: "#1A237E"
                radius: 4
                Text {
                    anchors.centerIn: parent
                    text: "\ue0c8 " + nearbyInfoDialog.centerLat.toFixed(5) + ", " +
                          nearbyInfoDialog.centerLon.toFixed(5)
                    font.family: "Material Icons"
                    color: "white"
                    font.pixelSize: 12
                }
            }

            // 附近路线
            Text {
                text: "\ue536 附近路线 (" + nearbyInfoDialog.nearbyRoutes.length + ")"  // Material Icons: hiking
                font.family: "Material Icons"
                color: "white"
                font.pixelSize: 14
                font.bold: true
                Layout.topMargin: 6
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(nearbyInfoDialog.nearbyRoutes.length * 50, 180)
                spacing: 4
                clip: true
                model: nearbyInfoDialog.nearbyRoutes
                delegate: Rectangle {
                    width: ListView.view ? ListView.view.width : 0
                    height: 46
                    color: mArea.containsMouse ? "#37474F" : "#263238"
                    radius: 4
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: modelData.name || "(未命名)"
                                color: "white"
                                font.pixelSize: 12
                                font.bold: true
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: (modelData.distance || 0).toFixed(1) + " km  ·  " +
                                      (modelData.difficulty || 1) + "★"
                                color: "#B0BEC5"
                                font.pixelSize: 10
                            }
                        }
                        Button {
                            text: "查看"
                            Layout.preferredWidth: 50
                            Layout.preferredHeight: 32
                            Material.background: "#1976D2"
                            Material.foreground: "white"
                            font.pixelSize: 10
                            onClicked: {
                                nearbyInfoDialog.close()
                                mapPage.addOrToggleRoute(modelData)
                            }
                        }
                    }
                    MouseArea { id: mArea; anchors.fill: parent; hoverEnabled: true }
                }
            }
            Text {
                visible: nearbyInfoDialog.nearbyRoutes.length === 0
                text: "(无附近路线)"
                color: "#78909C"
                font.pixelSize: 11
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            // 附近物种
            Text {
                text: "\ue0c8 物种标注 (" + nearbyInfoDialog.nearbySpecies.length + ")"  // Material Icons: place
                font.family: "Material Icons"
                color: "white"
                font.pixelSize: 14
                font.bold: true
                Layout.topMargin: 6
            }
            Text {
                visible: nearbyInfoDialog.nearbySpecies.length === 0
                text: "(5km 内无物种标注)"
                color: "#78909C"
                font.pixelSize: 11
                Layout.fillWidth: true
            }
            ListView {
                visible: nearbyInfoDialog.nearbySpecies.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(nearbyInfoDialog.nearbySpecies.length * 36, 100)
                spacing: 2
                clip: true
                model: nearbyInfoDialog.nearbySpecies
                delegate: Text {
                    width: ListView.view ? ListView.view.width : 0
                    text: "\ue0c8 " + (modelData.note || modelData.speciesCategory || "标注") +
                          "  ·  " + modelData.lat.toFixed(3) + ", " + modelData.lon.toFixed(3)
                    font.family: "Material Icons"
                    color: "#FFCC80"
                    font.pixelSize: 11
                    leftPadding: 6
                    topPadding: 4
                    bottomPadding: 4
                }
            }

            // 2026-09-15: 附近危险物种
            Text {
                text: "\ue002 危险物种 (" + nearbyInfoDialog.nearbyDangers.length + ")"  // Material Icons: warning
                font.family: "Material Icons"
                color: "#FF8A65"
                font.pixelSize: 14
                font.bold: true
                Layout.topMargin: 6
            }
            Text {
                visible: nearbyInfoDialog.nearbyDangers.length === 0
                text: "(5km 内无危险物种标注)"
                color: "#78909C"
                font.pixelSize: 11
                Layout.fillWidth: true
            }
            ListView {
                visible: nearbyInfoDialog.nearbyDangers.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(nearbyInfoDialog.nearbyDangers.length * 36, 80)
                spacing: 2
                clip: true
                model: nearbyInfoDialog.nearbyDangers
                delegate: Text {
                    width: ListView.view ? ListView.view.width : 0
                    text: "\ue002 " + (modelData.note || modelData.speciesCategory || "危险") +
                          "  ·  " + modelData.lat.toFixed(3) + ", " + modelData.lon.toFixed(3)
                    font.family: "Material Icons"
                    color: "#FF8A65"
                    font.pixelSize: 11
                    leftPadding: 6
                    topPadding: 4
                    bottomPadding: 4
                }
            }

            Item { Layout.fillHeight: true }

            Button {
                text: "关闭"
                Layout.fillWidth: true
                onClicked: nearbyInfoDialog.close()
            }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56
        color: "#CC1A237E"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            // 2026-09-15: SOS 紧凑按钮 (40x40, 适合 56 顶栏高度)
            // 长按 3 秒触发紧急流程, 跳到 SOSPage
            Rectangle {
                id: sosBtn
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: sosArea.pressed ? "#B71C1C" : "#D32F2F"
                border.color: "white"
                border.width: 1.5

                property int pressDuration: 0

                Behavior on color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: sosBtn.pressDuration > 0
                          ? (sosBtn.pressDuration + "s")
                          : "🆘"
                    color: "white"
                    font.pixelSize: sosBtn.pressDuration > 0 ? 14 : 18
                    font.bold: true
                }

                Timer {
                    id: sosPressTimer
                    interval: 1000
                    repeat: true
                    onTriggered: {
                        sosBtn.pressDuration = Math.min(3, sosBtn.pressDuration + 1)
                        if (sosBtn.pressDuration >= 3) {
                            sosBtn.pressDuration = 0
                            sosPressTimer.stop()
                            mapPage.ApplicationWindow.window.navBus.navigateTo("SOSPage", {})
                        }
                    }
                }

                MouseArea {
                    id: sosArea
                    anchors.fill: parent
                    onPressed: {
                        sosBtn.pressDuration = 0
                        sosPressTimer.start()
                    }
                    onReleased: {
                        sosPressTimer.stop()
                        if (sosBtn.pressDuration < 3) {
                            sosBtn.pressDuration = 0
                        }
                    }
                }
            }

            // 2026-09-15: 去掉 "🗺️ " 前缀, 避免 emoji 占位让文字被裁
            Text {
                text: "户外地图"
                color: "white"
                font.pixelSize: 18
                font.bold: true
                Layout.fillWidth: true
            }

            // 2026-09-15: 危险标记统计 (替代 HomePage 的 StatCard)
            // 用 Material Icons 字符, 不用 emoji, 风格统一
            Row {
                spacing: 4
                Text {
                    text: "\ue002"  // Material Icons: warning
                    color: "#FFB74D"
                    font.family: "Material Icons"
                    font.pixelSize: 18
                }
                Text {
                    text: mapPage.speciesLocations.length
                    color: "#FFB74D"
                    font.pixelSize: 14
                    font.bold: true
                }
            }

            // 2026-09-15: 附近信息按钮 - 弹中心点周边 5km 信息
            Rectangle {
                Layout.preferredHeight: 32
                Layout.preferredWidth: 32
                radius: 16
                color: nearArea.containsMouse ? "#37474F" : "#455A64"
                border.color: "white"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "\ue1cd"  // nearby (location_searching)
                    color: "white"
                    font.family: "Material Icons"
                    font.pixelSize: 18
                }
                MouseArea {
                    id: nearArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        // 重新拉当前中心点的附近信息
                        var c = map.center
                        nearbyInfoDialog.centerLat = c.latitude
                        nearbyInfoDialog.centerLon = c.longitude
                        nearbyInfoDialog.open()
                    }
                }
            }

            // 2026-09-15: 多选已选项提示 + 入口
            // 行为:
            //   - 单击: 打开 selectedListDialog (可单项删除)
            //   - 双击: 全部清空
            Rectangle {
                visible: mapPage.selectedRouteIds.length + mapPage.selectedTrackIds.length > 0
                Layout.preferredHeight: 32
                Layout.preferredWidth: chipRow.implicitWidth + 20
                radius: 16
                color: chipArea.containsMouse ? "#37474F" : "#455A64"
                border.color: "#90CAF9"
                border.width: 1

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: "已选 " + (mapPage.selectedRouteIds.length + mapPage.selectedTrackIds.length)
                        color: "white"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    Text {
                        text: "\ue5d2"  // expand_more
                        color: "#FFCDD2"
                        font.family: "Material Icons"
                        font.pixelSize: 14
                    }
                }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: selectedListDialog.open()
                    onDoubleClicked: {
                        if (mapPage.selectedRouteIds.length + mapPage.selectedTrackIds.length > 0) {
                            confirmClearDialog.open()
                        }
                    }
                }
            }
        }
    }

    // 2026-09-15: 已选列表 - 单击 chip 弹出, 列出全部选中 + 单项删除
    Dialog {
        id: selectedListDialog
        title: "已选 " + (mapPage.selectedRouteIds.length + mapPage.selectedTrackIds.length) + " 项"
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, 420)
        height: Math.min(parent.height * 0.7, 520)

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
                    color: hoverArea.containsMouse ? "#37474F" : "#263238"
                    radius: 4

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Rectangle {
                            width: 10; Layout.fillHeight: true
                            color: modelData.color
                            radius: 2
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            // 2026-09-19: \ue52f (bicycle) 改成 \ue536 (hiking) - 徒步路线图标
                            Text {
                            text: (modelData.kind === "travel" ? "\ue531 " : "\ue536 ") +
                                  (modelData.name || "(未命名)")
                            font.family: "Material Icons"
                            color: "white"
                            font.pixelSize: 14
                            font.bold: true
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: (modelData.kind === "travel" ? "自驾游" : "徒步路线") +
                                      "  ·  " + modelData.path.length + " 个点"
                                color: "#B0BEC5"
                                font.pixelSize: 11
                            }
                        }

                        // 2026-09-15: 概览按钮 - 弹出 RouteSummaryPanel
                        Button {
                            text: "\ue01d"  // Material Icons: equalizer
                            font.family: "Material Icons"
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            Material.background: "#1976D2"
                            Material.foreground: "white"
                            onClicked: {
                                mapPage.openSummary(modelData.kind === "travel" ? "travel" : "route",
                                                     modelData.id, modelData.name)
                            }
                        }
                        Button {
                            text: "\ue5cd"
                            font.family: "Material Icons"
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            Material.background: "#D32F2F"
                            Material.foreground: "white"
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
                    color: hoverArea.containsMouse ? "#37474F" : "#263238"
                    radius: 4

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Rectangle {
                            width: 10; Layout.fillHeight: true
                            color: modelData.color
                            radius: 2
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "\ue922 " + (modelData.name || "(轨迹)")  // Material Icons: route
                                font.family: "Material Icons"
                                color: "white"
                                font.pixelSize: 14
                                font.bold: true
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: "轨迹  ·  " + modelData.path.length + " 个点"
                                color: "#B0BEC5"
                                font.pixelSize: 11
                            }
                        }

                        // 2026-09-15: 概览按钮
                        Button {
                            text: "\ue01d"  // Material Icons: equalizer
                            font.family: "Material Icons"
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            Material.background: "#1976D2"
                            Material.foreground: "white"
                            onClicked: mapPage.openSummary("track", modelData.id, modelData.name)
                        }
                        Button {
                            text: "\ue5cd"
                            font.family: "Material Icons"
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            Material.background: "#D32F2F"
                            Material.foreground: "white"
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
                color: "#90A4AE"
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                topPadding: 30
                bottomPadding: 30
            }

            Item { Layout.fillHeight: true }  // 占位

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    text: "全部清空"
                    Layout.fillWidth: true
                    Material.background: "#D32F2F"
                    Material.foreground: "white"
                    onClicked: {
                        mapPage.clearSelections()
                        selectedListDialog.close()
                    }
                }
                Button {
                    text: "关闭"
                    Layout.fillWidth: true
                    onClicked: selectedListDialog.close()
                }
            }
        }
    }

    // 2026-09-15: 弹窗: 多个选中时, 点 chip 弹出确认
    Dialog {
        id: confirmClearDialog
        title: "清空已选?"
        anchors.centerIn: parent
        standardButtons: Dialog.Yes | Dialog.No
        Text {
            text: "已选 " + (mapPage.selectedRouteIds.length + mapPage.selectedTrackIds.length) +
                  " 项 (路线/轨迹), 全部清空?"
            color: "white"
            wrapMode: Text.WordWrap
        }
        onAccepted: mapPage.clearSelections()
    }

    // 右侧浮动按钮列
    MapRightButtonColumn {
        // 2026-09-19: 改回 onXxxClicked: (handler 形式), 不用 function onXxxClicked(){}
        // (后者在直接子组件初始化块里不被识别为 signal handler, 因为不是 Connection 元素)
        onAnnotateClicked: mapPage.annotateHere()
        onCaptureClicked: {
            // 2026-09-17: 去掉 typeof 包装 - QML context property 用 typeof 会
            // 抛 ReferenceError 被吞, 永远 false, 导致拍照按钮"无反应"
            if (androidPlatform && androidPlatform.requestTakePhoto) {
                androidPlatform.requestTakePhoto()
            } else {
                console.log("takePhoto: androidPlatform not registered (desktop debug)")
            }
        }
        onCenterClicked: mapPage.centerOnMe()
        onTrackSheetClicked: {
            bottomSheet.currentTab = 0
            bottomSheet.open()
        }
        onDangerMarkClicked: {
            bottomSheet.currentTab = 2
            bottomSheet.open()
        }
        // 2026-10-09: 底图切换入口 (第 6 按钮) → 弹 baseMapMenu
        onBaseMapClicked: baseMapMenu.popup()
    }

    // 2026-10-09: 底图切换菜单 (地形/路网/卫星). 选中项打勾.
    //   触发 mapPage.currentBaseMap = idx → onCurrentBaseMapChanged → _applyBaseMap 重建 plugin.
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
                    mapPage.currentBaseMap = index
                }
            }
        }
    }

    // 2026-09-16: 缩放按钮 (右下角, 用户常需要 + / - 控制比例)
    Item {
        id: zoomControls
        anchors.right: parent ? parent.right : undefined
        anchors.bottom: parent ? parent.bottom : undefined
        anchors.bottomMargin: 100  // 在 BottomSheet 之上
        anchors.rightMargin: 12
        z: 1000
        width: 40
        height: 96

        Column {
            anchors.fill: parent
            spacing: 4

            // + 放大
            Rectangle {
                width: 40; height: 46
                radius: 6
                color: zoomInArea.pressed ? "#37474F" : "#455A64"
                border.color: "white"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: "white"
                    font.pixelSize: 26
                    font.bold: true
                }
                TapHandler {
                    id: zoomInArea
                    onTapped: {
                        if (map.zoomLevel < map.maximumZoomLevel) {
                            map.zoomLevel = map.zoomLevel + 1
                            mapPage.currentZoom = map.zoomLevel
                        }
                    }
                }
                ToolTip.visible: zoomInArea.pressed
                ToolTip.delay: 500
                ToolTip.text: "放大"
            }

            // − 缩小
            Rectangle {
                width: 40; height: 46
                radius: 6
                color: zoomOutArea.pressed ? "#37474F" : "#455A64"
                border.color: "white"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: "white"
                    font.pixelSize: 26
                    font.bold: true
                }
                TapHandler {
                    id: zoomOutArea
                    onTapped: {
                        if (map.zoomLevel > map.minimumZoomLevel) {
                            map.zoomLevel = map.zoomLevel - 1
                            mapPage.currentZoom = map.zoomLevel
                        }
                    }
                }
                ToolTip.visible: zoomOutArea.pressed
                ToolTip.delay: 500
                ToolTip.text: "缩小"
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

        // 2026-09-19: 用 QML6 信号 handler 形式 (onXxx: ...) 而不是
        // function onXxx(args){}, 后者在子组件实例化块里不被识别为 signal handler
        // (只有 Connections 元素才识别 function onXxx), 之前的注释搞反了
        onCaptureRequested: mapPage.onCaptureRequested()
        onRouteSelected: function(routeId, route) { mapPage.onRouteSelected(routeId, route) }
        onTrackSelected: function(trackId, track) { mapPage.onTrackSelected(trackId, track) }
        onNearbyRefreshRequested: mapPage.refreshNearby()
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
            color: mapPage._routePalette[(mapPage.selectedRouteIds.length + ci) % mapPage._routePalette.length],
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

    function refreshNearby() {
        // 实际刷新由 MapBottomSheet 内的 NearbyTab.refresh 完成 (持有 currentLat/Lon)
        // 此处为透传钩子, 保留扩展位
    }

    // 2026-09-11: 线路支持外部数据格式导入 (GPX/KML/CSV 三种, 复用 mapService
    // 现有 importGpx / importKml / importCsv 接口). 用 FileDialog 选文件,
    // onAccepted 根据扩展名分发. 入口: 底栏「导航」Tab 的「导入」按钮 (2026-10-09 打通).
    // 导入成功后 MapService emit dataChanged, NavigationTab 监听后自查刷新.
    Dialog {
        id: importDialog
        title: "导入外部轨迹"
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, 400)

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: "支持 GPX (奥维/户外助手) / KML (Google Earth) / CSV (自建)"
                color: "#B0BEC5"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Button {
                Layout.fillWidth: true
                text: "\ue2c6 选择文件 (GPX / KML / CSV)"  // Material Icons: file_download
                font.family: "Material Icons"
                Material.background: "#1976D2"
                onClicked: importFileDialog.open()
            }

            // 2026-10-09: 补取消/关闭路径 (此前只能靠选完文件 importDialog.close())
            Button {
                Layout.fillWidth: true
                text: "取消"
                Material.background: "#455A64"
                onClicked: importDialog.close()
            }

            Text {
                text: mapPage._importStatus
                color: mapPage._importStatusColor
                font.pixelSize: 12
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }

    property string _importStatus: ""
    property string _importStatusColor: "#B0BEC5"

    FileDialog {
        id: importFileDialog
        title: "选择轨迹文件"
        nameFilters: ["轨迹文件 (*.gpx *.kml *.csv)", "GPX (*.gpx)", "KML (*.kml)", "CSV (*.csv)"]
        onAccepted: {
            // 2026-09-21: Phase 5 - importXxx 返回 Result {ok, value=trackId, error}.
            var path = selectedFile.toString().replace("file://", "")
            var lower = path.toLowerCase()
            var r = null
            if (lower.endsWith(".gpx")) {
                r = mapService.importGpx(path)
            } else if (lower.endsWith(".kml")) {
                r = mapService.importKml(path)
            } else if (lower.endsWith(".csv")) {
                r = mapService.importCsv(path)
            } else {
                mapPage._importStatus = "\ue5cd 不支持的文件格式: " + path  // Material Icons: close
                mapPage._importStatusColor = "#F44336"
                return
            }
            if (r && r.ok && r.value) {
                var trackId = r.value
                // 2026-09-15: 导入成功后, 在当前地图上自动画线 + fit
                // (不再 push TrackDetailPage, 用户随时可点 chip 列表里的 📊 看详情)
                var r2 = mapService.getTrackById(trackId)  // 2026-10-09: 契约切 Result, 读 .value
                var trackName = (r2 && r2.ok && r2.value && r2.value.name) || "(导入轨迹)"
                mapPage._importStatus = "\ue5ca 导入成功: " + trackName
                mapPage._importStatusColor = "#4CAF50"
                // 2026-10-09: 删除未定义的 mapPage.refreshData() (TypeError);
                //   MapService 导入时已 emit dataChanged, NavigationTab 监听后自查 refresh.
                importDialog.close()
                mapPage.addOrToggleTrack(trackId)
            } else {
                // 2026-09-21: 失败时显示具体错误 (Result.error.message)
                var errMsg = (r && r.error && r.error.message) || "未知错误"
                mapPage._importStatus = "\ue5cd 导入失败: " + errMsg  // Material Icons: close
                mapPage._importStatusColor = "#F44336"
            }
        }
    }
}
