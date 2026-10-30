/**
 * @file EquipmentPage.qml
 * @brief 装备清单生成 + 我的清单 + 装备库 (2026-10-20 v9 F1/F3 同款, 丁骨架二级页)
 *
 * 入口有两个: 顶栏菜单抽屉的「装备」(Main.qml case "pack") 与「我」页第四行
 * (MePage), 都压在 stackView 上, 没有底部方位带 → 返回走标题条右上角的方角.
 *
 * 版式逐块对应已评审的 mock (review-v9-screens.html 「V9 · 3」+ 手册目录 F1 母版):
 *   标题条   54px 三段 (GEAR / xxx 微标签 / 视图名 / 读数行) + 右上 26px 方角返回.
 *   视图     三枚 chip 一行 (生成 / 我的清单 N / 装备库 N) 取代旧 TabBar + StackLayout.
 *   表单     两张 Card (行程 / 环境), 整块放在 ScrollView 里, 底栏钉住主操作.
 *   清单行   3px 海拔条 + 名称/副行 + 等宽度数 + 行内三枚方角动作块.
 *   库行     46px 图鉴编号 + 名称/类别 + 等宽度数 + 编辑(基础=复制副本)/删除.
 *   底栏     上边 1px 墨线: 左 OutlineButton 次级, 右 PrimaryButton 主操作.
 *
 * 四条不能破的规则:
 *   ① 不编读数. 库件数 / 关键件数 / 清单份数 / 重量全部由 equipmentService 现算,
 *      页面不写死 49 或 5.
 *   ② 表单里每一项都真的进 params. 旧版还发 tempAvg/tempMin/uvIndex/people 四个字段,
 *      但 equipment_rules.json 的 42 条规则里没有任何温度或人数条件
 *      (RuleConditionStrategy 注册的前缀: altitude/precipitation/season/wind_speed/
 *      wind_level/difficulty/days/diurnal_range/humidity/uv_level/is_*), 留着等于
 *      让用户以为"调了有用" → 一并删掉, 并在卡片注里写明不参与.
 *   ③ 汉字不进等宽 (见 [[qml-monofont-no-cjk]]). 只有编号、"N ITEMS"、度数与 kg/g 走 monoFont.
 *   ④ 不给假入口. 基础库条目不可删 → 删除方块直接不出现 (旧版是 enabled:false + 0.3 透明),
 *      左滑手势撤掉, 所有动作都在行内看得见.
 *
 * 2026-10-20 顺带修掉的三处旧病:
 *   - 输入卡片被限高 40% 内部滚动, "生成"按钮与下方清单挤在同一屏里够不到 (#36).
 *     现在整页只有一个滚动方向: 表单在 ScrollView 内滚, 底栏常驻.
 *   - 三个 Dialog 的 ComboBox + CheckBox 换成文字 chip, 弹层按钮走自定义 footer,
 *     不再出现英文 OK/Cancel (#41).
 *   - 装备库的类别是英文键 (rescue/protection/...), 旧版只映射成图标、从不显示;
 *     现在按中文类别分组并把键译显示出来 (#37 同类).
 */

