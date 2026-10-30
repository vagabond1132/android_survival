/**
 * @file FieldGuideDetailPage.qml
 * @brief 物种详情 (2026-10-20 丁骨架 ③: 图版头 + 方位条 + 速览网格 + 地图记录)
 *
 * 版式逐块对应已评审的 mock (review-ding-v8.html 「丁 ③」), 每块解决一件事:
 *   图版头    150px 沉底图版区 + 左上档位 chip + 右上收藏/返回方角 + 底部 编号/名称/学名.
 *             中间那块色是 entity.representative_color (数据里 659 条全有, HSV),
 *             不是装饰 —— 它替掉按危险色渐变的 Hero: 渐变大色块在强光下最糊,
 *             而"档位"用一枚小 chip 就够.
 *   方位条    这个物种在你哪个方位、多远 (BearingBar). 没有标注位置就没有这一条.
 *   速览网格  季节/生境/海拔/分布, 汉字键走默认字体, 值里的数字也一起默认字体.
 *   记录卡    你自己在这张地图上标过的点 (mapService 的 species_*.json).
 *
 * 合并 (2026-10-20 #60): SpeciesDetailPage (danger_species.json, 33 条) 不再单独一页.
 *   本页多一个 speciesId 入口: 先按 id 前缀定界门、去四本图鉴里取完整数据 (能取到就
 *   连带图册/标注/收藏一起有), 取不到才回 danger_species 库. 全站只剩一种"物种详情"
 *   版式 —— ①营地 / ②图鉴 / 路线详情 / 危险物种 / 全局搜索 推进来的是同一个页面.
 *   数据源由入口决定 (preferDanger): 33 条里有若干条 (plant_gelsemium 等) 同名 id 也在
 *   图鉴里, 两套字段集不一样, 逐字段合并会让同一物种在不同入口长得不一样, 所以整条替换.
 *
 * 五条不能破的规则 (改这个文件前先读):
 *   ① 不编读数. 物种数据里没有经纬度 (见 FieldGuideIndex::toMap), 方位/距离只能来自
 *      用户自己的标注; 没标注或没定位 → 整条方位带不出现, 而不是画个 0° 指北.
 *   ② 记录位置必须用真实定位. 2026-10-20 之前这里写死北京 `_lastLat: 39.9087 /
 *      _lastLon: 116.3975` 兜底, 用户在野外点"记录位置"会把物种记到首都 ——
 *      现在没定位就拒绝写库. 野外 App 里错的坐标比没有坐标更危险.
 *   ③ C++ 侧写操作返回的是 Result 信封 {ok, value} / {ok:false, error}, 不是 bool.
 *      旧代码 `var ok = svc.recordLocation(...)` 判的是对象真假 → 恒为真,
 *      失败也提示"已记录". 一律走 detailPage._ok(res).
 *   ④ 汉字键不许绑 monoFont (本字体无 CJK 字形, 真机方框), 也不许加 letterSpacing.
 *      见 [[qml-monofont-no-cjk]].
 *   ⑤ 标注只写一个库. "记录位置"走 mapService.addSpeciesLocation, 不走
 *      plantService.recordLocation (那是 *_locations 表) —— ①营地/②图鉴/④地图读的都是
 *      前者, 写后者等于标了一个谁也看不见的点, 方位条也就永远是空的.
 *
 * 2026-10-19 那次改版的两条仍然有效: 卡片一律用 Card (高度由内容撑开, 长中文描述
 * 不会被裁); 所有上下文服务 (plantService/animalService/insectService/mushroomService/
 * speciesService/imageFetcher/fieldGuideHistory/mapService/emergencyService) 在
 * teardown 期间可能为 null, 全部加守卫; [gp ...] 诊断日志一条没删
 * (是 2026-09-30 排查图册链路刻意埋的).
 */

// 2026-10-19 真机 stage0.log: delegate 里引用外层 id (如 categorySection / searchDialog) 在 qmlcachegen
// 编译下会抛 ReferenceError, 必须 Bound 语义才能拿到外层组件作用域.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: detailPage

    // === 入参 ==============================================================
    // 图鉴入口: entityId + kingdomIndex
    property string entityId: ""
    // 危险物种入口 (2026-10-20 合并): 只给 id, 界门由前缀推, 图鉴取不到再回 danger 库
    property string speciesId: ""
    // 2026-10-20 #60: 同一个 id 可能两边都有 (plant_gelsemium 在 33 条危险库和 659 条
    //   图鉴里各一份, 字段集不同). 由入口决定读哪一份, 不让物种内容随点击路径漂移.
    property bool preferDanger: false
    // 2026-09-19: 兼容旧调用, 保留 entity 入参. 但下面 _loadEntity() 会优先
    //   按 entityId + kingdomIndex 重新拉取完整数据, 避免 ListModel role 化导致
    //   嵌套数组 (ediblePart / lookAlike[fieldMap]) 丢失或变 QQmlListModel.
    property var entity: ({})
    property int kingdomIndex: 0  // 0=植物 1=动物 2=昆虫 3=蘑菇
    property bool opened: false

    signal closeRequested()

    title: entity.commonName || "物种详情"

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles; visible: false }

    // === 运行时状态 =========================================================
    property bool _photoLoading: false
    // 这个物种在我地图上标过的点 (取不到 NOTIFY 的 service 方法 → 手动刷)
    property var _marks: []
    // 2026-10-23 #113: 真机 46 条标注把整段拉成一屏半的墙. 默认只铺最近 5 条,
    //   要看得更多点「展开全部」—— 方位条/清空仍然吃全量 _marks, 折叠只是显示层.
    readonly property int _marksShownCount: detailPage._marksExpanded
                                            ? detailPage._marks.length
                                            : Math.min(5, detailPage._marks.length)
    property bool _marksExpanded: false
    property string _marksOwner: ""
    property bool _fav: false
    // entity 来自哪套数据: false = danger_species.json (没有图册检索词/代表色)
    property bool _fromGuide: true
    ListModel { id: photoModel }

    // === 定位 (与 ①营地 同一来源) ===========================================
    readonly property bool hasFix: emergencyService ? emergencyService.hasLocation : false
    readonly property real curLat: emergencyService ? emergencyService.currentLatitude : 0
    readonly property real curLon: emergencyService ? emergencyService.currentLongitude : 0
    readonly property real altM: emergencyService ? emergencyService.currentAltitude : Number.NaN
    // 2026-10-26「精度到 1 米」: 标注点要带上这一帧的 ± 精度, 存进 species_*.json.
    //   NaN = 后端没给 HorizontalAccuracy; 不许写成 0 (JSON 里的 0 会被读成"精度 0 米").
    readonly property real accM: emergencyService ? emergencyService.currentAccuracy : Number.NaN

    // 缺字段一律翻成 NaN, 不用 `Number(x) || 0` —— 后者把"没有高程"写成"海拔 0 米",
    //   把"没有精度"写成"精度 0 米", 两种假读数在列表里都看不出破绽.
    function _numOrNaN(v) {
        if (v === undefined || v === null || v === "") return Number.NaN
        var n = Number(v)
        return isFinite(n) ? n : Number.NaN
    }

    // === 小工具 ============================================================
    // Result 信封判成功: 信封是对象, 直接 `if (res)` 恒真 (规则 ③)
    function _ok(res) { return !!(res && res.ok) }

    // 2026-09-19: 把 list 字段统一转成 JS Array (避免 .join() 报
    //   "Property 'join' of object QQmlListModel is not a function").
    //   QStringList 在 QML 端是 QQmlListModel, 没有 Array.prototype 方法.
    function _toArr(v) {
        if (!v) return []
        if (Array.isArray(v)) return v
        var out = []
        try {
            for (var i = 0; i < v.length; ++i) out.push(v[i])
        } catch (e) { return [] }
        return out
    }

    // [3,"4","5","9"] → "3—5 · 9 月" (mock 的"季节"格就是这种压缩写法)
    function _monthRange(list) {
        var nums = []
        for (var i = 0; i < list.length; ++i) {
            var n = parseInt(list[i], 10)
            if (isFinite(n) && n >= 1 && n <= 12) nums.push(n)
        }
        if (nums.length === 0) return ""
        nums.sort(function (a, b) { return a - b })
        var out = [], start = nums[0], prev = nums[0]
        for (var j = 1; j < nums.length; ++j) {
            if (nums[j] === prev + 1) { prev = nums[j]; continue }
            out.push(start === prev ? String(start) : start + "—" + prev)
            start = nums[j]; prev = nums[j]
        }
        out.push(start === prev ? String(start) : start + "—" + prev)
        return out.join(" · ") + " 月"
    }

    // === 取数 ==============================================================
    // kingdomIndex -> kingdom 字符串 (缓存目录 / 收藏记录用)
    function _kingdomName() {
        return ["plantae", "animalia", "insecta", "fungi"][kingdomIndex] || "unknown"
    }
    function _kingdomHint() {
        return ["plant", "animal", "insect", "mushroom"][kingdomIndex] || ""
    }
    // kingdom 字符串 -> kingdomIndex (易混种跳转时该条目可能跨类别)
    function _kingdomIndexOf(kingdom) {
        var i = ["plantae", "animalia", "insecta", "fungi"].indexOf(kingdom)
        return i >= 0 ? i : detailPage.kingdomIndex
    }
    // danger_species 的 id 前缀 -> 界门 (snake/animal 都算动物界)
    function _kingdomIndexFromId(id) {
        if (id.indexOf("plant_") === 0) return 0
        if (id.indexOf("mushroom_") === 0) return 3
        if (id.indexOf("insect_") === 0) return 2
        if (id.indexOf("snake_") === 0 || id.indexOf("animal_") === 0) return 1
        return -1
    }
    // 当前界门对应的 service (上下文属性, teardown 期可能已为 null)
    function _svcOf(idx) {
        return idx === 0 ? plantService
             : idx === 1 ? animalService
             : idx === 2 ? insectService
             : idx === 3 ? mushroomService : null
    }

    function buildFirstAidModel() {
        var arr = []
        if (entity.firstAidId) {
            arr.push({ "scenario": "中毒/咬伤", "id": entity.firstAidId })
        }
        var links = entity.firstAidLinks
        if (links) {
            for (var k in links) arr.push({ "scenario": k, "id": links[k] })
        }
        return arr
    }

    // 2026-09-24: 取本实体的下载检索词, photoSources 为空时用学名/中文名兜底.
    //   背景: 数据侧历史遗留导致部分条目没有 photo_sources, 旧逻辑在此直接 return →
    //   imageFetcher.fetchImages 永不调用 → 图册永远"暂无图片".
    //   danger_species 那套数据只有 photos 字段, 所以两个名字都读.
    function _collectSources() {
        var data = _toArr(entity.photoSources)
        if (data.length === 0) data = _toArr(entity.photos)
        var out = []
        for (var i = 0; i < data.length; ++i) {
            if (data[i]) out.push(data[i])
        }
        if (out.length > 0) return out
        var sci = (entity.scientificName || "").trim()
        var cn = (entity.commonName || "").trim()
        if (sci) out.push(sci)
        if (cn) {
            out.push(cn)
            var hint = _kingdomHint()
            if (hint) out.push(cn + " " + hint)
        }
        return out
    }

    // 2026-09-19: 运行时图册 (ImageFetcherService 提供)
    // 2026-09-30 诊断: 图册加载链路埋点 (QML 侧). 走 qDebug → 全局 message handler
    //   汇聚进 stage0.log. 判读: 无 "gp loadPhotos" → 本函数没跑 (entity 未就绪);
    //   有 "gp loadPhotos sources=0" → 检索词为空 (数据字段缺失);
    //   有 "gp loadPhotos ... calling fetchImages" 但无后续 "gp allReady/gp failed"
    //   → C++ 侧信号没回 → 看 C++ 的 "img req/reply" 埋点.
    function _loadPhotos() {
        photoModel.clear()
        if (!entity || !entity.id) {
            console.warn("[gp loadPhotos] SKIP no entity.id")
            return
        }
        var sources = _collectSources()
        if (sources.length === 0) {
            console.warn("[gp loadPhotos] SKIP sources=0 id=" + entity.id)
            return
        }
        var kingdom = _kingdomName()
        if (!imageFetcher) {
            console.warn("[gp loadPhotos] SKIP imageFetcher 不可用 id=" + entity.id)
            return
        }
        var cached = imageFetcher.cachedImages(entity.id, kingdom)
        // fetchImages 会把已缓存的图作为 imageReady 信号立即重发, 这里只标记加载态
        detailPage._photoLoading = (cached.length === 0)
        console.log("[gp loadPhotos] id=" + entity.id + " kingdom=" + kingdom
                    + " sources=" + sources.length + " cached=" + cached.length
                    + " loading=" + detailPage._photoLoading
                    + " → calling fetchImages")
        imageFetcher.fetchImages(entity.id, kingdom, sources)
    }

    // 地图上的记录 + 收藏态: 两个都是"没有 NOTIFY 的 service 方法", 只能手动取
    function _loadMarks() {
        var out = []
        if (!mapService || !entity.id) { detailPage._marks = out; return }
        // 换物种时收起折叠: 上一个物种"展开全部到第 40 条"的状态不该跟过来
        if (detailPage._marksOwner !== entity.id) {
            detailPage._marksOwner = entity.id
            detailPage._marksExpanded = false
        }
        var raw = mapService.getSpeciesLocations()
        for (var i = 0; i < raw.length; ++i) {
            var m = raw[i]
            if (m.speciesId !== entity.id) continue
            var la = Number(m.lat), lo = Number(m.lon)
            if (!isFinite(la) || !isFinite(lo)) continue
            out.push({
                id: String(m.id || ""),
                lat: la, lon: lo,
                // 2026-10-26: 这两个键在新数据里"未知就整条不写", 所以读回来是
                //   undefined. 原来写 `Number(m.altitude) || 0` 把未知变成 0 ——
                //   列表里 "0 m" 看着像"海平面", ±0 看着像"极准", 两个都是假读数.
                alt: _numOrNaN(m.altitude),
                accM: _numOrNaN(m.accuracy),
                note: m.note || "",
                takenAt: m.takenAt || ""
            })
        }
        // 2026-10-23 #113: id 就是 addSpeciesLocation 的 epoch-ms, 文件名排序=时间升序,
        //   于是"最近标的"排在 46 行的最底下. 详情页要的是最近几条, 倒过来.
        out.sort(function (a, b) { return (b.id || "").localeCompare(a.id || "") })
        detailPage._marks = out
    }

    function _loadFav() {
        detailPage._fav = (fieldGuideHistory && entity.id)
                          ? fieldGuideHistory.isFavoriteEntity(entity.id) : false
    }

    // 2026-09-19: 进入页面时按 entityId 重新拉数据 + 触发图册加载
    // 2026-09-20: 之前 Component.onCompleted + onEntityIdChanged 双触发导致 _loadEntity
    //   跑两次 (一次空 id, 一次有效 id). 只用变更信号 + 兜底首帧.
    onEntityIdChanged: detailPage._loadEntity()
    onSpeciesIdChanged: detailPage._loadEntity()
    onKingdomIndexChanged: detailPage._loadEntity()
    // 2026-10-20: StackView 的 initialProperties 是一条一条赋的. 若 speciesId 先落地,
    //   上面那两条已经把图鉴那份取完了, 之后 preferDanger 才变 true —— 不补一次就会
    //   停在错的数据源上. 只在"要 danger 而当前是图鉴, 且危险库里确实有这个 id"时重取.
    onPreferDangerChanged: {
        if (!detailPage.preferDanger || !detailPage._fromGuide || !speciesService) return
        var lid = detailPage.entityId || detailPage.speciesId
        if (!lid) return
        var hit = speciesService.getById(lid)
        if (hit && hit.id) detailPage._loadEntity()
    }
    // 2026-09-20: onEntityChanged 不再隐式触发 _loadPhotos, 改为 _loadEntity 显式调
    //   (避免 recordLocation 修改 entity 后 _loadPhotos 再次跑, 清空刚刚加载的图).
    function _loadEntity() {
        var id = entityId || speciesId || (entity && entity.id) || ""
        if (!id) {
            console.warn("[gp loadEntity] SKIP empty id")
            return
        }
        // speciesId 入口: 界门由前缀推. 改了界门就交给 onKingdomIndexChanged 再跑一次,
        // 否则同一次调用里既换界门又取数, 日志会出现两遍完整加载.
        if (!entityId && speciesId) {
            var k = _kingdomIndexFromId(speciesId)
            if (k >= 0 && k !== kingdomIndex) {
                kingdomIndex = k
                return
            }
        }
        var svc = _svcOf(kingdomIndex)
        var fresh = svc ? svc.getById(id) : {}
        // 33 条危险物种里有若干条同时也在图鉴 (如 plant_gelsemium). 两套字段集不同:
        //   危险库有 symptoms/protectiveGear/categoryName, 图鉴有 venomType/可食/易混/代表色.
        // 逐字段覆盖会让同一个物种在不同入口长得不一样, 所以整条替换: 入口说用哪套就用哪套.
        if (detailPage.preferDanger && speciesService) {
            var pds = speciesService.getById(id)
            if (pds && pds.id) {
                detailPage._fromGuide = false
                entity = pds
                console.log("[gp loadEntity] id=" + id + " ← danger_species (preferDanger)")
                detailPage._loadPhotos()
                detailPage._loadMarks()
                detailPage._loadFav()
                return
            }
            // preferDanger 但危险库里没有 (路线关联表里的 id 可能是图鉴 id) → 回落到图鉴
        }
        if (fresh && fresh.id) {
            detailPage._fromGuide = true
            entity = fresh
            console.log("[gp loadEntity] id=" + id + " kingdomIndex=" + kingdomIndex
                        + " ← 图鉴库 (speciesService 不参与)")
            detailPage._loadPhotos()
        } else if (speciesService) {
            // 图鉴四本里没有这个 id → 危险物种库 (danger_species.json)
            var ds = speciesService.getById(id)
            if (!ds || !ds.id) {
                console.warn("[gp loadEntity] id=" + id + " 两套数据都查不到")
                return
            }
            detailPage._fromGuide = false
            entity = ds
            console.log("[gp loadEntity] id=" + id + " ← danger_species")
            detailPage._loadPhotos()
        } else {
            console.warn("[gp loadEntity] 服务不可用 id=" + id)
            return
        }
        detailPage._loadMarks()
        detailPage._loadFav()
    }

    Component.onCompleted: {
        if (emergencyService) emergencyService.requestLocationUpdate()
        detailPage._loadEntity()
    }

    Connections {
        target: mapService
        function onDataChanged() { detailPage._loadMarks() }
    }

    // === 派生读数 ==========================================================
    // 2026-10-19: 危险档位原来是 hero / 性质卡 / 易混种三处各抄一遍同样的
    //   四段三元, 改一处忘两处就出现"红色图标配绿色文字". 收敛成三个只读属性.
    readonly property string _dangerIcon: entity.dangerLevel >= 4 ? "error"
                                          : entity.dangerLevel >= 1 ? "warning" : "check"
    // 档位文案只讲危险度. 0 档以前写"无害可食" —— 可食不是危险度的推论 (一只无毒的鸟
    // 不等于能吃), 能吃由下面的可食卡和类目 chip 说.
    // 2026-10-26: 这四段三元收进 CommonOptions.dangerLevelLabel(), 地图标注弹层也读它
    readonly property string _dangerLabel: CommonOptions.dangerLevelLabel(entity.dangerLevel)
    readonly property color _dangerTone: entity.dangerLevel >= 4 ? CommonOptions.colorHazard
                                       : entity.dangerLevel >= 1 ? CommonOptions.colorWarn
                                                                 : CommonOptions.colorForest

    // 类目: 图鉴库存英文键, 危险物种库存的是 categoryName (已经中文)
    readonly property string _categoryLabel: {
        if (entity.categoryName) return entity.categoryName
        var c = entity.category
        return (typeof c === "string" && c.length > 0)
               ? CommonOptions.speciesCategoryLabel(c) : ""
    }

    // 图版色块: representative_color 是 {h,s,v} (数据 659 条全有), 危险物种库没有该字段
    readonly property bool _plateColorValid: {
        var c = entity.representativeColor
        return !!(c && typeof c === "object" && isFinite(Number(c.h)))
    }
    // 2026-10-21 真机: 这里原来调 Qt.hsv() —— QML 根本没有这个函数 (只有 Qt.hsla),
    //   每次求值都抛 TypeError, 色块永远拿不到色。HSV→RGB 收口到 CommonOptions::hsvColor。
    readonly property color _plateColor: _plateColorValid
        ? CommonOptions.hsvColor(Math.round(Number(entity.representativeColor.h)),
                                 Math.round(Number(entity.representativeColor.s) || 0),
                                 Math.round(Number(entity.representativeColor.v) || 0))
        : CommonOptions.colorSurfaceDim

    // 题注读数: 把数据里原始的 h/s/v 抄出来 (口径同数据侧: h 0-360、s/v 0-100,
    // 正是 CommonOptions::hsvColor 的入参, 不做任何换算)
    readonly property string _plateHsvText: {
        var c = entity.representativeColor
        if (!(c && typeof c === "object")) return ""
        return "H" + Math.round(Number(c.h) || 0)
               + " S" + Math.round(Number(c.s) || 0)
               + " V" + Math.round(Number(c.v) || 0)
    }

    // 海拔: 图鉴给 min/max, 危险物种库给拼好的 "0-2500m" 字符串
    readonly property string _elevText: {
        if (entity.elevationRange) return entity.elevationRange
        var lo = Number(entity.minElevation) || 0
        var hi = Number(entity.maxElevation) || 0
        if (hi <= 0) return ""
        return lo > 0 ? (lo + "—" + hi + " m") : ("≤" + hi + " m")
    }

    // 速览网格 (只列数据里真有内容的行, 空行不留占位)
    readonly property var _facts: {
        var out = []
        var mo = _monthRange(_toArr(entity.activeMonths))
        if (mo) out.push({ k: "季节", v: mo })
        var hab = _toArr(entity.habitats)
        if (hab.length) out.push({ k: "生境", v: hab.join("、") })
        if (_elevText) out.push({ k: "海拔", v: _elevText })
        var dist = _toArr(entity.distribution)
        if (dist.length) {
            out.push({ k: "分布",
                       v: dist.slice(0, 5).join("、")
                          + (dist.length > 5 ? " 等 " + dist.length + " 处" : "") })
        }
        var al = _toArr(entity.alias)
        if (al.length) out.push({ k: "又名", v: al.join("、") })
        if (entity.protectionLevel) out.push({ k: "保护", v: entity.protectionLevel })
        return out
    }

    // 可食 (只有植物界填了这组字段)
    readonly property bool _hasEdible: kingdomIndex === 0 && _toArr(entity.ediblePart).length > 0
    readonly property var _edibleRows: {
        var out = []
        if (!detailPage._hasEdible) return out
        var parts = _toArr(entity.ediblePart), i
        var pn = []
        for (i = 0; i < parts.length; ++i) pn.push(CommonOptions.ediblePartLabel(parts[i]))
        out.push({ k: "部位", v: pn.join("、") })
        var em = _monthRange(_toArr(entity.edibleMonths))
        if (em) out.push({ k: "采食期", v: em })
        var meths = _toArr(entity.edibleMethod), mn = []
        for (i = 0; i < meths.length; ++i) mn.push(CommonOptions.edibleMethodLabel(meths[i]))
        if (mn.length) out.push({ k: "做法", v: mn.join("、") })
        if (entity.taste) out.push({ k: "口感", v: entity.taste })
        out.push({ k: "生食", v: entity.rawEdible ? "可生食" : "不建议生食" })
        if (entity.mustCook) out.push({ k: "做熟", v: "必须彻底做熟" })
        if (entity.harvestTips) out.push({ k: "采摘", v: entity.harvestTips })
        return out
    }

    // 毒性与症状 (动物/蘑菇界 + 危险物种库的症状/防护)
    readonly property var _dangerRows: {
        var out = []
        if (kingdomIndex === 1) {
            var vt = entity.venomType
            if (vt && vt !== "none") {
                out.push({ k: "毒素", v: CommonOptions.venomTypeLabel(vt) })
                if (entity.venomLocation) out.push({ k: "部位", v: entity.venomLocation })
                if (Number(entity.attackDistanceCm) > 0)
                    out.push({ k: "攻击距离", v: entity.attackDistanceCm + " cm" })
                if (entity.activeTime) out.push({ k: "活跃", v: entity.activeTime })
            }
        }
        if (kingdomIndex === 3 && entity.poisoningType) {
            out.push({ k: "中毒类型", v: entity.poisoningType })
            if (Number(entity.latencyHours) > 0)
                out.push({ k: "潜伏期", v: entity.latencyHours + " 小时" })
            if (entity.mortalityRate) out.push({ k: "致死率", v: entity.mortalityRate })
        }
        var sy = _toArr(entity.symptoms)
        if (sy.length) out.push({ k: "症状", v: sy.join("；") })
        var pg = _toArr(entity.protectiveGear)
        if (pg.length) out.push({ k: "防护", v: pg.join("、") })
        return out
    }

    // 最近一个标注点 (有定位才算得出方位; 没定位时方位条整块不出现 —— 规则 ①)
    readonly property var _nearest: {
        if (!hasFix || _marks.length === 0) return null
        var best = null, bestD = -1, brg = 0
        for (var i = 0; i < _marks.length; ++i) {
            var m = _marks[i]
            var d = CommonOptions.distanceMeters(curLat, curLon, m.lat, m.lon)
            if (bestD < 0 || d < bestD) { bestD = d; best = m }
        }
        if (!best) return null
        brg = CommonOptions.bearingDegrees(curLat, curLon, best.lat, best.lon)
        return { mark: best, dist: bestD, bearing: brg }
    }
    // 这句有汉字 (方位词), 不许绑 monoFont
    readonly property string _bearingReadout: _nearest
        ? Math.round(_nearest.bearing) + "° · "
          + CommonOptions.compassLabel(_nearest.bearing) + " · "
          + CommonOptions.formatBearingDistance(_nearest.dist)
        : ""

    // 标注点的等宽读数行: 纯拉丁数字 (规则 ④)
    function markMonoText(m) {
        var s = m.lat.toFixed(5) + " / " + m.lon.toFixed(5)
        // 2026-10-26「精度到 1 m」: ± 说的是这一帧的水平精度, 老数据没这个键就不写
        //   (写 ±0 会被读成"这个点极准").
        if (isFinite(m.accM) && m.accM > 0) s += " · ±" + Math.round(m.accM) + "m"
        // 高程: 原来 gate 是 `m.alt > 0`, 未知被上游写成 0 时恰好不显示; 现在未知是
        //   NaN, 用 isFinite 判. 负高程 (吐鲁番盆地) 是真数, 要显示.
        if (isFinite(m.alt)) s += " · " + Math.round(m.alt) + "m"
        var t = String(m.takenAt || "")
        if (t.length >= 10) s += " · " + t.slice(5, 10)
        return s
    }

    // === 动作 ==============================================================
    function back() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    function toggleFavorite() {
        if (!fieldGuideHistory) {
            console.warn("[gp favorite] fieldGuideHistory 不可用")
            recordTip.show("收藏失败: 历史记录服务不可用", false)
            return
        }
        if (!entity.id) { recordTip.show("收藏失败: 缺少实体 ID", false); return }
        // 2026-10-20 #59: 原来这里给 addRecord(ViewRecord) 传 12 个位置参数 ——
        //   那个方法只吃结构体, QML 构造不出它, 调用静默失败, 所以"收藏点了没反应".
        var res = fieldGuideHistory.toggleFavoriteByEntity(
            entity.id, _kingdomName(), entity.commonName || "",
            entity.scientificName || "", _categoryLabel, Number(entity.dangerLevel) || 0)
        if (_ok(res)) {
            detailPage._fav = res.value.favorite === true
            recordTip.show(_fav ? "已收藏 · 在「我 → 收藏」里" : "已取消收藏", true)
        } else {
            recordTip.show("收藏失败: " + ((res && res.error && res.error.message)
                                          || "未知错误"), false)
        }
    }

    function recordHere() {
        if (!mapService) { recordTip.show("记录失败: 地图服务不可用", false); return }
        if (!entity.id) { recordTip.show("记录失败: 缺少实体 ID", false); return }
        // 规则 ②: 没定位不写库 (以前写死北京坐标, 野外标的点全落到首都)
        if (!hasFix) { recordTip.show("未定位 · GPS 就绪后才能记录位置", false); return }
        // 2026-10-26「精度到 1 m」: 原来这里 `(isFinite(altM) && altM > 0) ? altM : 0`
        //   —— 没有高程就写 0, 落盘读起来是"海平面 0 米". 现在高程未知就传 NaN,
        //   C++ 那一键整条不写; 同时把这帧的 ± 精度一起存进去, 标注列表说得清准不准.
        var alt = (isFinite(altM) && altM > -500 && altM < 9000) ? altM : Number.NaN
        var acc = (isFinite(accM) && accM > 0) ? accM : Number.NaN
        var res = mapService.addSpeciesLocation(
            entity.id, entity.commonName || "", _kingdomName(),
            curLat, curLon, alt, "图鉴详情手动记录", acc)
        if (_ok(res)) {
            detailPage._loadMarks()
            recordTip.show("已记录 " + curLat.toFixed(5) + " / " + curLon.toFixed(5)
                           + (isFinite(acc) ? " · ±" + acc.toFixed(1) + " m"
                                           : " · 该点没有精度读数")
                           + " · 地图与方位条同步", true)
        } else {
            recordTip.show("记录失败: " + ((res && res.error && res.error.message)
                                          || "未知错误"), false)
        }
    }

    // 2026-10-23 #113: 标注此前只能写不能删 —— 野外试标的一堆点会永远压在详情页.
    //   走 MapService::deleteSpeciesLocation (按 species_<id>.json 文件名删).
    function deleteMark(id) {
        if (!mapService) { recordTip.show("删除失败: 地图服务不可用", false); return }
        if (!id) { recordTip.show("删除失败: 这条标注没有 ID", false); return }
        var res = mapService.deleteSpeciesLocation(String(id))
        if (_ok(res)) {
            detailPage._loadMarks()
            recordTip.show("已删除 1 条标注 · 剩余 " + detailPage._marks.length + " 条", true)
        } else {
            // 全站口径: ServiceError 是 QmlResultBridge 塞进 res.error 的对象, 可读的是
            //   res.error.message. 直接把 res.error 拼进字符串会得到对象名, 用户看不到原因.
            recordTip.show("删除失败: " + ((res && res.error && res.error.message)
                                          || "未知错误"), false)
        }
    }

    // 清空 = 逐条删. 不另开一个 C++ 批量接口: 标注本来就是一条一个文件,
    //   量级只有几十条, 少一处要维护的 SQL/目录扫描.
    function clearMarks() {
        if (!mapService) { recordTip.show("清空失败: 地图服务不可用", false); return }
        var ids = []
        for (var i = 0; i < detailPage._marks.length; ++i) {
            var id = String(detailPage._marks[i].id || "")
            if (id) ids.push(id)
        }
        if (ids.length === 0) { recordTip.show("这个物种没有可删的标注", false); return }
        var failed = 0
        for (var j = 0; j < ids.length; ++j) {
            if (!_ok(mapService.deleteSpeciesLocation(ids[j]))) failed++
        }
        detailPage._loadMarks()
        recordTip.show(failed === 0
                       ? "已清空 " + ids.length + " 条标注"
                       : "清空完成, 但有 " + failed + " 条没删掉", failed === 0)
    }

    function openInMap(lat, lon) {
        var name = (entity.commonName || "物种") + (_categoryLabel ? " · " + _categoryLabel : "")
        if (!CommonOptions.openMapMarker(lat, lon, name))
            recordTip.show("没找到可用的地图应用 (高德/geo: 都打不开)", false)
    }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- ① 图版头 (150px 沉底图版区, 不用渐变) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            color: CommonOptions.colorSurfaceAlt

            // 底边 1px 墨线: 图版区与正文的分界靠描边, 不靠阴影
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            // 代表色色块 (数据里的 representative_color, 不是装饰)
            // 2026-10-22 #96(a): 光有 46×46 色块读不出它是数据 —— 旁边补两行题注,
            //   上行汉字说是"代表色", 下行等宽把 h/s/v 三个原始数字抄出来. 色块一旦
            //   带上读数, 就与图版编号 (SP-xxx) 同属"这条记录的字段", 而不是页面配色.
            //   汉字与数字必须拆两个 Text: styles.monoFont 族没汉字字形 (真机出方框).
            RowLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 22
                spacing: styles.spSm

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                    color: detailPage._plateColor
                    border.color: CommonOptions.colorText
                    border.width: styles.lineHair
                    IconLabel {
                        anchors.centerIn: parent
                        // 危险物种库没有代表色, 也只在真有对应字形时才补图标
                        // (本字体无蘑菇/昆虫形, 硬凑就是"蛇画成垃圾桶")
                        visible: !detailPage._plateColorValid && detailPage.kingdomIndex <= 1
                        name: detailPage.kingdomIndex === 0 ? "plant" : "animal"
                        size: styles.icMd
                        tintColor: CommonOptions.colorInk3
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    visible: detailPage._plateColorValid
                    spacing: 1
                    Text {
                        text: "代表色"
                        font.pixelSize: styles.fsXs
                        // 汉字微标签: 不加字距 (样式铁律), 且不进 mono 族
                        font.letterSpacing: 0
                        color: CommonOptions.colorTextDim
                    }
                    Text {
                        text: detailPage._plateHsvText
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextMuted
                    }
                }
            }

            // 左下: 编号 + 中文名
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
                        prefix: "SP"
                        entryId: entity.id || ""
                        bracketed: true
                        tone: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    // 右下: 学名 (拉丁 → 可以等宽) + 类目 (汉字 → 默认字体)
                    ColumnLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignBottom
                        spacing: 1
                        Text {
                            Layout.alignment: Qt.AlignRight
                            visible: (entity.scientificName || "").length > 0
                            text: entity.scientificName || ""
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorTextMuted
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            visible: detailPage._categoryLabel.length > 0
                            text: detailPage._categoryLabel
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                            elide: Text.ElideRight
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: entity.commonName || "物种详情"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
            }

            // 左上: 档位 chip
            DangerChip {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: styles.pageMargin
                anchors.topMargin: styles.spSm
                level: Number(entity.dangerLevel) || 0
                compact: true
                label: detailPage._dangerLabel
            }

            // 右上: 收藏 + 返回 (26px 方块视觉, 热区各扩 6px 到 38~44)
            Row {
                id: headButtons
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: styles.cardPad
                anchors.topMargin: styles.cardPad
                spacing: styles.spXs

                Rectangle {
                    width: 30
                    height: 30
                    color: detailPage._fav ? CommonOptions.colorAmber
                                           : CommonOptions.colorSurface
                    border.color: CommonOptions.colorText
                    border.width: styles.lineHair
                    IconLabel {
                        anchors.centerIn: parent
                        name: detailPage._fav ? "star" : "bookmark"
                        size: styles.icSm
                        tintColor: detailPage._fav ? CommonOptions.colorTextOnAccent
                                                   : CommonOptions.colorText
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: detailPage.toggleFavorite()
                    }
                }
                Rectangle {
                    width: 30
                    height: 30
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
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: detailPage.back()
                    }
                }
            }
        }

        // --- ② 方位条: 没有标注点就没有这一条 (规则 ①) ---
        Rectangle {
            Layout.fillWidth: true
            visible: detailPage._nearest !== null
            // 是 ColumnLayout 的孩子 → 只能给 Layout.preferredHeight, 写 height 是
            // 未定义行为 (qmllint [Quick.layout-positioning], 2026-10-21 全站门禁抓到)
            Layout.preferredHeight: bearingCol.implicitHeight + 2 * styles.spSm
            color: CommonOptions.colorSurface

            ColumnLayout {
                id: bearingCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: styles.spXs

                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "相对你的方位"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: detailPage._bearingReadout
                        font.pixelSize: styles.fsSm
                        color: CommonOptions.colorText
                    }
                }
                BearingBar {
                    Layout.fillWidth: true
                    bearing: detailPage._nearest ? detailPage._nearest.bearing : 0
                    hasBearing: detailPage._nearest !== null
                    tone: CommonOptions.colorWater
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

            ColumnLayout {
                width: parent.width
                spacing: styles.spMd

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    Layout.topMargin: styles.spMd
                    spacing: styles.spSm

                    // 学名在图版头已给, 这里补别名/一句话识别 (mock ③ 的正文起手)
                    Text {
                        Layout.fillWidth: true
                        visible: (entity.description || "").length > 0
                        text: entity.description || ""
                        font.pixelSize: styles.fsMd
                        color: CommonOptions.colorText
                        wrapMode: Text.WordWrap
                    }
                    DuoRule { Layout.fillWidth: true }

                    // 速览网格
                    Repeater {
                        model: detailPage._facts
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: styles.spMd
                            Text {
                                Layout.preferredWidth: 40
                                Layout.alignment: Qt.AlignTop
                                text: modelData.k
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.v
                                font.pixelSize: styles.fsMd
                                color: CommonOptions.colorText
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // --- 可食卡 (植物界; 强调描边走 forest) ---
                Card {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: detailPage._hasEdible
                    borderTone: CommonOptions.colorForest
                    spacing: styles.spSm

                    SectionTitle {
                        Layout.fillWidth: true
                        icon: "plant"
                        text: "可食"
                        iconColor: CommonOptions.colorForest
                        titleColor: CommonOptions.colorForest
                        pixelSize: styles.fsMd
                    }
                    Repeater {
                        model: detailPage._edibleRows
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: styles.spMd
                            Text {
                                Layout.preferredWidth: 44
                                Layout.alignment: Qt.AlignTop
                                text: modelData.k
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.v
                                font.pixelSize: styles.fsSm
                                color: CommonOptions.colorText
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // --- 毒性与症状卡 (有内容才出现) ---
                Card {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: detailPage._dangerRows.length > 0
                    borderTone: entity.dangerLevel >= 3
                                ? CommonOptions.colorHazard : CommonOptions.colorWarn
                    spacing: styles.spSm

                    SectionTitle {
                        Layout.fillWidth: true
                        icon: "warning"
                        text: entity.dangerLevel >= 4 ? "危险" : "毒性与症状"
                        iconColor: entity.dangerLevel >= 4
                                   ? CommonOptions.colorHazard : CommonOptions.colorWarn
                        titleColor: entity.dangerLevel >= 4
                                    ? CommonOptions.colorHazard : CommonOptions.colorWarn
                        pixelSize: styles.fsMd
                    }
                    Repeater {
                        model: detailPage._dangerRows
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: styles.spMd
                            Text {
                                Layout.preferredWidth: 44
                                Layout.alignment: Qt.AlignTop
                                text: modelData.k
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.v
                                font.pixelSize: styles.fsSm
                                color: CommonOptions.colorText
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // --- 易混种 (琥珀描边; 有 id 的条目可跳它自己的详情页) ---
                Card {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: detailPage.lookAlikeCount > 0
                    borderTone: CommonOptions.colorWarn
                    spacing: styles.spSm

                    SectionTitle {
                        Layout.fillWidth: true
                        icon: "warning"
                        text: "易混"
                        trailing: "需 100% 确定"
                        iconColor: CommonOptions.colorHazard
                        titleColor: CommonOptions.colorWarn
                        pixelSize: styles.fsMd
                    }
                    Repeater {
                        model: entity.lookAlike || []
                        delegate: Rectangle {
                            id: laItem
                            required property var modelData
                            Layout.fillWidth: true
                            // 有 id 且有名字才算可跳转的图鉴内条目
                            readonly property bool _clickable: !!(laItem.modelData
                                                                 && laItem.modelData.id)
                            color: "transparent"
                            implicitHeight: laCol.implicitHeight
                            radius: styles.rMd

                            ColumnLayout {
                                id: laCol
                                width: parent.width
                                spacing: styles.spXs
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: styles.spXs
                                    // 2026-10-19: ▸ (U+25B8) 该机无字形 → tofu; 统一走
                                    //   IconLabel 语义名 chevron_right.
                                    IconLabel {
                                        name: "chevron_right"
                                        size: styles.icSm
                                        tintColor: laItem._clickable
                                                   ? CommonOptions.colorBlaze
                                                   : CommonOptions.colorText
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: (laItem.modelData.name
                                               || laItem.modelData.commonName || "未知")
                                              + (laItem.modelData.fatality
                                                 ? "  (致死性: " + laItem.modelData.fatality + ")"
                                                 : "")
                                        color: laItem._clickable
                                               ? CommonOptions.colorBlaze : CommonOptions.colorText
                                        font.pixelSize: styles.fsMd
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "区别: " + (laItem.modelData.distinction || "")
                                    color: CommonOptions.colorTextMuted
                                    font.pixelSize: styles.fsSm
                                    wrapMode: Text.WordWrap
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: laItem._clickable
                                cursorShape: laItem._clickable
                                             ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: detailPage.navigateTo("FieldGuideDetailPage", {
                                    entityId: laItem.modelData.id,
                                    kingdomIndex: detailPage._kingdomIndexOf(
                                        laItem.modelData.kingdom)
                                })
                            }
                        }
                    }
                }

                // --- 急救联动 ---
                Card {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: detailPage.firstAidRows.length > 0
                    borderTone: CommonOptions.colorHazard
                    spacing: styles.spSm

                    SectionTitle {
                        Layout.fillWidth: true
                        icon: "firstaid"
                        text: "急救联动"
                        iconColor: CommonOptions.colorHazard
                        titleColor: CommonOptions.colorHazard
                        pixelSize: styles.fsMd
                    }
                    Repeater {
                        model: detailPage.firstAidRows
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: styles.spSm
                            Text {
                                Layout.fillWidth: true
                                text: modelData.scenario
                                font.pixelSize: styles.fsSm
                                color: CommonOptions.colorText
                                wrapMode: Text.WordWrap
                            }
                            OutlineButton {
                                Layout.alignment: Qt.AlignVCenter
                                text: "查看"
                                tone: CommonOptions.colorHazard
                                textSize: styles.fsSm
                                onClicked: detailPage.navigateTo(
                                    "FirstAidDetailPage", { entryId: modelData.id })
                            }
                        }
                    }
                }

                // 2026-09-19: 识别特征 - 数据已在 entity.features,
                // 4 个 field_guide_*.json 全部条目都有 features 填充
                Section {
                    titleIconName: "search"
                    title: "识别特征"
                    items: entity.features || []
                }

                // --- 图册 (2026-10-19 保留 [gp ...] 诊断埋点, 一条没删) ---
                Card {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm

                    RowLayout {
                        Layout.fillWidth: true
                        SectionTitle {
                            Layout.alignment: Qt.AlignVCenter
                            icon: "photo"
                            text: "图册"
                            trailing: detailPage._photoLoading
                                     ? ("加载中 " + photoModel.count) : String(photoModel.count)
                            iconColor: CommonOptions.colorText
                            pixelSize: styles.fsMd
                        }
                        Item { Layout.fillWidth: true }
                        // 2026-09-23: 图册刷新 —— 之前无图就永远无图 (C++ 不重试远程).
                        // 2026-10-19: 原加载态沙漏码位未核验, 统一 refresh 图标 + touchMin 热区.
                        Rectangle {
                            id: refreshBtn
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: styles.touchMin
                            Layout.preferredHeight: styles.touchMin
                            radius: styles.rPill
                            color: CommonOptions.withAlpha(CommonOptions.colorBlaze, 0.14)
                            border.color: CommonOptions.colorBlaze
                            border.width: styles.lineHair
                            enabled: !detailPage._photoLoading
                            opacity: enabled ? 1.0 : 0.45
                            ToolTip.text: "刷新图册 (清缓存重拉)"
                            ToolTip.visible: refreshArea.containsMouse
                            ToolTip.delay: 600
                            IconLabel {
                                anchors.centerIn: parent
                                name: "refresh"
                                size: styles.icMd
                                tintColor: CommonOptions.colorBlaze
                            }
                            MouseArea {
                                id: refreshArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!entity || !entity.id) return
                                    if (!imageFetcher) {
                                        console.warn("[gp refresh] imageFetcher 不可用")
                                        recordTip.show("图片服务不可用, 请稍后重试", false)
                                        return
                                    }
                                    var kingdom = detailPage._kingdomName()
                                    var sources = detailPage._collectSources()
                                    if (sources.length === 0) {
                                        recordTip.show("无可用检索词, 无法刷新", false)
                                        return
                                    }
                                    console.log("[gp refresh] id=" + entity.id
                                                + " kingdom=" + kingdom
                                                + " sources=" + sources.length
                                                + " → clearCache + fetchImages")
                                    imageFetcher.clearCache(entity.id, kingdom)
                                    photoModel.clear()
                                    detailPage._photoLoading = true
                                    imageFetcher.fetchImages(entity.id, kingdom, sources)
                                }
                            }
                        }
                    }

                    // 2 列网格 (图片来源: photoModel, 由 imageFetcher 异步填充)
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: styles.spSm
                        rowSpacing: styles.spSm
                        visible: photoModel.count > 0

                        Repeater {
                            model: photoModel
                            delegate: Rectangle {
                                id: cellBox
                                required property int index
                                required property string path
                                required property int idx
                                Layout.fillWidth: true
                                // 图片预览区必须固定高度 → styles.chartH (原来是裸 140)
                                Layout.preferredHeight: styles.chartH
                                radius: styles.rMd
                                color: CommonOptions.colorSurfaceDim
                                border.color: CommonOptions.colorDivider
                                border.width: styles.lineHair
                                clip: true

                                // 加载状态跟踪 - id 引用而非 parent.children[0]
                                Image {
                                    id: cellImage
                                    anchors.fill: parent
                                    source: cellBox.path
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    visible: status === Image.Ready
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 250 } }
                                }
                                // 加载占位 (灰底 + 索引 + spinner)
                                Item {
                                    anchors.fill: parent
                                    visible: cellImage.status !== Image.Ready
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: styles.spXs
                                        BusyIndicator {
                                            width: styles.icLg; height: styles.icLg
                                            running: cellImage.status === Image.Loading
                                            visible: cellImage.status === Image.Loading
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                        Text {
                                            // 2026-10-19: 2.jpg 里整屏红字 "加载失败" 太刺眼,
                                            //   而且自建 CDN 目前对所有路径回 HTML 占位页
                                            //   (图还没铺), 这不是用户能解决的错误.
                                            text: cellImage.status === Image.Error
                                                  ? "图片暂缺" : ("图 " + (cellBox.idx + 1))
                                            color: cellImage.status === Image.Error
                                                   ? CommonOptions.colorTextDim
                                                   : CommonOptions.colorTextMuted
                                            font.pixelSize: styles.fsXs
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                        IconLabel {
                                            visible: cellImage.status === Image.Error
                                            name: "broken_image"
                                            size: styles.icLg
                                            tintColor: CommonOptions.colorTextDisabled
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    EmptyState {
                        Layout.fillWidth: true
                        visible: photoModel.count === 0
                        iconName: "photo"
                        tint: CommonOptions.colorTextDim
                        text: detailPage._photoLoading ? "正在加载图片…" : "暂无图片"
                    }
                }

                // --- 地图上的记录 (你自己标过的点, 也是方位条的唯一数据源) ---
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: styles.spSm

                        SectionTitle {
                            Layout.fillWidth: true
                            icon: "pin_drop"
                            text: "地图上的记录"
                            trailing: detailPage._marks.length > 0
                                     ? String(detailPage._marks.length) : "无记录"
                            iconColor: CommonOptions.colorWater
                            pixelSize: styles.fsMd
                        }
                        // 2026-10-23 #113: 标注此前只进不出, 野外试标的点会永久堆在这页.
                        // 2026-10-26 真机反馈「样式还要改」: 原来这是一颗红描边 OutlineButton
                        //   (32 高) 顶在栏头 —— ①它和下面每一行的删除方块是同一个动作的两
                        //   半, 却画成两种东西; ②红描边按 token 规则只留给 SOS 与真危险,
                        //   一屏第 3 处强调描边就把它贬值了; ③danger 红字压在 fsXs 上最糊.
                        //   现在改成与行内删除方块同一套视觉 (surfaceDim 底 + divider 描边),
                        //   带一个"清空"词避免只剩图标看不懂.
                        Rectangle {
                            visible: detailPage._marks.length > 0
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: clearRow.implicitWidth + 2 * styles.spSm
                            Layout.preferredHeight: styles.btnHSm
                            radius: styles.rSm
                            color: CommonOptions.colorSurfaceDim
                            border.color: CommonOptions.colorDivider
                            border.width: styles.lineHair

                            RowLayout {
                                id: clearRow
                                anchors.centerIn: parent
                                spacing: styles.spXs
                                IconLabel {
                                    Layout.alignment: Qt.AlignVCenter
                                    name: "delete"
                                    size: styles.icSm
                                    tintColor: CommonOptions.colorTextMuted
                                }
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "清空"
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorTextMuted
                                }
                            }

                            TapHandler {
                                cursorShape: Qt.PointingHandCursor
                                onTapped: markClearDialog.open()
                            }
                        }
                    }

                    Repeater {
                        model: detailPage._marks.slice(0, detailPage._marksShownCount)
                        delegate: Rectangle {
                            id: markRow
                            required property var modelData
                            Layout.fillWidth: true
                            // 2026-10-23 真机 (用户截图: 46 行压成一团黑字): 这行原来绑
                            //   `markRowCol.implicitHeight` —— 全工程根本没有 markRowCol 这个
                            //   id, 绑定求值即抛 ReferenceError (release 包 logcat 全空, 只在
                            //   stage0.log 里), implicitHeight 停在 Rectangle 默认的 0 → 每行
                            //   0 高, 行内容靠 anchors.fill 也是 0, 文字不裁剪就整块溢出叠住
                            //   下一行. 现在绑这块 RowLayout 自己的隐式高度.
                            implicitHeight: markRowInner.implicitHeight + 2 * styles.cardPad
                            color: CommonOptions.colorSurface
                            border.color: CommonOptions.colorRule
                            border.width: styles.lineHair

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: styles.lineAccent
                                color: CommonOptions.colorWater
                            }

                            RowLayout {
                                id: markRowInner
                                anchors.fill: parent
                                anchors.leftMargin: styles.lineAccent + styles.cardPad
                                anchors.rightMargin: styles.cardPad
                                anchors.topMargin: styles.cardPad
                                anchors.bottomMargin: styles.cardPad
                                spacing: styles.spSm

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        Layout.fillWidth: true
                                        text: markRow.modelData.note
                                              ? markRow.modelData.note : "标注点"
                                        font.pixelSize: styles.fsMd
                                        color: CommonOptions.colorText
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        // 纯数字 + 斜杠 + 单位, 可以等宽 (规则 ④)
                                        text: detailPage.markMonoText(markRow.modelData)
                                        font.family: styles.monoFont
                                        font.pixelSize: styles.fsXs
                                        color: CommonOptions.colorTextDim
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: markRow.modelData.id === ""
                                        Layout.fillWidth: true
                                        // 老数据里没有 id 的行删不掉, 如实说, 不假装能删
                                        text: "此条没有 ID · 无法删除"
                                        font.pixelSize: styles.fsXs
                                        color: CommonOptions.colorHazard
                                        elide: Text.ElideRight
                                    }
                                    // 点这块文字 = 在高德里看这个点. 触点只盖文字列, 不盖删除
                                    //   方块 —— 两个动作叠在同一个触点上, 一次点击会又跳高德
                                    //   又弹删除确认. 用 TapHandler 不用整块 fill 的 MouseArea:
                                    //   后者按下即独占抓握, 慢速拖动会变成点行, 页面滚不动
                                    //   (同 #105 目标列表那次).
                                    TapHandler {
                                        cursorShape: Qt.PointingHandCursor
                                        onTapped: detailPage.openInMap(markRow.modelData.lat,
                                                                      markRow.modelData.lon)
                                    }
                                }

                                // 只是提示"点左边这块文字会跳高德", 本身不是触点
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "高德"
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorWater
                                }

                                // 删除走独立方块, 和"高德"不共用触点区, 免得一次点击两个动作
                                // 2026-10-28 控件盘点: 与「轨迹」Tab 的分析格、已选清单的
                                //   摘线格合成同一枚 IconActionCell (原来三处三份写法).
                                IconActionCell {
                                    Layout.alignment: Qt.AlignVCenter
                                    cellSize: styles.btnHSm
                                    iconName: "delete"
                                    tone: CommonOptions.colorDanger
                                    enabled: markRow.modelData.id !== ""
                                    onTriggered: {
                                        markDeleteDialog.pending = markRow.modelData
                                        markDeleteDialog.open()
                                    }
                                }
                            }
                        }
                    }

                    // 折叠只影响这一段的显示; 方位条和「清空」仍然吃全量 _marks
                    OutlineButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: detailPage._marks.length > 5
                        text: detailPage._marksExpanded
                              ? "收起 · 只看最近 5 条"
                              : "展开全部 " + detailPage._marks.length + " 条"
                        textSize: styles.fsXs
                        onClicked: detailPage._marksExpanded = !detailPage._marksExpanded
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: detailPage._marks.length === 0
                        text: detailPage.hasFix
                              ? "还没标过这个物种 · 到当前位置按「记录位置」"
                              : "GPS 未就绪 · 定位后才能记录位置"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextDim
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                    }
                }

                // --- 内联反馈 (2026-10-19: 自指高度 → Card, 状态色走 borderTone) ---
                Card {
                    id: recordTip
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: false
                    borderTone: CommonOptions.colorForest

                    Text {
                        id: tipText
                        Layout.fillWidth: true
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsSm
                        wrapMode: Text.WordWrap
                    }
                    Timer {
                        id: tipTimer
                        interval: 2400
                        onTriggered: recordTip.visible = false
                    }
                    function show(msg, ok) {
                        tipText.text = msg
                        recordTip.borderTone = ok ? CommonOptions.colorForest
                                                  : CommonOptions.colorHazard
                        visible = true
                        tipTimer.restart()
                    }
                }

                // --- 来源 / 审核 ---
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    text: "来源: " + (entity.source || "未注明")
                          + (entity.reviewer ? " · 审核: " + entity.reviewer : "")
                          + (detailPage._fromGuide ? "" : " · 危险物种库")
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorTextDim
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spMd }
            }
        }

        // --- ④ 固定底栏 (mock 的 34px 按钮低于 44 触摸下限, 这里按 btnH 撑高) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: styles.btnH + 2 * styles.spSm
            color: CommonOptions.colorSurfaceAlt

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                spacing: styles.spSm

                OutlineButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: styles.btnH
                    text: "带我过去"
                    tone: detailPage._marks.length > 0 ? CommonOptions.colorWater
                                                       : CommonOptions.colorTextDisabled
                    textSize: styles.fsLg
                    enabled: detailPage._marks.length > 0
                    onClicked: {
                        if (detailPage._marks.length === 0) return
                        // 有定位就用最近的标注点, 没定位退到第一个标过的点
                        var m = detailPage._nearest ? detailPage._nearest.mark : detailPage._marks[0]
                        detailPage.openInMap(m.lat, m.lon)
                    }
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    text: "记录位置"
                    iconName: "add"
                    tone: CommonOptions.colorAccent
                    textSize: styles.fsLg
                    enabled: detailPage.hasFix && !!entity.id
                    onClicked: detailPage.recordHere()
                }
            }
        }
    }

    // === 标注删除的两道确认 (2026-10-23 #113) =================================
    //   删除是不可逆的, 而且这一步没有"撤销" —— 所以单条和清空都先问一句.
    //   文案里带上坐标, 让用户确认的正是他要删的那一条.
    Dialog {
        id: markDeleteDialog
        title: "删除这条标注?"
        anchors.centerIn: parent
        width: Math.min(360, detailPage.width - 2 * styles.pageMargin)
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        padding: styles.spMd
        property var pending: null

        Text {
            text: markDeleteDialog.pending
                  ? detailPage.markMonoText(markDeleteDialog.pending)
                  : ""
            color: CommonOptions.colorText
            font.family: styles.monoFont
            font.pixelSize: styles.fsSm
            wrapMode: Text.WordWrap
        }
        footer: DialogFooter {
            cancelText: "留着"
            confirmText: "删除"
            confirmCode: "不可撤"
            onCancel: markDeleteDialog.close()
            onConfirm: {
                var m = markDeleteDialog.pending
                markDeleteDialog.close()
                if (m) detailPage.deleteMark(m.id)
            }
        }
    }

    Dialog {
        id: markClearDialog
        title: "清空这个物种的标注?"
        anchors.centerIn: parent
        width: Math.min(360, detailPage.width - 2 * styles.pageMargin)
        standardButtons: Dialog.NoButton
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        padding: styles.spMd

        Text {
            text: "共 " + detailPage._marks.length
                  + " 条 · 删掉后方位条和「带我过去」也会跟着没了"
            color: CommonOptions.colorText
            font.pixelSize: styles.fsMd
            wrapMode: Text.WordWrap
        }
        footer: DialogFooter {
            cancelText: "留着"
            confirmText: "清空"
            confirmCode: "不可撤"
            confirmEnabled: detailPage._marks.length > 0
            onCancel: markClearDialog.close()
            onConfirm: {
                markClearDialog.close()
                detailPage.clearMarks()
            }
        }
    }

    // === 只给上面版面用的两个计数 (避免在 visible 表达式里重复拼判断) ======
    readonly property int lookAlikeCount: _toArr(entity.lookAlike).length
    readonly property var firstAidRows: buildFirstAidModel()

    // 2026-09-19: ImageFetcherService 信号监听 (缓存命中 + 远程下载)
    // 2026-09-30 诊断: 每个 signal 入口第一行先打日志 —— 这是判定 "C++ 是否真的发了信号"
    //   与 "id 是否对得上" 的关键. 若 C++ 有 "img cached" 而这里无 "gp onImageReady" →
    //   信号名/参数不匹配或 Connections target 断了; 有 "gp onImageReady" 但 id 不匹配 →
    //   页面 entity.id 与 fetch 时传的 id 不一致 (entity 被换过).
    Connections {
        target: imageFetcher
        function onImageReady(id, index, localPath) {
            console.log("[gp onImageReady] id=" + id + " idx=" + index
                        + " curEntityId=" + (detailPage.entity ? detailPage.entity.id : "(no entity)")
                        + " path=" + localPath)
            if (!detailPage.entity) {
                console.warn("[gp onImageReady] entity 未就绪, drop")
                return
            }
            if (id !== detailPage.entity.id) {
                console.warn("[gp onImageReady] ID MISMATCH, drop")
                return
            }
            // 本地绝对路径 → file:// URL (Windows 测试机 + Android 真机都兼容)
            var url = "file:///"
            if (localPath.charAt(0) === "/") {
                url += localPath
            } else {
                url += localPath.replace(/\\/g, "/").replace(/^([A-Za-z]):/, "$1:")
            }
            // 已存在就不重复加 (cached 路径 + 远程补的可能是同一张)
            for (var i = 0; i < photoModel.count; i++) {
                if (photoModel.get(i).idx === index) {
                    console.log("[gp onImageReady] idx=" + index + " already in model, skip")
                    return
                }
            }
            photoModel.append({ "path": url, "idx": index })
            console.log("[gp onImageReady] appended, photoModel.count=" + photoModel.count
                        + " url=" + url)
        }
        function onImagesAllReady(id, paths) {
            console.log("[gp onImagesAllReady] id=" + id
                        + " curEntityId=" + (detailPage.entity ? detailPage.entity.id : "(no entity)")
                        + " paths=" + (paths ? paths.length : 0))
            if (detailPage.entity && id === detailPage.entity.id) detailPage._photoLoading = false
        }
        function onImageFailed(id, reason) {
            console.warn("[gp onImageFailed] id=" + id + " reason=" + reason)
            if (detailPage.entity && id === detailPage.entity.id) detailPage._photoLoading = false
        }
    }
}