// delegate 里要读 equipmentPage 的方法与状态, qmlcachegen 静态编译下必须 Bound,
// 否则真机静默 ReferenceError (见 [[qml-delegate-outer-id-pragma]]).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: equipmentPage

    Styles { id: styles; visible: false }

    title: "装备清单"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 视图: 0 生成 / 1 我的清单 / 2 装备库 ==============================
    property int view: 0

    // === 生成器表单 (字段顺序与 EquipmentService::generateList 读键顺序同源) ===
    property int altMax: 1500
    property int days: 2
    property int difficulty: 2          // 1-5
    property int seasonIndex: 1         // 0春 1夏 2秋 3冬
    property int precipIndex: 0         // 0无 1小 2中 3大 4暴 (冬 = 雪)
    property int humidityIndex: 1       // 0干 1中 2湿
    property int uvLevelIndex: 2        // 0弱 1中 2强 3很强 4极强
    property int windLevelIndex: 1      // 0静 1微 2中 3大 4强
    property int diurnalRange: 10       // °C, 规则阈值 15 / 20
    property bool isRainySeason: false
    property bool isDesert: false
    property bool isCoastal: false

    // === 2026-10-22: 背负方式 (轻装 / 重装) ================================
    // 档位序数与 EquipmentService.h LoadStyle 一一对应 (0 轻装一日 … 3 多日重装).
    // loadFollowTrip 为真时按天数/难度推, 推断式必须与引擎 generateList 里那段
    // 保持一致 (EquipmentService.cpp "params.days >= 3 ? Expedition : ..."),
    // 否则表单显示的档位和真正送进规则的档位会打架.
    property int loadIndex: 2
    property bool loadFollowTrip: true
    readonly property int loadAuto: days >= 3 ? 3
                                    : (days >= 2 ? 2 : (difficulty >= 4 ? 1 : 0))
    readonly property int loadEffective: loadFollowTrip ? loadAuto : loadIndex
    readonly property var loadNames: ["轻装一日", "单日强度", "过夜重装", "多日重装"]

    // === 2026-10-29: 天气来源 (手填 / 往年推演 / 当前天气预报) ==============
    // 1 与 2 都是"自动档": 读数写回下面那五排 chip; 用户手改任意一档即切回手填
    // (保留刚填进来的值当起点), 不搞"看起来自动其实被覆盖"的隐藏态.
    // 2 是在线预报 (#154 落的服务层, 这一轮才接上页面): 只要拿不到能用的数
    // (没定位 / 没网 / 缓存太旧 / 这一天空), 就**自动降到 1 的推演读数**并把原因
    // 写在读数下面 —— 环境条件这一整块不允许空白, 也不允许"预报"两个字挂着一份空数.
    property int weatherSource: 1       // 0 手填 / 1 往年推演 / 2 当前天气预报
    property string climateProvince: "" // 空 = 还没选 (表里 34 省, 见 climate_normals.json)
    property int climateMonth: new Date().getMonth() + 1
    property var climateRead: ({})      // equipmentService.climateFor 的原样返回
    readonly property bool hasClimate: climateRead.tempAvg !== undefined
    property var forecastRead: ({})     // weatherService.forecastFor 的原样返回
    readonly property bool hasForecast: forecastRead.tempAvg !== undefined
    // 来源句与降级原因一律**赋值**、不做绑定 (#111 两条 binding loop 的同一条教训)
    property string forecastSrcLine: ""
    property string forecastFailLine: ""
    readonly property bool hasEnv: hasForecast || hasClimate
    // 读数条与雪/雨折档只看这一份: 预报优先, 拿不到就是推演. 两边引擎侧键同名
    // (WeatherForecastService 头注写明了), 所以页面只写一套折档.
    readonly property var envRead: hasForecast ? forecastRead : climateRead
    /// 缓存超过 12 小时就不当"今天的天气"用 (服务的复用窗口是 30 分钟)
    readonly property int forecastMaxAgeMinutes: 720

    // 2026-10-23 (#111) 真机 stage0.log 两条告警是同一个环:
    //   EquipmentPage.qml:46 (根对象) Binding loop detected for property "climateSrcLine"
    //   读数条那条 QQuickText     Binding loop detected for property "text"
    // 它原来是个 readonly 块绑定, 读 climateRead + climateMonth, 唯一消费者是下面
    // climateReadout 里的 Text.text. 自指路径 (求值 → 写回 → 再求值):
    //   climateSrcLine 求值 → Text.text 被写 → QQuickText 尺寸变
    //   → climateReadout (anchors.fill: parent) 重算 → Rectangle.implicitHeight
    //   → 外层布局把高度发回 Rectangle → anchors.fill 把尺寸发给 climateReadout
    //   → 同一条 Text 的排版重来 → climateSrcLine 在同一批次里被重入 → 两条一起报.
    // 这一处先把"绑定"这条边拆掉: 整句只在 applyClimate() (climateRead 的唯一写者)
    // 里拼好并 **赋值**, 属性上没有绑定, 结构上就不可能再被重入. 另一半 (anchors.fill
    // ↔ implicitHeight 的高度环) 在 climateReadout 那块单独断, 两条边都断环才真的没有.
    // 汉字不进等宽 (规则 ③): 这句里全是汉字与数字, 消费者用默认字族.
    property string climateSrcLine: ""

    // Precipitation 枚举 (EquipmentService.h) 的显示名: 1-4 雨, 5-8 雪.
    // 这里只是把引擎算出来的档位翻成人话, 不参与判定.
    readonly property var precipNames: ["无降水", "小雨", "中雨", "大雨", "暴雨",
                                        "小雪", "中雪", "大雪", "暴雪"]
    readonly property var humidityNames: ["干燥", "适中", "闷热"]
    // 读数条要把引擎算出的等级翻回成人话, 而下面那两排 chip 就是同一份档位 ——
    // 两处必须用同一个数组, 否则"显示强、发出去是中等"这种错就藏在两份字面量里.
    readonly property var uvLevelNames: ["弱", "中等", "强", "很强", "极强"]
    readonly property var windLevelNames: ["静风", "微风", "中等", "大风", "强风"]

    readonly property var provinceChoices: {
        if (!equipmentService) return []
        var n = equipmentService.climateProvinceNames()
        return n ? n : []
    }
    readonly property int climateTotal: provinceChoices.length

    /**
     * 2026-10-23 (#111): 来源句的唯一生产者. 读数与月份都从**入参**取, 函数内不读
     * 页面状态, 更不读 climateSrcLine 自己 —— 这样它只能被 applyClimate 调一次,
     * 不存在"绑定时读到自己"的自指.
     */
    function composeClimateSrcLine(c, month) {
        climateSrcLine = (c.climateProvince || "") + " · " + month + " 月 @"
                + c.climateAltitudeM + " m (代表站 " + c.climateRefAltitudeM
                + " m, 温度修正 " + c.climateCorrectC + " ℃)"
    }

    /**
     * 自动档: 把往年读数**写回下面那五排 chip**, 而不是另起一条参数通道 ——
     * 表单显示的就是真正送进引擎的, 用户一眼能看见"它替我填成了什么",
     * 手改任意一档 (onClicked 里 weatherSource = 0) 即转手填, 不留隐藏态.
     *
     * 2026-10-23 (#111): climateSrcLine 不再是绑定, 所以三个出口都要自己把它落定,
     * 且要**先写来源句再写 climateRead** —— climateRead 一落, hasClimate 立刻把读数条
     * 显出来并触发一轮布局, 那一刻 Text 读到的必须是新省份的句子, 不能是上一次的.
     *
     * 2026-10-29 (#155): 返回"有没有读到数" —— 预报档拿不到时要靠这个决定降不降级.
     */
    function applyClimate() {
        if (weatherSource === 0 || !equipmentService || climateProvince.length === 0) {
            climateSrcLine = ""
            climateRead = ({})
            return false
        }
        var r = equipmentService.climateFor(climateProvince, climateMonth, altMax)
        if (!r || r.tempAvg === undefined) {
            climateSrcLine = ""
            climateRead = ({})
            return false
        }
        composeClimateSrcLine(r, climateMonth)
        climateRead = r
        applyEnvRead(r)
        return true
    }

    /**
     * 2026-10-29: 五排 chip 的写回从 applyClimate 里拆出来共用 —— 预报与推演的
     * 引擎侧键同名 (tempAvg/precipitation/uvLevel/...), 折档逻辑不该抄第二遍.
     * 枚举 1-4 是雨, 5-8 是雪; 表单那一排只有 4 档, 雪档折回同位 (冬=降雪).
     */
    function applyEnvRead(r) {
        seasonIndex = r.season
        precipIndex = r.precipitation > 4 ? r.precipitation - 4 : r.precipitation
        humidityIndex = r.humidity
        uvLevelIndex = r.uvLevel
        windLevelIndex = r.windLevel
        diurnalRange = r.diurnalRange
        isRainySeason = r.isRainySeason
    }

    /// 今天这一日 (open-meteo 按日期给, 键就是 ISO 日) —— 用本地日, 不用 toISOString (UTC)
    function forecastDayIso() {
        var d = new Date()
        var p2 = function(n) { return n < 10 ? "0" + n : "" + n }
        return d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(d.getDate())
    }

    /**
     * 发请求. 只在"切到预报档"和"改了海拔"两处调, 不在读数回调里调 ——
     * 30 分钟内命中缓存时 refresh 会**当场** emit forecastUpdated, 回调里再发一次
     * 请求就是自己转自己.
     */
    function pullForecast() {
        if (weatherSource !== 2 || !weatherService) return
        if (!emergencyService || !emergencyService.hasLocation) return
        weatherService.refresh(emergencyService.currentLatitude,
                               emergencyService.currentLongitude, altMax)
    }

    /// 只读已拿回来的数 (缓存或刚拉到的), 不发请求; 返回有没有可用的读数
    function readForecast() {
        forecastRead = ({})
        forecastSrcLine = ""
        if (!weatherService) {
            forecastFailLine = "天气预报服务还没就绪 · 检查 ServiceRegistry 是否注册 weatherService"
            return false
        }
        if (!emergencyService || !emergencyService.hasLocation) {
            forecastFailLine = "现在没有定位: 预报要经纬度才能问, 先去①营地或地图页拿到定位"
            return false
        }
        var f = weatherService.forecastFor(forecastDayIso())
        if (!f || f.tempAvg === undefined) {
            forecastFailLine = "今天这一天的预报读不到 (还没拉到或离线)"
            return false
        }
        if (f.ageMinutes !== undefined && f.ageMinutes > forecastMaxAgeMinutes) {
            forecastFailLine = "这份预报是 " + Math.round(f.ageMinutes / 60) + " 小时前的, 太旧"
            return false
        }
        forecastFailLine = ""
        composeForecastSrcLine(f)
        forecastRead = f
        applyEnvRead(f)
        return true
    }

    /**
     * 预报的来源句: 日期 + 多旧 + 有没有做海拔修正.
     * 「不给假读数」在这里的具体形状: ageMinutes 缺就不写"刚刚", 修正海拔缺就直说"未做".
     */
    function composeForecastSrcLine(f) {
        var parts = ["预报 " + (f.forecastDate || forecastDayIso())]
        // ageMinutes 的 -1 是服务侧"抓取时刻丢了"的哨兵, 不是"负一分钟前"; 直接写会
        // 画出"抓于 -1 分钟前" —— 一个假读数, 所以这里按三态分: 未知 / 刚刚 / N 分钟前.
        if (f.ageMinutes === undefined || f.ageMinutes < 0)
            parts.push("抓取时刻未知")
        else if (f.ageMinutes < 1)
            parts.push("刚抓到")
        else
            parts.push("抓于 " + Math.round(f.ageMinutes) + " 分钟前")
        parts.push(f.forecastElevationM !== undefined
                   ? ("按 " + f.forecastElevationM + " m 修正")
                   : "未做海拔修正")
        forecastSrcLine = parts.join(" · ")
    }

    /**
     * 三源总入口 (#147/#155): 预报 → 推演 → 手填, 上一级拿不到就降一级.
     * 预报成功时**不再**跑 applyClimate —— 否则五排 chip 会被推演值盖回去.
     */
    function applyWeather() {
        if (weatherSource === 0) {
            forecastRead = ({})
            forecastSrcLine = ""
            forecastFailLine = ""
            applyClimate()
            return
        }
        if (weatherSource === 2) {
            if (readForecast()) return
            climateRead = ({})      // 清掉可能残留的上一份, 让 hasEnv 只反映推演结果
        }
        applyClimate()
    }
    onWeatherSourceChanged: {
        if (weatherSource === 2) {
            if (emergencyService) emergencyService.requestLocationUpdate()
            pullForecast()
        }
        applyWeather()
    }
    onClimateProvinceChanged: applyWeather()
    onClimateMonthChanged: applyWeather()
    onAltMaxChanged: {
        // 同一格点换海拔要重拉: 旧读数是按旧海拔修正过的, 不能当新数用
        if (weatherSource === 2) pullForecast()
        applyWeather()
    }

    Connections {
        target: weatherService
        function onForecastUpdated() { equipmentPage.applyWeather() }
        function onForecastFailed(reason) {
            equipmentPage.forecastRead = ({})
            equipmentPage.forecastSrcLine = ""
            equipmentPage.forecastFailLine = "预报拉取失败: " + reason
            equipmentPage.applyClimate()
        }
    }

    // 冬季的"降水"是雪, 不是雨. 引擎侧 precipitation 枚举 1-4 是雨、5-8 是雪
    // (EquipmentService.h Precipitation), 所以同一档位在两个季节映射到不同值:
    // 选「大雪」不会再命中"强降雨需防水"这种雨具理由, 只会命中雪规则.
    //
    // 2026-10-22 反例 (往年读数逼出来的): 海南 1 月 tempMin 15 ℃ → 季节按月份判是
    // 「冬」, 降水却是 1 (= 小雨). 若这里仍按 isWinter 把那一排 chip 换成雪档,
    // applyClimate 折回来的 index 1 会被当成「小雪」=5 送进引擎 —— 给海南一月下起雪.
    // 所以雪/雨这一族改由**读数本身**决定: 自动档看 climateRead, 手填看季节.
    // 折档 (r.precipitation>4 ? -4 : 原值) 与 precipValues 在两种族下都是精确互逆的.
    readonly property bool isWinter: seasonIndex === 3
    readonly property bool snowFamily: weatherSource !== 0 && hasEnv
                                       ? envRead.precipitation > 4
                                       : isWinter
    readonly property var precipLabels: snowFamily
                                        ? ["无", "小雪", "中雪", "大雪", "暴雪"]
                                        : ["无", "小雨", "中雨", "大雨", "暴雨"]
    readonly property var precipValues: snowFamily ? [0, 5, 6, 7, 8] : [0, 1, 2, 3, 4]

    /**
     * 读数条那六格 (#155): 预报与推演共用一份, 缺测的那一项整格不出现.
     * 原来这里是六行硬拼的字符串 —— 预报侧一个字段缺测就会把 "undefined mm"
     * 画上屏, 与「不给假读数」直接冲突, 所以改成按键是否存在决定 push.
     * 降水毫米数两边键名不同 (月表 climatePrecipMm / 日预报 forecastPrecipMm).
     */
    readonly property var envTiles: {
        if (!equipmentPage.hasEnv) return []
        var r = equipmentPage.envRead
        var mm = equipmentPage.hasForecast ? r.forecastPrecipMm : r.climatePrecipMm
        var out = []
        if (r.tempMin !== undefined) out.push(["夜温", r.tempMin + " ℃"])
        if (r.tempAvg !== undefined) out.push(["日均", r.tempAvg + " ℃"])
        if (r.precipitation !== undefined)
            out.push(["降水", equipmentPage.precipNames[r.precipitation]
                                 + (mm !== undefined ? " · " + mm + " mm" : "")])
        if (r.uvLevel !== undefined)
            out.push(["紫外线", equipmentPage.uvLevelNames[r.uvLevel]
                                 + (r.uvIndex !== undefined ? " · " + r.uvIndex : "")])
        if (r.windLevel !== undefined)
            out.push(["风", equipmentPage.windLevelNames[r.windLevel]
                                 + (r.windSpeed !== undefined ? " · " + r.windSpeed + " m/s" : "")])
        if (r.diurnalRange !== undefined) out.push(["昼夜温差", r.diurnalRange + " ℃"])
        return out
    }

    // === 数据 ==============================================================
    property var lists: []              // getAllLists().value
    property var listRows: []           // head / item 混合
    property var items: []              // 基础库 + 自定义, 已归一化
    property var itemRows: []           // head / item 混合
    property bool onlyCritical: false
    property string note: ""            // 校验/写操作反馈: 常驻可读, 不闪 toast

    // === 装备条目对话框 (新建 / 修改 / 复制副本 共用一套字段) ===============
    property string dlgMode: "add"      // add | edit | clone
    property string editItemId: ""
    property string dlgCategory: "rescue"
    property bool dlgCritical: false

    // 2026-10-22 (#84 补): 库扩到 77 件时新增了 shelter / carry / cook 三类, 这里
    // 只列了 9 类 —— 分组本身不会丢 (order 从实际数据推, categoryLabel 兜底原键),
    // 但分区标题会直接显示英文 "shelter", 新建条目的类别 chip 也选不到这三类.
    // 顺序即分组显示顺序, 营地/背负/保暖/炊具排在前面是重装清单的主线.
    readonly property var categoryKeys: ["shelter", "carry", "warmth", "cook",
                                         "water", "food", "protection", "altitude",
                                         "rescue", "light", "tools", "navigation"]
    readonly property var categoryNames: ["营地庇护", "背负", "保暖", "炊具炉料",
                                          "饮水", "食物", "防护", "高原",
                                          "急救救援", "照明", "工具", "导航"]
    readonly property var seasonNames: ["春", "夏", "秋", "冬"]

    function categoryLabel(key) {
        var i = categoryKeys.indexOf(key)
        return i >= 0 ? categoryNames[i] : (key && key.length > 0 ? String(key) : "未分类")
    }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    function fmtKg(g) {
        if (g <= 0) return "0 kg"
        return (g / 1000).toFixed(2) + " kg"
    }

    readonly property int baseCount: {
        var n = 0
        for (var i = 0; i < items.length; ++i) if (!items[i].isUser) n++
        return n
    }
    readonly property int userCount: items.length - baseCount
    readonly property int criticalCount: {
        var n = 0
        for (var i = 0; i < items.length; ++i) if (items[i].critical) n++
        return n
    }
    readonly property int doneLists: {
        var n = 0
        for (var i = 0; i < lists.length; ++i) if (lists[i].isCompleted === true) n++
        return n
    }
    readonly property int totalGrams: {
        var s = 0
        for (var i = 0; i < lists.length; ++i) s += (Number(lists[i].totalWeightG) || 0)
        return s
    }

    // === 读数行 (每个视图报自己那一档的覆盖面) =============================
    readonly property string statusLine: {
        if (view === 0) {
            if (!equipmentService) return "装备引擎还没就绪 · 检查 ServiceRegistry 是否注册 equipmentService"
            if (items.length === 0) return "装备库空 · 检查 assets/data/equipment_base.json 是否打进包里"
            // 库件数在视图 chip 上已经写着, 读数行留给"这次到底按什么生成"
            var src = equipmentPage.hasForecast
                      ? "今天预报"
                      : (weatherSource !== 0 && climateProvince.length > 0 && hasClimate
                         ? (climateProvince + " " + climateMonth + "月往年") : "天气手填")
            return altMax + " m · " + days + " 天 · 难度 " + difficulty + " · "
                   + loadNames[loadEffective] + " · "
                   + seasonNames[seasonIndex]
                   + (precipIndex > 0 ? " · " + precipLabels[precipIndex] : "")
                   + " · " + src
        }
        if (view === 1) {
            if (lists.length === 0) return "还没有生成过清单 · 切到「生成」按行程条件出一份"
            return lists.length + " 份 · 已清点 " + doneLists + " · 合计 " + fmtKg(totalGrams)
        }
        var t = baseCount + " 件基础 · " + userCount + " 件自定义 · 关键 " + criticalCount + " 件"
        return onlyCritical ? t + " · 现只列关键" : t
    }

    readonly property string kicker: view === 0 ? "装备 / 打包"
                                      : (view === 1 ? "装备 / 我的清单" : "装备 / 装备库")
    readonly property string pageTitle: view === 0 ? "装备清单"
                                        : (view === 1 ? "我的清单" : "装备库")

    // === 取数 ==============================================================
    function loadLists() {
        if (!equipmentService) { lists = []; listRows = []; return }
        // getAllLists 是 Result 包装 (Phase 5 批次 3), 失败时目录打不开要看得见
        var res = equipmentService.getAllLists()
        var arr = (res && res.ok && res.value && res.value.length !== undefined) ? res.value : []
        if (res && res.ok === false)
            equipmentPage.note = "清单目录读不出来: " + ((res.error && res.error.message) || "未知错误")
        lists = arr
        rebuildLists()
    }

    // 分组轴 = 海拔档 (L0~L6 的名字), 组内按生成时间新→旧.
    // getAllLists 遍历的是存储目录里的 *.json, 顺序跟着文件系统走, 不排就会跳.
    function rebuildLists() {
        var bucket = ({})
        var order = []
        for (var i = 0; i < lists.length; ++i) {
            var l = lists[i]
            var lv = Number(l.altitudeLevel) || 0
            var key = String(lv)
            if (!bucket[key]) {
                bucket[key] = []
                order.push({ lv: lv, label: String(l.altitudeLevelName || "未标注档位") })
            }
            bucket[key].push({
                kind: "item",
                itemId: String(l.id || ""),
                name: String(l.name || "未命名清单"),
                level: lv,
                altMax: Number(l.altitudeMax) || 0,
                grams: Number(l.totalWeightG) || 0,
                checked: Number(l.checkedCount) || 0,
                completed: l.isCompleted === true,
                created: String(l.createdAt || ""),
                label: "", count: 0
            })
        }
        order.sort(function (a, b) { return a.lv - b.lv })
        var out = []
        for (var g = 0; g < order.length; ++g) {
            var members = bucket[String(order[g].lv)]
            members.sort(function (a, b) {
                if (a.created === b.created) return a.name < b.name ? -1 : 1
                return a.created < b.created ? 1 : -1
            })
            // 两类行必须同键: delegate 里的绑定一律会求值 (`visible: false` 不拦绑定),
            // 少一个键真机上就是 "Unable to assign [undefined] to QString/bool/int"。
            out.push({
                kind: "head", label: order[g].label, count: members.length, level: order[g].lv,
                itemId: "", name: "", altMax: 0, grams: 0, checked: 0,
                completed: false, created: ""
            })
            for (var m = 0; m < members.length; ++m) out.push(members[m])
        }
        listRows = out
    }

    function loadItems() {
        if (!equipmentService) { items = []; itemRows = []; return }
        // getAllItems / getUserItems 返回裸 QVariantList (无 Result 包装)
        var base = equipmentService.getAllItems()
        var user = equipmentService.getUserItems()
        var all = []
        var b
        for (b = 0; b < base.length; ++b) all.push(normItem(base[b], false))
        for (b = 0; b < user.length; ++b) all.push(normItem(user[b], true))
        items = all
        rebuildItems()
    }

    function normItem(raw, isUser) {
        return {
            itemId: String(raw.id || ""),
            name: String(raw.name || "未命名装备"),
            category: String(raw.category || ""),
            grams: Number(raw.weightG) || 0,
            critical: raw.isCritical === true,
            isUser: isUser
        }
    }

    // 分组轴 = 类别 (按 equipment_base.json 的 categories 序, 未知类别排最后)
    function rebuildItems() {
        var bucket = ({})
        var order = []
        for (var i = 0; i < items.length; ++i) {
            var it = items[i]
            if (onlyCritical && !it.critical) continue
            var cat = it.category
            if (!bucket[cat]) { bucket[cat] = []; order.push(cat) }
            bucket[cat].push({
                kind: "item",
                itemId: it.itemId,
                name: it.name,
                catKey: cat,
                catLabel: categoryLabel(cat),
                grams: it.grams,
                critical: it.critical,
                isUser: it.isUser,
                plate: CommonOptions.plateCode("GB", it.itemId),
                label: "", count: 0
            })
        }
        order.sort(function (a, b) {
            var ia = categoryKeys.indexOf(a)
            var ib = categoryKeys.indexOf(b)
            if (ia < 0) ia = 999
            if (ib < 0) ib = 999
            return ia - ib
        })
        var out = []
        for (var g = 0; g < order.length; ++g) {
            var members = bucket[order[g]]
            members.sort(function (a, b) {
                if (a.grams !== b.grams) return a.grams - b.grams
                return a.name < b.name ? -1 : 1
            })
            out.push({
                kind: "head", label: categoryLabel(order[g]), count: members.length,
                itemId: "", name: "", catKey: order[g], catLabel: "", grams: 0,
                critical: false, isUser: false, plate: ""
            })
            for (var m = 0; m < members.length; ++m) out.push(members[m])
        }
        itemRows = out
    }

    function refreshAll() {
        loadLists()
        loadItems()
    }

    Component.onCompleted: {
        refreshAll()
        // 下拉框显示的是第 0 项, 状态也得是第 0 项, 否则"看着选了四川其实没选"
        if (climateProvince.length === 0 && provinceChoices.length > 0)
            climateProvince = provinceChoices[0]
        // 环境条件现在有三个来源, 首屏也要走三源总入口, 不能只灌往年表
        applyWeather()
    }

    // 写操作 (addUserItem / updateUserItem / deleteUserItem / saveList / deleteList)
    // 在 C++ 侧都会发 dataChanged 或 list* → 一律靠信号回表, 不在调用处手动刷,
    // 否则一次点击刷两遍.
    Connections {
        target: equipmentService
        function onDataChanged() { equipmentPage.refreshAll() }
        function onListGenerated(listId) { equipmentPage.loadLists() }
        function onListCompleted(listId) { equipmentPage.loadLists() }
        // 重命名/勾选走 saveList → listModified, 之前这里没接, 改完名不回表
        function onListModified(listId) { equipmentPage.loadLists() }
    }
    onOnlyCriticalChanged: rebuildItems()

    // === 生成 ==============================================================
    // 海拔/天数输入直接改写页面状态 (字段 text 不做绑定, 避免与 resetForm 的
    // 一次性赋值互相回写).
    function autoName() {
        if (nameField.text.length === 0) {
            nameField.placeholderText = equipmentPage.altMax > 0
                    ? ("留空自动命名: 海拔" + equipmentPage.altMax + "m·" + equipmentPage.days + "天")
                    : "清单名称 (留空自动命名)"
        }
    }

    function resetForm() {
        altMaxField.text = "1500"
        daysField.text = "2"
        equipmentPage.altMax = 1500
        equipmentPage.days = 2
        equipmentPage.difficulty = 2
        equipmentPage.seasonIndex = 1
        equipmentPage.precipIndex = 0
        equipmentPage.humidityIndex = 1
        equipmentPage.uvLevelIndex = 2
        equipmentPage.windLevelIndex = 1
        equipmentPage.diurnalRange = 10
        equipmentPage.isRainySeason = false
        equipmentPage.isDesert = false
        equipmentPage.isCoastal = false
        equipmentPage.loadIndex = 2
        equipmentPage.loadFollowTrip = true
        equipmentPage.weatherSource = 1
        equipmentPage.climateProvince = ""
        equipmentPage.climateMonth = new Date().getMonth() + 1
        // 2026-10-23 (#111): 这里原来直接 climateRead = ({}) 把读数清空, 而来源句
        // (climateSrcLine) 现在是赋值不是绑定, 少一次调用就会把上一个省份的句子留在
        // 属性上. 改调 applyClimate(): 省份为空走第一条分支, 读数与来源句一起归零.
        // 2026-10-29 (#155): 换成 applyWeather() —— 预报那一源的读数与两句说明
        // (forecastRead / forecastSrcLine / forecastFailLine) 也要在这里一起归零,
        // 否则重置完"手填"档上还能看见上一份预报的数字.
        equipmentPage.applyWeather()
        nameField.text = ""
        nameField.placeholderText = "清单名称 (留空自动命名)"
        equipmentPage.note = ""
    }

    function generateList() {
        var altMax = equipmentPage.altMax
        var days = equipmentPage.days
        if (altMax <= 0) { equipmentPage.note = "最高海拔要大于 0 米"; return }
        if (days <= 0) { equipmentPage.note = "行程天数要至少 1 天"; return }
        if (!equipmentService) { equipmentPage.note = "装备引擎还没就绪, 重启后再试"; return }

        var listName = nameField.text.trim()
        if (listName.length === 0) listName = "海拔" + altMax + "m·" + days + "天"

        // 风力等级同时反推一个代表风速: 规则里 wind_speed>=8 与 wind_level in
        // [strong,gale] 是两条, 只发等级会漏掉前者.
        var windSpeedByLevel = [0.2, 2.0, 5.0, 9.0, 15.0]
        var params = {
            "altitudeMax": altMax,
            "altitudeMin": Math.max(0, altMax - 500),
            "altitudeCamp": Math.max(0, altMax - 200),
            "days": days,
            "difficulty": equipmentPage.difficulty,
            "season": equipmentPage.seasonIndex,
            "windSpeed": windSpeedByLevel[equipmentPage.windLevelIndex] || 0.0,
            "precipitation": equipmentPage.precipValues[equipmentPage.precipIndex],
            "diurnalRange": equipmentPage.diurnalRange,
            "humidity": equipmentPage.humidityIndex,
            "uvLevel": equipmentPage.uvLevelIndex,
            "windLevel": equipmentPage.windLevelIndex,
            "isRainySeason": equipmentPage.isRainySeason,
            "isDesert": equipmentPage.isDesert,
            "isCoastal": equipmentPage.isCoastal
        }

        // 背负方式: 跟随行程时发的就是引擎自己会推出的那一档; 显式发出去是为了
        // 关掉跟随之后表单选的值真的说了算 (引擎里 load 缺省才走推断).
        params["load"] = equipmentPage.loadEffective

        // 天气来源: 「往年」与「预报」两档下温度/风速/紫外线的具体数值都在读数里
        // (那五排 chip 只有档位), 等级已由 applyClimate/applyForecast 写回 chip,
        // 引擎再按数值核一遍等级 —— 阈值只有一份 (EquipmentService 的换算函数).
        // 2026-10-29 (#147/#155): 三源里两个自动档共用同一套键名 (WeatherForecastService
        // 头注写明了"与 climateFor 同名同语义"), 所以这里不再按来源分支, 只判有没有读数.
        if (equipmentPage.weatherSource !== 0) {
            if (!equipmentPage.hasEnv) {
                // 不静默退回手填: 用户选的是自动档, 拿不到就不生成
                equipmentPage.note = equipmentPage.weatherSource === 2
                        ? ("预报和往年都没取到数: " + (equipmentPage.forecastFailLine || "原因未知")
                           + " · 切「往年推演」要先挑地点, 或改「手填」自己定档。")
                        : "往年天气还没取到: 先挑地点; 这一带不在 34 省表里就切回「手填」。"
                return
            }
            var c = equipmentPage.envRead
            params["tempAvg"] = c.tempAvg
            params["tempMin"] = c.tempMin
            if (c.windSpeed !== undefined) params["windSpeed"] = c.windSpeed
            if (c.uvIndex !== undefined) params["uvIndex"] = c.uvIndex
        }

        var result = equipmentService.generateList(listName, params)
        if (!result || !result.id) {
            equipmentPage.note = "生成没有成功: 规则可能一条没命中, 或清单没能写进存储"
            return
        }
        equipmentPage.note = ""
        navigateTo("EquipmentDetailPage", { listId: String(result.id) })
    }

    // === 条目写操作 ========================================================
    function openItemDialog(mode, seed) {
        var s = seed || ({})
        equipmentPage.dlgMode = mode
        equipmentPage.editItemId = String(s.itemId || "")
        equipmentPage.dlgCategory = s.category ? String(s.category) : "rescue"
        equipmentPage.dlgCritical = s.critical === true
        itemNameText.text = (s.name ? String(s.name) : "") + (mode === "clone" ? " (副本)" : "")
        itemWeightText.text = String(s.grams !== undefined ? s.grams : 100)
        equipmentPage.note = ""
        itemDialog.open()
    }

    function acceptItemDialog() {
        if (!equipmentService) { equipmentPage.note = "装备引擎还没就绪"; return }
        var nm = itemNameText.text.trim()
        if (nm.length === 0) { equipmentPage.note = "装备名称不能为空"; return }
        var g = parseInt(itemWeightText.text) || 0
        var r
        if (equipmentPage.dlgMode === "edit" && equipmentPage.editItemId.length > 0) {
            r = equipmentService.updateUserItem(equipmentPage.editItemId, nm,
                                                equipmentPage.dlgCategory, g,
                                                equipmentPage.dlgCritical)
        } else {
            r = equipmentService.addUserItem(nm, equipmentPage.dlgCategory, g,
                                             equipmentPage.dlgCritical)
        }
        if (r && r.ok === false) {
            equipmentPage.note = ((r.error && r.error.message) || "保存失败")
                    + " · 名称「" + nm + "」没有写进库"
            return
        }
        equipmentPage.note = ""   // 回表由 dataChanged 触发
    }

    function deleteItem(itemId) {
        if (!equipmentService || itemId.length === 0) return
        var r = equipmentService.deleteUserItem(itemId)
        if (r && r.ok === false)
            equipmentPage.note = "删除失败: " + ((r.error && r.error.message) || "未知错误")
    }

    function deleteList(listId, listName) {
        if (!equipmentService || listId.length === 0) return
        var r = equipmentService.deleteList(listId)
        if (r && r.ok === false)
            equipmentPage.note = "删除清单失败: " + ((r.error && r.error.message) || "未知错误")
    }

    function renameList(listId, newName) {
        if (!equipmentService || listId.length === 0 || newName.length === 0) return
        var old = equipmentService.getList(listId)
        if (!old || !old.id) { equipmentPage.note = "这份清单读不到了, 可能已被删除"; return }
        old.name = newName
        var r = equipmentService.modifyList(listId, old)
        if (r && r.ok === false)
            equipmentPage.note = "重命名失败: " + ((r.error && r.error.message) || "未知错误")
    }

    // 行内动作方块: 32px 面 + 外扩 6px 热区 = 44px (touchMin).
    // 内联组件看不到外层 styles id, 自带一个 (与 Chip.qml 同构).
    component ActionCell: Rectangle {
        id: cell
        property string iconName: ""
        property color tone: CommonOptions.colorText
        signal clicked()

        Styles { id: cellStyles; visible: false }

        implicitWidth: 32
        implicitHeight: 32
        radius: cellStyles.rSm
        color: CommonOptions.colorSurface
        border.color: CommonOptions.colorRule
        border.width: cellStyles.lineHair

        IconLabel {
            anchors.centerIn: parent
            name: cell.iconName
            size: cellStyles.icSm
            tintColor: cell.tone
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            enabled: cell.enabled
            cursorShape: cell.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: cell.clicked()
        }
    }

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- 标题条 (54px: 微标签 / 视图名 / 读数行, 右上 26px 方角返回) ---
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 40      // 给右上角方角让位
                spacing: 3
                Text {
                    text: equipmentPage.kicker
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsXs
                    font.letterSpacing: 1.8
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: equipmentPage.pageTitle
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: equipmentPage.statusLine
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: styles.spXs
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
                    onClicked: equipmentPage.goBack()
                }
            }
        }

        // --- 视图切换 (三枚 chip 一行, 带条数) ---
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            spacing: styles.spXs

            Repeater {
                model: ["生成", "我的清单 " + equipmentPage.lists.length,
                        "装备库 " + equipmentPage.items.length]
                delegate: Chip {
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData
                    checked: index === equipmentPage.view
                    accent: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: equipmentPage.view = index
                }
            }
        }

        // --- 反馈行: 校验/写操作失败常驻在这里, 视图间不丢 ---
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spXs
            visible: equipmentPage.note.length > 0
            text: equipmentPage.note
            font.pixelSize: styles.fsXs
            color: CommonOptions.colorLegendAmber
            wrapMode: Text.WordWrap
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: styles.bottomClearance   // A41: 末行给下面的吸底条让位
            currentIndex: equipmentPage.view

            // ============================================================
            // 视图 0: 生成器
            // ============================================================
            ScrollView {
                contentWidth: width
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: styles.pageGap

                    // --- 行程卡 ---
                    Card {
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        Layout.topMargin: styles.spSm
                        spacing: styles.spSm

                        SectionTitle {
                            Layout.fillWidth: true
                            icon: "note_add"
                            text: "行程条件"
                            pixelSize: styles.fsLg
                        }

                        TextField {
                            id: nameField
                            Layout.fillWidth: true
                            Layout.preferredHeight: styles.fieldH
                            placeholderText: "清单名称 (留空自动命名)"
                            placeholderTextColor: CommonOptions.colorTextDim
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsMd
                            leftPadding: styles.spSm
                            rightPadding: styles.spSm
                            topPadding: 0
                            bottomPadding: 0
                            background: Rectangle {
                                color: nameField.activeFocus
                                       ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                                border.color: nameField.activeFocus
                                              ? CommonOptions.colorText : CommonOptions.colorRule
                                border.width: styles.lineHair
                                radius: styles.rSm
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spSm

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    text: "最高海拔 (m)"
                                    color: CommonOptions.colorInk3
                                    font.pixelSize: styles.fsXs
                                }
                                TextField {
                                    id: altMaxField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: styles.btnH
                                    text: "1500"
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    color: CommonOptions.colorText
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsMd
                                    leftPadding: styles.spSm
                                    rightPadding: styles.spSm
                                    topPadding: 0
                                    bottomPadding: 0
                                    onTextChanged: {
                                        equipmentPage.altMax = parseInt(text) || 0
                                        equipmentPage.autoName()
                                    }
                                    background: Rectangle {
                                        color: altMaxField.activeFocus
                                               ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                                        border.color: altMaxField.activeFocus
                                                      ? CommonOptions.colorText : CommonOptions.colorRule
                                        border.width: styles.lineHair
                                        radius: styles.rSm
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    text: "行程天数"
                                    color: CommonOptions.colorInk3
                                    font.pixelSize: styles.fsXs
                                }
                                TextField {
                                    id: daysField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: styles.btnH
                                    text: "2"
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    color: CommonOptions.colorText
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsMd
                                    leftPadding: styles.spSm
                                    rightPadding: styles.spSm
                                    topPadding: 0
                                    bottomPadding: 0
                                    onTextChanged: {
                                        equipmentPage.days = parseInt(text) || 0
                                        equipmentPage.autoName()
                                    }
                                    background: Rectangle {
                                        color: daysField.activeFocus
                                               ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                                        border.color: daysField.activeFocus
                                                      ? CommonOptions.colorText : CommonOptions.colorRule
                                        border.width: styles.lineHair
                                        radius: styles.rSm
                                    }
                                }
                            }
                        }

                        // 难度: 单选 chip, 选中那枚染难度色 (与路线目录的 3px 条同源)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "难度"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: [1, 2, 3, 4, 5]
                                delegate: Chip {
                                    required property int modelData
                                    Layout.fillWidth: true
                                    text: modelData + " 星"
                                    checked: equipmentPage.difficulty === modelData
                                    accent: CommonOptions.difficultyColor(modelData)
                                    textSize: styles.fsXs
                                    onClicked: equipmentPage.difficulty = modelData
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: CommonOptions.difficultyLabel(equipmentPage.difficulty)
                                  + " · 规则按「该星及以上」触发 (4 星与 5 星各一条附加)"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                            wrapMode: Text.WordWrap
                        }

                        // --- 背负方式 (2026-10-22 新增块, 左侧 3px 橙条标出) ---
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: styles.spMd
                            spacing: styles.spXs

                            Rectangle {
                                Layout.fillHeight: true
                                Layout.preferredWidth: styles.lineAccent
                                color: CommonOptions.colorBlaze
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: styles.spXs

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: styles.spXs
                                    Text {
                                        Layout.preferredWidth: 56
                                        text: "背负"
                                        color: CommonOptions.colorInk3
                                        font.pixelSize: styles.fsXs
                                    }
                                    Repeater {
                                        model: equipmentPage.loadNames
                                        delegate: Chip {
                                            required property int index
                                            required property var modelData
                                            Layout.fillWidth: true
                                            text: modelData
                                            checked: equipmentPage.loadEffective === index
                                            accent: CommonOptions.colorAccent
                                            textSize: styles.fsXs
                                            onClicked: {
                                                equipmentPage.loadFollowTrip = false
                                                equipmentPage.loadIndex = index
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: styles.spXs
                                    Item { Layout.preferredWidth: 56 }
                                    Chip {
                                        text: "跟随行程"
                                        checked: equipmentPage.loadFollowTrip
                                        accent: CommonOptions.colorTealDeep
                                        textSize: styles.fsXs
                                        onClicked: equipmentPage.loadFollowTrip =
                                                   !equipmentPage.loadFollowTrip
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: equipmentPage.loadFollowTrip
                                              ? (equipmentPage.days + " 天 / 难度 "
                                                 + equipmentPage.difficulty + " → 自动这档")
                                              : "已手动定档"
                                        font.pixelSize: styles.fsXs
                                        color: CommonOptions.colorInk3
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "不过夜就不背包里的帐篷睡袋 —— 这一档改的是"
                                          + "帐篷 / 睡袋 / 炉具 / 氧气进不进绝对必带。"
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorInk3
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    // --- 环境卡 ---
                    Card {
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        spacing: styles.spSm

                        SectionTitle {
                            Layout.fillWidth: true
                            icon: "equalizer"
                            text: "环境条件"
                            pixelSize: styles.fsLg
                        }

                        // --- 天气来源 (2026-10-22 新增块, 3px 橙条标出) -------
                        // 「往年」档下这五排 chip 不是给用户瞎填的: 它显示的是
                        // climateFor 替这条路线填出来的档位 (applyClimate 写回),
                        // 手改任意一档即切回「手填」, 不留"看着自动其实被覆盖"的态.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: styles.spMd
                            spacing: styles.spXs

                            Rectangle {
                                Layout.fillHeight: true
                                Layout.preferredWidth: styles.lineAccent
                                color: CommonOptions.colorBlaze
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: styles.spSm

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: styles.btnHSm
                                    spacing: 0

                                    Repeater {
                                        model: ["手填", "往年推演", "当前天气预报"]
                                        delegate: Rectangle {
                                            required property int index
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: styles.btnHSm
                                            border.width: styles.lineHair
                                            border.color: CommonOptions.colorText
                                            color: equipmentPage.weatherSource === index
                                                   ? CommonOptions.colorText
                                                   : CommonOptions.colorSurface
                                            // 相邻两枚之间只画一条线: 后一枚盖掉自己的左边
                                            Layout.leftMargin: index > 0 ? -styles.lineHair : 0
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.pixelSize: styles.fsSm
                                                font.bold: equipmentPage.weatherSource === index
                                                color: equipmentPage.weatherSource === index
                                                       ? CommonOptions.colorTextOnAccent
                                                       : CommonOptions.colorTextMuted
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: equipmentPage.weatherSource = index
                                            }
                                        }
                                    }
                                }

                                FilterRow {
                                    Layout.fillWidth: true
                                    label: "地点"
                                    labelWidth: 56
                                    comboModel: equipmentPage.provinceChoices
                                    comboCurrentIndex: Math.max(
                                        0, equipmentPage.provinceChoices.indexOf(
                                               equipmentPage.climateProvince))
                                    // 2026-10-29 (#155): 预报档也要能改 —— 预报取不到时
                                    // 落回的就是这一份往年读数, 锁住等于把降级的那条路也锁了.
                                    enabled: equipmentPage.weatherSource !== 0
                                    onComboActivated: (i, v) => {
                                        equipmentPage.climateProvince = String(v)
                                    }
                                }

                                FilterRow {
                                    Layout.fillWidth: true
                                    label: "月份"
                                    labelWidth: 56
                                    stepperValue: equipmentPage.climateMonth + " 月 · "
                                                  + equipmentPage.seasonNames[
                                                        (equipmentPage.climateMonth >= 3
                                                         && equipmentPage.climateMonth <= 5) ? 0
                                                        : (equipmentPage.climateMonth <= 8 ? 1
                                                           : (equipmentPage.climateMonth <= 11 ? 2 : 3))]
                                    stepperMinusEnabled: equipmentPage.weatherSource !== 0
                                    stepperPlusEnabled: equipmentPage.weatherSource !== 0
                                    onStepperMinus: equipmentPage.climateMonth =
                                            equipmentPage.climateMonth <= 1
                                            ? 12 : equipmentPage.climateMonth - 1
                                    onStepperPlus: equipmentPage.climateMonth =
                                            equipmentPage.climateMonth >= 12
                                            ? 1 : equipmentPage.climateMonth + 1
                                }

                                // 读数条: 自动档下"它替我填成了什么"全在这一块
                                Rectangle {
                                    Layout.fillWidth: true
                                    // 这块必须有 implicitHeight: 里面的 ColumnLayout 不再
                                    // anchors.fill 父项, 不写这条就是 0 高, 读数会溢出压住
                                    // 后面的行 (layout_collapse_check 命中项, 也是"清单页
                                    // 布局差"的真因). 撑高度的子项必须**不锚底边**, 见下面
                                    // climateReadout 的 #111 注.
                                    implicitHeight: climateReadout.implicitHeight + 2 * styles.spSm
                                    visible: equipmentPage.hasEnv
                                    border.width: styles.lineHair
                                    border.color: CommonOptions.colorText
                                    color: CommonOptions.colorSurfaceDim

                                    ColumnLayout {
                                        id: climateReadout
                                        // 2026-10-23 (#111): 原来是 anchors.fill: parent ——
                                        // 那是一条闭合的高度自指环:
                                        //   Rectangle.implicitHeight ← climateReadout.implicitHeight
                                        //   → Rectangle.height (外层 ColumnLayout 按 implicitHeight
                                        //     给它发行高) → climateReadout 被 anchors.fill 拉成
                                        //     父项高度 → 布局重排子项 → climateReadout.implicitHeight
                                        //   → 回到第一行.
                                        // 环里每一次重排都要重发那条 Text.text (绑的是
                                        // equipmentPage.climateSrcLine), 于是 Qt 在同一批次里
                                        // 重入它, 真机就是这条 QQuickText 报
                                        // "Binding loop detected for property text".
                                        // 改法照抄 PositionReadout.qml:76-82 那个已评审的写法:
                                        // 只锚左/右/顶, 不锚底 —— 布局高度由它自己的
                                        // implicitHeight 决定, 父项高度由它撑, 单向依赖.
                                        // Card.qml 头注早就把 fill + implicitHeight 列为禁忌.
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: styles.spSm
                                        spacing: styles.spXs

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: styles.spSm
                                            Text {
                                                Layout.fillWidth: true
                                                text: equipmentPage.hasForecast ? "今天预报" : "往年这个时候"
                                                color: CommonOptions.colorText
                                                font.pixelSize: styles.fsSm
                                                font.bold: true
                                            }
                                            Text {
                                                text: equipmentPage.hasForecast ? "逐日预报" : "常年值"
                                                font.pixelSize: styles.fsXs
                                                color: CommonOptions.colorInk3
                                            }
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 3
                                            rowSpacing: styles.spXs
                                            columnSpacing: styles.spSm

                                            Repeater {
                                                model: equipmentPage.envTiles
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
                                            // 汉字与读数分两个节点: 名字用默认字族, 数值那截才允许等宽
                                            Text {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "数据来源"
                                                font.pixelSize: styles.fsXs
                                                color: CommonOptions.colorInk3
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: equipmentPage.hasForecast
                                                      ? equipmentPage.forecastSrcLine
                                                      : equipmentPage.climateSrcLine
                                                font.pixelSize: styles.fsXs
                                                color: CommonOptions.colorTextMuted
                                                elide: Text.ElideRight
                                            }
                                        }

                                        // 降级说明: 只在预报档没吃上时才占一行, 而且说清
                                        // 现在这一屏是推演而不是预报 —— 不说就等于骗人.
                                        Text {
                                            Layout.fillWidth: true
                                            visible: equipmentPage.weatherSource === 2
                                                     && equipmentPage.forecastFailLine.length > 0
                                            text: "退回往年推演: " + equipmentPage.forecastFailLine
                                            font.pixelSize: styles.fsXs
                                            color: CommonOptions.colorHazard
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: equipmentPage.hasForecast
                                          ? ("这一屏是逐日在线预报, 只到未来几天; 天数更长的行程仍按往年推演那一档带。")
                                          : (equipmentPage.hasClimate
                                             ? (equipmentPage.weatherSource === 2
                                                ? "上面这屏是往年推演, 不是天气预报 —— 预报没吃上的原因见上一条。"
                                                : "常年平均态, 不是天气预报 —— 只用来决定带不带冰爪这一级。")
                                             : (equipmentPage.weatherSource === 1
                                                ? ("这一带不在往年表里 (表内 "
                                                   + equipmentPage.climateTotal + " 省), 切「手填」自己定档。")
                                                : (equipmentPage.weatherSource === 2
                                                   ? "预报和往年都没取到数 · 见上一条原因, 或切「手填」自己定档。"
                                                   : "手填: 下面五档就是本次生成的输入。")))
                                    font.pixelSize: styles.fsXs
                                    color: equipmentPage.hasEnv ? CommonOptions.colorInk3
                                                                : CommonOptions.colorHazard
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "季节"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: equipmentPage.seasonNames
                                delegate: Chip {
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    checked: equipmentPage.seasonIndex === index
                                    accent: CommonOptions.colorAccent
                                    textSize: styles.fsSm
                                    onClicked: {
                                        // 手改任意一档 → 来源即刻转「手填」, 不留隐藏态
                                        equipmentPage.weatherSource = 0
                                        equipmentPage.seasonIndex = index
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: equipmentPage.snowFamily ? "降雪" : "降水"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: equipmentPage.precipLabels
                                delegate: Chip {
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    checked: equipmentPage.precipIndex === index
                                    accent: CommonOptions.colorWater
                                    textSize: styles.fsXs
                                    onClicked: {
                                        equipmentPage.weatherSource = 0
                                        equipmentPage.precipIndex = index
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "湿度"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: equipmentPage.humidityNames
                                delegate: Chip {
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    checked: equipmentPage.humidityIndex === index
                                    accent: CommonOptions.colorWater
                                    textSize: styles.fsSm
                                    onClicked: {
                                        equipmentPage.weatherSource = 0
                                        equipmentPage.humidityIndex = index
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "紫外线"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: equipmentPage.uvLevelNames
                                delegate: Chip {
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    checked: equipmentPage.uvLevelIndex === index
                                    accent: CommonOptions.colorLegendAmber
                                    textSize: styles.fsXs
                                    onClicked: {
                                        equipmentPage.weatherSource = 0
                                        equipmentPage.uvLevelIndex = index
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "风力"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: equipmentPage.windLevelNames
                                delegate: Chip {
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    checked: equipmentPage.windLevelIndex === index
                                    accent: CommonOptions.colorWater
                                    textSize: styles.fsXs
                                    onClicked: {
                                        equipmentPage.weatherSource = 0
                                        equipmentPage.windLevelIndex = index
                                    }
                                }
                            }
                        }

                        FilterRow {
                            Layout.fillWidth: true
                            label: "温差"
                            labelWidth: 56
                            stepperValue: equipmentPage.diurnalRange + " °C"
                            stepperMinusEnabled: equipmentPage.diurnalRange > 0
                            stepperPlusEnabled: equipmentPage.diurnalRange < 40
                            onStepperMinus: {
                                equipmentPage.weatherSource = 0
                                equipmentPage.diurnalRange =
                                        Math.max(0, equipmentPage.diurnalRange - 5)
                            }
                            onStepperPlus: {
                                equipmentPage.weatherSource = 0
                                equipmentPage.diurnalRange =
                                        Math.min(40, equipmentPage.diurnalRange + 5)
                            }
                        }

                        // 地区标记: 多选 chip (雨季/沙漠/沿海)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "地区"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: [["雨季", "isRainySeason"], ["沙漠", "isDesert"], ["沿海", "isCoastal"]]
                                delegate: Chip {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData[0]
                                    checked: equipmentPage[modelData[1]] === true
                                    accent: CommonOptions.colorBlaze
                                    textSize: styles.fsSm
                                    onClicked: {
                                        equipmentPage.weatherSource = 0
                                        equipmentPage[modelData[1]] =
                                                !equipmentPage[modelData[1]]
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "季节选「冬」时降水按降雪计 · 海拔 2500 m 以上自动按高原处理 · "
                                  + "保暖/防暑看的是夜温与日均, 人数不参与选装"
                                  + (equipmentPage.weatherSource === 2
                                     ? " · 预报只覆盖未来几天, 出发前仍要对当天天气"
                                     : equipmentPage.weatherSource === 1
                                       ? " · 往年常态只有月内均值, 出发前请看实时天气"
                                       : "")
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                            wrapMode: Text.WordWrap
                        }
                    }

                    Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spSm }
                }
            }

            // ============================================================
            // 视图 1: 我的清单
            // ============================================================
            Item {
                ListView {
                    id: listView
                    anchors.fill: parent
                    anchors.leftMargin: styles.pageMargin
                    anchors.rightMargin: styles.pageMargin
                    anchors.topMargin: styles.spSm
                    anchors.bottomMargin: styles.spSm
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: equipmentPage.listRows

                    // 行 = MouseArea 在前 (垫底), 内容行在后: 行内动作块才不会被子项挡住,
                    // 空白处仍然整行可点.
                    delegate: Item {
                        required property var modelData
                        width: listView.width
                        height: modelData.kind === "head" ? 30 : styles.rowHTall

                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.kind === "item"
                            cursorShape: Qt.PointingHandCursor
                            onClicked: equipmentPage.navigateTo(
                                       "EquipmentDetailPage", { listId: modelData.itemId })
                        }

                        // 分组标题 (海拔档)
                        RowLayout {
                            anchors.fill: parent
                            anchors.rightMargin: styles.spXs
                            spacing: styles.spSm
                            visible: modelData.kind === "head"

                            Rectangle {
                                Layout.preferredWidth: styles.lineAccent
                                Layout.fillHeight: true
                                Layout.topMargin: 9
                                Layout.bottomMargin: 9
                                color: CommonOptions.altitudeColor(modelData.level)
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsLg
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData.count + " 份清单"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                        }

                        // 清单行
                        RowLayout {
                            anchors.fill: parent
                            anchors.rightMargin: styles.spXs
                            spacing: styles.spSm
                            visible: modelData.kind === "item"

                            Rectangle {
                                Layout.fillHeight: true
                                Layout.preferredWidth: styles.lineAccent
                                color: CommonOptions.altitudeColor(modelData.level)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: CommonOptions.colorText
                                    font.pixelSize: styles.fsMd
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "最高 " + modelData.altMax + " m · 已勾 "
                                          + modelData.checked
                                          + (modelData.completed ? " · 已清点" : "")
                                    color: CommonOptions.colorInk3
                                    font.pixelSize: styles.fsXs
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: equipmentPage.fmtKg(modelData.grams)
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                            ActionCell {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: "edit"
                                tone: CommonOptions.colorText
                                onClicked: {
                                    renameDialog.listId = modelData.itemId
                                    renameDialog.listName = modelData.name
                                    itemRenameField.text = modelData.name
                                    renameDialog.open()
                                }
                            }
                            ActionCell {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: "check"
                                tone: CommonOptions.colorForest
                                onClicked: equipmentPage.navigateTo(
                                           "ChecklistPage", { listId: modelData.itemId })
                            }
                            ActionCell {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: "delete"
                                tone: CommonOptions.colorDanger
                                onClicked: {
                                    confirmDeleteDialog.listId = modelData.itemId
                                    confirmDeleteDialog.listName = modelData.name
                                    confirmDeleteDialog.open()
                                }
                            }
                        }

                        Rectangle {
                            visible: modelData.kind === "item"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: styles.lineHair
                            color: CommonOptions.colorRuleSoft
                        }
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    visible: equipmentPage.listRows.length === 0
                    iconName: "backpack"
                    text: "还没有生成过清单"
                    hint: "切到「生成」填最高海拔与天数, 生成的清单会写进应用私有目录"
                    actionText: "去生成"
                    onActionTriggered: {
                        equipmentPage.view = 0
                        equipmentPage.loadLists()
                    }
                }
            }

            // ============================================================
            // 视图 2: 装备库
            // ============================================================
            Item {
                ListView {
                    id: itemsView
                    anchors.fill: parent
                    anchors.leftMargin: styles.pageMargin
                    anchors.rightMargin: styles.pageMargin
                    anchors.topMargin: styles.spSm
                    anchors.bottomMargin: styles.spSm
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: equipmentPage.itemRows

                    delegate: Item {
                        required property var modelData
                        width: itemsView.width
                        height: modelData.kind === "head" ? 30 : styles.rowHTall

                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.kind === "item"
                            cursorShape: Qt.PointingHandCursor
                            // 点行 = 编辑: 自定义条目直接改, 基础条目走"复制为自定义副本"
                            // (基础库写回 QSettings 没有意义, C++ 侧也没有 updateUserItem 的分支)
                            onClicked: equipmentPage.openItemDialog(
                                       modelData.isUser ? "edit" : "clone", modelData)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.rightMargin: styles.spXs
                            spacing: styles.spSm
                            visible: modelData.kind === "head"

                            Text {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsLg
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData.count + " 项"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.rightMargin: styles.spXs
                            spacing: 9
                            visible: modelData.kind === "item"

                            Plate {
                                Layout.preferredWidth: styles.plateW
                                Layout.alignment: Qt.AlignVCenter
                                code: modelData.plate
                                tone: CommonOptions.colorInk3
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: CommonOptions.colorText
                                    font.pixelSize: styles.fsMd
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.catLabel + (modelData.isUser ? " · 自定义" : "")
                                              + (modelData.grams <= 0 ? " · 无重量" : "")
                                        color: CommonOptions.colorInk3
                                        font.pixelSize: styles.fsXs
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            // "关键"是这一列唯一的信号 (5/49 件), 用琥珀文字而不是色条:
                            // 色条在本页已经有海拔含义 (视图 1), 不能借来当第二套语义.
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                visible: modelData.critical
                                text: "关键"
                                color: CommonOptions.colorLegendAmber
                                font.pixelSize: styles.fsXs
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData.grams + " g"
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                            ActionCell {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: modelData.isUser ? "edit" : "add"
                                tone: modelData.isUser ? CommonOptions.colorText
                                                       : CommonOptions.colorInk3
                                onClicked: equipmentPage.openItemDialog(
                                           modelData.isUser ? "edit" : "clone", modelData)
                            }
                            // 规则 ④: 基础库条目不可删 → 不给禁用态的假按钮
                            ActionCell {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                visible: modelData.isUser
                                iconName: "delete"
                                tone: CommonOptions.colorDanger
                                onClicked: equipmentPage.deleteItem(modelData.itemId)
                            }
                        }

                        Rectangle {
                            visible: modelData.kind === "item"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: styles.lineHair
                            color: CommonOptions.colorRuleSoft
                        }
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    visible: equipmentPage.itemRows.length === 0
                    iconName: "store"
                    text: equipmentPage.items.length === 0 ? "装备库是空的" : "没有关键装备"
                    hint: equipmentPage.items.length === 0
                          ? "检查 assets/data/equipment_base.json 是否打进包里"
                          : "关掉「只列关键」就能看到全部类别"
                    actionText: equipmentPage.items.length === 0 ? "重新载入" : "看全部"
                    onActionTriggered: {
                        if (equipmentPage.items.length === 0) equipmentPage.loadItems()
                        else equipmentPage.onlyCritical = false
                    }
                }
            }
        }

        // --- 底栏 (主操作常驻, 不随表单内部滚动丢失) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: barRow.implicitHeight + 2 * styles.spSm
            // 视图 1 没有整页级动作 (清单的行内动作齐了), 不摆空按钮
            visible: equipmentPage.view !== 1
            color: CommonOptions.colorSurfaceAlt

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            RowLayout {
                id: barRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                spacing: styles.spMd

                OutlineButton {
                    Layout.preferredWidth: 96
                    Layout.alignment: Qt.AlignVCenter
                    text: equipmentPage.view === 0
                          ? "重置"
                          : (equipmentPage.onlyCritical ? "看全部 " + equipmentPage.items.length
                                                        : "只列关键 " + equipmentPage.criticalCount)
                    tone: CommonOptions.colorText
                    textSize: styles.fsSm
                    onClicked: {
                        if (equipmentPage.view === 0) equipmentPage.resetForm()
                        else equipmentPage.onlyCritical = !equipmentPage.onlyCritical
                    }
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: equipmentPage.view === 0 ? "生成装备清单" : "新建装备"
                    iconName: equipmentPage.view === 0 ? "backpack" : "add"
                    tone: CommonOptions.colorAccent
                    textSize: styles.fsLg
                    onClicked: {
                        if (equipmentPage.view === 0) equipmentPage.generateList()
                        else equipmentPage.openItemDialog("add", ({ grams: 100 }))
                    }
                }
            }
        }
    }

    // === 对话框 ============================================================
    // 装备条目: 新建 / 修改 / 复制副本 共用一套字段 (dlgMode 决定写哪个口子).
    // 不用 standardButtons —— Material 的 OK/Cancel/Yes/No 在中文包里没有译文,
    // 弹出来是英文 (#41); 这里自定义 footer, 按钮文案自己写.
    Dialog {
        id: itemDialog
        modal: true
        anchors.centerIn: parent
        width: Math.min(420, equipmentPage.width - 2 * styles.pageMargin)
        padding: styles.spMd
        // Dialog 的底色走 Material 附加属性 (与 Main.qml searchDialog 同一条路);
        // 直接写 color: 会被 qmllint 判成 Dialog 上没有的属性.
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText

        property string dlgTitle: equipmentPage.dlgMode === "edit" ? "修改装备"
                                : (equipmentPage.dlgMode === "clone" ? "复制为自定义装备" : "新建装备")

        contentItem: ColumnLayout {
            spacing: styles.spSm

            Text {
                Layout.fillWidth: true
                text: itemDialog.dlgTitle
                color: CommonOptions.colorText
                font.pixelSize: styles.fsLg
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: equipmentPage.dlgMode === "clone"
                text: "基础库条目改不动, 复制一份改名或改重量就是你的自定义装备"
                color: CommonOptions.colorInk3
                font.pixelSize: styles.fsXs
                wrapMode: Text.WordWrap
            }
            TextField {
                id: itemNameText
                Layout.fillWidth: true
                Layout.preferredHeight: styles.btnH
                placeholderText: "装备名称"
                placeholderTextColor: CommonOptions.colorTextDim
                color: CommonOptions.colorText
                font.pixelSize: styles.fsMd
                leftPadding: styles.spSm
                rightPadding: styles.spSm
                topPadding: 0
                bottomPadding: 0
                background: Rectangle {
                    color: itemNameText.activeFocus
                           ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                    border.color: itemNameText.activeFocus
                                  ? CommonOptions.colorText : CommonOptions.colorRule
                    border.width: styles.lineHair
                    radius: styles.rSm
                }
            }

            // 类别: 9 枚文字 chip 分两行 (Material 的 ComboBox 弹出层要另管字体,
            // 且 9 类是本库的固定枚举, 摊开比下拉少一次点击)
            Text {
                text: "类别"
                color: CommonOptions.colorInk3
                font.pixelSize: styles.fsXs
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 5
                columnSpacing: styles.spXs
                rowSpacing: styles.spXs

                Repeater {
                    model: equipmentPage.categoryKeys
                    delegate: Chip {
                        required property var modelData
                        Layout.fillWidth: true
                        text: equipmentPage.categoryLabel(modelData)
                        checked: equipmentPage.dlgCategory === modelData
                        accent: CommonOptions.colorAccent
                        textSize: styles.fsXs
                        onClicked: equipmentPage.dlgCategory = String(modelData)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: styles.spSm
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "重量 (g)"
                        color: CommonOptions.colorInk3
                        font.pixelSize: styles.fsXs
                    }
                    TextField {
                        id: itemWeightText
                        Layout.fillWidth: true
                        Layout.preferredHeight: styles.btnH
                        inputMethodHints: Qt.ImhDigitsOnly
                        color: CommonOptions.colorText
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsMd
                        leftPadding: styles.spSm
                        rightPadding: styles.spSm
                        topPadding: 0
                        bottomPadding: 0
                        background: Rectangle {
                            color: itemWeightText.activeFocus
                                   ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                            border.color: itemWeightText.activeFocus
                                          ? CommonOptions.colorText : CommonOptions.colorRule
                            border.width: styles.lineHair
                            radius: styles.rSm
                        }
                    }
                }
                Chip {
                    Layout.alignment: Qt.AlignBottom
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: styles.chipH
                    text: "关键装备"
                    checked: equipmentPage.dlgCritical
                    accent: CommonOptions.colorLegendAmber
                    textSize: styles.fsXs
                    onClicked: equipmentPage.dlgCritical = !equipmentPage.dlgCritical
                }
            }
        }

        footer: DialogFooter {
            // 2026-10-26 按钮定稿: footer 排在 Dialog.padding 外面, 由 DialogFooter 自己管内缩与顶线
            kind: "primary"
            cancelText: "取消"
            confirmText: equipmentPage.dlgMode === "edit" ? "保存修改" : "存为我的装备"
            onCancel: itemDialog.reject()
            onConfirm: {
                equipmentPage.acceptItemDialog()
                // 校验/写入失败时 note 会留在页面上, 对话框不关, 用户能接着改
                if (equipmentPage.note.length === 0) itemDialog.accept()
            }
        }
    }

    Dialog {
        id: renameDialog
        property string listId: ""
        property string listName: ""

        modal: true
        anchors.centerIn: parent
        width: Math.min(420, equipmentPage.width - 2 * styles.pageMargin)
        padding: styles.spMd
        // Dialog 的底色走 Material 附加属性 (与 Main.qml searchDialog 同一条路);
        // 直接写 color: 会被 qmllint 判成 Dialog 上没有的属性.
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText

        contentItem: ColumnLayout {
            spacing: styles.spSm

            Text {
                Layout.fillWidth: true
                text: "重命名清单"
                color: CommonOptions.colorText
                font.pixelSize: styles.fsLg
                font.bold: true
                elide: Text.ElideRight
            }
            TextField {
                id: itemRenameField
                Layout.fillWidth: true
                Layout.preferredHeight: styles.btnH
                placeholderText: "新名称"
                placeholderTextColor: CommonOptions.colorTextDim
                color: CommonOptions.colorText
                font.pixelSize: styles.fsMd
                leftPadding: styles.spSm
                rightPadding: styles.spSm
                topPadding: 0
                bottomPadding: 0
                background: Rectangle {
                    color: itemRenameField.activeFocus
                           ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                    border.color: itemRenameField.activeFocus
                                  ? CommonOptions.colorText : CommonOptions.colorRule
                    border.width: styles.lineHair
                    radius: styles.rSm
                }
            }
        }

        footer: DialogFooter {
            kind: "primary"
            cancelText: "取消"
            confirmText: "改名"
            onCancel: renameDialog.reject()
            onConfirm: {
                var nm = itemRenameField.text.trim()
                if (nm.length === 0) {
                    equipmentPage.note = "名称不能为空, 清单还是原来那个"
                    return
                }
                equipmentPage.renameList(renameDialog.listId, nm)
                if (equipmentPage.note.length === 0) renameDialog.accept()
            }
        }
    }

    Dialog {
        id: confirmDeleteDialog
        property string listId: ""
        property string listName: ""

        modal: true
        anchors.centerIn: parent
        width: Math.min(420, equipmentPage.width - 2 * styles.pageMargin)
        padding: styles.spMd
        // Dialog 的底色走 Material 附加属性 (与 Main.qml searchDialog 同一条路);
        // 直接写 color: 会被 qmllint 判成 Dialog 上没有的属性.
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText

        contentItem: ColumnLayout {
            spacing: styles.spSm

            Text {
                Layout.fillWidth: true
                text: "删除清单"
                color: CommonOptions.colorDangerOnText
                font.pixelSize: styles.fsLg
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: "要删掉「" + confirmDeleteDialog.listName
                      + "」吗? 这条记录连同勾选状态一起从存储目录移除, 删了找不回。"
                color: CommonOptions.colorText
                font.pixelSize: styles.fsMd
                wrapMode: Text.WordWrap
            }
        }

        footer: DialogFooter {
            kind: "danger"
            cancelText: "留着"
            confirmText: "删除"
            confirmIcon: "delete"
            confirmCode: "不可撤"
            onCancel: confirmDeleteDialog.reject()
            onConfirm: {
                equipmentPage.deleteList(confirmDeleteDialog.listId,
                                         confirmDeleteDialog.listName)
                if (equipmentPage.note.length === 0) confirmDeleteDialog.accept()
            }
        }
    }
}
