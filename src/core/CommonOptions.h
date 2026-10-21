/**
 * @file CommonOptions.h
 * @brief 全局设计 token (颜色) + 下拉选项 + 格式化 (C++ 单例)
 *
 * 之前用 QML pragma Singleton + import "components/CommonOptions.qml",
 * qmlcachegen 静态编译下不工作 (run.txt 18:23-18:26 报 "no such directory").
 * 改用 C++ 单例 + qmlRegisterSingletonInstance, 与 App 同样的注册方式.
 *
 * 2026-10-16 整体改版: 颜色 token 从 8 个扩到 30 个, 分四层
 *   ① surface  背景/卡片/描边   ② text     四级文字
 *   ③ brand/state 主色 + 语义状态色 (含半透明容器色, 深色主题下的 tint 背景)
 *   ④ categorical 分类/等级色 (通过 Q_INVOKABLE 函数按索引取, 避免各页自造色值)
 * 尺寸/间距/字号 token 在 qml/components/base/Styles.qml, 两者分工不变.
 *
 * 2026-10-20 「地物图例」改版: 整套 token 从深色 Material BlueGrey 换成
 * 户外可读的浅色底 + ISOM (定向地图图例) 信号色. 语义名保持不变, 只换值 +
 * 补 12 个图例色, 所以 490 处既有引用不用改就能跟着换肤.
 *   底色 (方案 A 岩面中性): paper #E8ECEA / card #F6F8F6 / ink #131A17 / rule #C9D2CD
 *   信号色 (色即语义, 不是装饰): forest 植被 / water 水源 / blaze 主操作强调
 *                              hazard 危险与 SOS / amber 警示 / plum 路线
 *   墨底仪表 (夜行读数块): night #0E1614 + onNight #EDF1EF
 * 为什么不用深色底: 山脊强光下深色主题对比度塌得最快, 这是野外查阅工具.
 * 为什么色值借图例: 绿色=植被/可食、蓝色=水源、橙红=危险/火、紫=路线,
 *                  用户在地图上早就按这个规则读色, 界面不用重新学.
 * hazard 红 #B4290E 只允许出现在 SOS 与真危险内容上 (红线, 见 dangerColor).
 * 页面禁止再写字面 hex.
 */
#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QColor>

class CommonOptions : public QObject {
    Q_OBJECT
    // === ① surface: 背景 / 卡片 / 描边 ===
    Q_PROPERTY(QColor colorBg         READ colorBg         CONSTANT)  // 窗口底色
    Q_PROPERTY(QColor colorSurface    READ colorSurface    CONSTANT)  // 一级卡片
    Q_PROPERTY(QColor colorSurfaceAlt READ colorSurfaceAlt CONSTANT)  // 二级卡片/抬升
    Q_PROPERTY(QColor colorSurfaceDim READ colorSurfaceDim CONSTANT)  // 图标底/输入框底
    Q_PROPERTY(QColor colorDivider    READ colorDivider    CONSTANT)  // 1px 分隔线/描边
    Q_PROPERTY(QColor colorScrim      READ colorScrim      CONSTANT)  // 弹层遮罩

    // === ② text: 四级文字 (亮度递减, 深色主题下越亮层级越高) ===
    Q_PROPERTY(QColor colorText        READ colorText        CONSTANT)  // 主文字
    Q_PROPERTY(QColor colorTextMuted   READ colorTextMuted   CONSTANT)  // 副标题/说明
    Q_PROPERTY(QColor colorTextDim     READ colorTextDim     CONSTANT)  // 弱提示/占位
    Q_PROPERTY(QColor colorTextDisabled READ colorTextDisabled CONSTANT) // 禁用
    Q_PROPERTY(QColor colorTextOnAccent READ colorTextOnAccent CONSTANT) // 主色底上文字

    // === ③ brand / state ===
    Q_PROPERTY(QColor colorAccent      READ colorAccent      CONSTANT)
    Q_PROPERTY(QColor colorAccentDeep  READ colorAccentDeep  CONSTANT)
    Q_PROPERTY(QColor colorAccentSoft  READ colorAccentSoft  CONSTANT)
    Q_PROPERTY(QColor colorAccentBg    READ colorAccentBg    CONSTANT)  // 主色 18% 容器
    Q_PROPERTY(QColor colorWarn        READ colorWarn        CONSTANT)
    Q_PROPERTY(QColor colorWarnBg      READ colorWarnBg      CONSTANT)
    Q_PROPERTY(QColor colorDanger      READ colorDanger      CONSTANT)
    Q_PROPERTY(QColor colorDangerDeep  READ colorDangerDeep  CONSTANT)
    Q_PROPERTY(QColor colorDangerBg    READ colorDangerBg    CONSTANT)
    Q_PROPERTY(QColor colorSuccess     READ colorSuccess     CONSTANT)
    Q_PROPERTY(QColor colorSuccessBg   READ colorSuccessBg   CONSTANT)
    Q_PROPERTY(QColor colorInfo        READ colorInfo        CONSTANT)
    Q_PROPERTY(QColor colorTeal        READ colorTeal        CONSTANT)
    Q_PROPERTY(QColor colorTealBg      READ colorTealBg      CONSTANT)
    Q_PROPERTY(QColor colorTealSoft    READ colorTealSoft    CONSTANT)  // 浅青底 (装备推荐卡)
    // 改版清点: 列表页 hero 渐变/优先级标记还用到下面 7 个色. 一并收口,
    // 否则 Wave 3 逐页替换时这 7 个只能继续留在 QML 里当字面 hex.
    Q_PROPERTY(QColor colorTealDeep    READ colorTealDeep    CONSTANT)  // 列表页 hero 渐变起点
    Q_PROPERTY(QColor colorGreenDeep   READ colorGreenDeep   CONSTANT)  // 深绿 (已掌握/安全)
    Q_PROPERTY(QColor colorOrangeDeep  READ colorOrangeDeep  CONSTANT)  // 深橙 (高难度)
    Q_PROPERTY(QColor colorAmber       READ colorAmber       CONSTANT)  // 琥珀 (推荐/星标)
    Q_PROPERTY(QColor colorAmberSoft   READ colorAmberSoft   CONSTANT)  // 浅橙容器底
    Q_PROPERTY(QColor colorRedBright   READ colorRedBright   CONSTANT)  // 亮红 (拨打/高危)
    Q_PROPERTY(QColor colorPink        READ colorPink        CONSTANT)  // 品红 (危险物种)

    // === ④ 图表 / 地图专用 ===
    Q_PROPERTY(QColor colorTrack      READ colorTrack      CONSTANT)
    Q_PROPERTY(QColor colorRouteLine  READ colorRouteLine  CONSTANT)
    Q_PROPERTY(QColor colorGridLine   READ colorGridLine   CONSTANT)

    // === ⑤ 地物图例信号色 (2026-10-20 新增, 借 ISOM 定向地图图例) ===
    // 与上面 ③ 的 state 色不同, 这一组是"类别"色: 出现在方位列 / 图版角标 /
    // 盘上的点 / 分类 chip 上. 用法固定 —— 绿=植被可食, 蓝=水源, 橙=火与主操作,
    // 红=危险与 SOS, 黄=警示, 紫=路线 —— 页面不要再自造.
    Q_PROPERTY(QColor colorForest    READ colorForest    CONSTANT)  // 植被 / 可食 / 安全
    Q_PROPERTY(QColor colorWater     READ colorWater     CONSTANT)  // 水源
    Q_PROPERTY(QColor colorBlaze     READ colorBlaze     CONSTANT)  // 主操作 3px 左条 / 火
    Q_PROPERTY(QColor colorHazard    READ colorHazard    CONSTANT)  // 危险 / SOS (仅此两处)
    Q_PROPERTY(QColor colorLegendAmber READ colorLegendAmber CONSTANT) // 警示 / 推荐
    Q_PROPERTY(QColor colorPlum      READ colorPlum      CONSTANT)  // 路线
    // 墨底仪表: ①营地与⑤求助共用的 PositionReadout, 全站只允许这两处
    Q_PROPERTY(QColor colorInkPanel  READ colorInkPanel  CONSTANT)  // 仪表底色
    Q_PROPERTY(QColor colorOnInk     READ colorOnInk     CONSTANT)  // 仪表上文字
    Q_PROPERTY(QColor colorOnInkDim  READ colorOnInkDim  CONSTANT)  // 仪表上弱文字
    Q_PROPERTY(QColor colorBlazeSoft READ colorBlazeSoft CONSTANT)  // 墨底上的橙 (blaze 提亮)
    // 三级描边 (组线 / 普通卡 / 强调): 等粗描边等于没有强调
    Q_PROPERTY(QColor colorRuleSoft  READ colorRuleSoft  CONSTANT)
    Q_PROPERTY(QColor colorRule      READ colorRule      CONSTANT)
    Q_PROPERTY(QColor colorInk3      READ colorInk3      CONSTANT)  // 三级文字 (微标签)
public:
    explicit CommonOptions(QObject* parent = nullptr) : QObject(parent) {}

    // ① surface — 方案 A 岩面中性底
    QColor colorBg()         const { return QColor("#E8ECEA"); }
    QColor colorSurface()    const { return QColor("#F6F8F6"); }
    QColor colorSurfaceAlt() const { return QColor("#E2E8E4"); }
    QColor colorSurfaceDim() const { return QColor("#DFE5E1"); }
    QColor colorDivider()    const { return QColor("#C9D2CD"); }
    QColor colorScrim()      const { return QColor("#B30E1614"); }

    // ② text — 墨 #131A17 起四级递减 (浅色底下越暗层级越高).
    //    colorText 是全站 490 处引用的主文字色, 值一换整站跟着走.
    QColor colorText()         const { return QColor("#131A17"); }
    QColor colorTextMuted()    const { return QColor("#4C5A53"); }
    QColor colorTextDim()      const { return QColor("#78857D"); }
    QColor colorTextDisabled() const { return QColor("#A9B3AC"); }
    QColor colorTextOnAccent() const { return QColor("#F6F8F6"); }

    // ③ brand / state
    QColor colorAccent()      const { return QColor("#131A17"); }
    QColor colorAccentDeep()  const { return QColor("#0B100E"); }
    QColor colorAccentSoft()  const { return QColor("#DE5B1C"); }
    QColor colorAccentBg()    const { return QColor("#2EDE5B1C"); }
    QColor colorWarn()        const { return QColor("#B5850F"); }
    QColor colorWarnBg()      const { return QColor("#2EB5850F"); }
    QColor colorDanger()      const { return QColor("#B4290E"); }
    QColor colorDangerDeep()  const { return QColor("#8E1F07"); }
    QColor colorDangerBg()    const { return QColor("#2EB4290E"); }
    QColor colorSuccess()     const { return QColor("#1B6A43"); }
    QColor colorSuccessBg()   const { return QColor("#2E1B6A43"); }
    QColor colorInfo()        const { return QColor("#0C6C9E"); }
    QColor colorTeal()        const { return QColor("#17704A"); }
    QColor colorTealBg()      const { return QColor("#2E17704A"); }
    QColor colorTealSoft()    const { return QColor("#D6E8DD"); }
    QColor colorTealDeep()    const { return QColor("#0E4B32"); }
    QColor colorGreenDeep()   const { return QColor("#145234"); }
    QColor colorOrangeDeep()  const { return QColor("#B8460F"); }
    QColor colorAmber()       const { return QColor("#B5850F"); }
    QColor colorAmberSoft()   const { return QColor("#F4E6BE"); }
    QColor colorRedBright()   const { return QColor("#B4290E"); }
    QColor colorPink()        const { return QColor("#752C6B"); }

    // ④ 图表 / 地图
    QColor colorTrack()       const { return QColor("#DE5B1C"); }
    QColor colorRouteLine()   const { return QColor("#752C6B"); }
    QColor colorGridLine()    const { return QColor("#C9D2CD"); }

    // ⑤ 地物图例信号色 + 墨底仪表 + 三级描边 (2026-10-20)
    // 这一组是"类别"色, 出现在方位列 / 图版角标 / 盘上的点 / 分类 chip.
    // 规则借自定向地图图例, 界面与地图读色一致: 绿植被 / 蓝水源 / 橙火与主操作 /
    // 红危险与 SOS / 黄警示 / 紫路线.
    // colorInkPanel + colorOnInk 只允许用在①营地与⑤求助共用的 PositionReadout,
    // 全站出现第三次就贬值 (墨底 = 高优先级仪表的信号).
    QColor colorForest()      const { return QColor("#1B6A43"); }
    QColor colorWater()       const { return QColor("#0C6C9E"); }
    QColor colorBlaze()       const { return QColor("#DE5B1C"); }
    QColor colorHazard()      const { return QColor("#B4290E"); }
    QColor colorLegendAmber() const { return QColor("#B5850F"); }
    QColor colorPlum()        const { return QColor("#752C6B"); }
    QColor colorInkPanel()    const { return QColor("#0E1614"); }
    QColor colorOnInk()       const { return QColor("#EDF1EF"); }
    QColor colorOnInkDim()    const { return QColor("#8FA39B"); }
    QColor colorBlazeSoft()   const { return QColor("#F0894E"); }
    QColor colorRuleSoft()    const { return QColor("#DDE4E0"); }
    QColor colorRule()        const { return QColor("#C9D2CD"); }
    QColor colorInk3()        const { return QColor("#8B978F"); }

    // === ⑦ 字体就绪标记 ===
    // main.cpp 在 QQmlApplicationEngine 构造前 addApplicationFont, 结果记在这里.
    // IconLabel 直接读这个 CONSTANT, 不再每次求值扫 Qt.fontFamilies()
    // (全量枚举字体很贵, 且原先靠跨文件 id 判断字体状态根本拿不到).
    Q_PROPERTY(bool iconFontReady READ iconFontReady CONSTANT)

    // === ⑥ 分类 / 等级色 (按索引取, 取代各页自造的 hex) ===
    // 循环色板: 装备/路线/统计图表的多分类着色, 8 色内不重复
    Q_INVOKABLE QColor categoryColor(int index) const;
    // 危险度 1-5 → 绿→黄→橙→红→深红
    Q_INVOKABLE QColor dangerColor(int level) const;
    // 难度 1-5
    Q_INVOKABLE QColor difficultyColor(int level) const;
    // 界: 0=植物 1=动物 2=昆虫 3=蘑菇 (与 kingdomOptions 索引一致)
    Q_INVOKABLE QColor kingdomColor(int index) const;
    // 海拔分段着色 (地图/路线剖面共用)
    Q_INVOKABLE QColor altitudeColor(int level) const;
    // 任意 token 加透明度 (替代页面里散落的 Qt.rgba(x,y,z,a))
    Q_INVOKABLE QColor withAlpha(const QColor &c, qreal alpha) const;
    // 2026-10-21 真机: 物种库的 representative_color 存的是 {h,s,v} (h 0-360, s/v 0-100),
    //   而 QML 全局函数里**没有 Qt.hsv()** (只有 Qt.hsla), 详情页直接调会抛
    //   "TypeError: Property 'hsv' of object Qt(...) is not a function"。
    //   HSV→RGB 收口到这里, 两个调用点 (详情页色块 / 图册选图页) 共用。
    Q_INVOKABLE QColor hsvColor(int h, int s, int v) const;
    // === 方位 (2026-10-20 「地物图例」丁骨架) ===
    // 丁的②资源按"离我多远 + 在哪个方位"排序, 每行左列是 50px 方位列.
    // 数据侧只有 lat/lon, 所以方位算在展示层, 单位统一米.
    // 正北 0°, 顺时针, 结果归一到 [0,360).
    Q_INVOKABLE qreal bearingDegrees(double fromLat, double fromLon,
                                     double toLat, double toLon) const;
    Q_INVOKABLE double distanceMeters(double lat1, double lon1,
                                      double lat2, double lon2) const;
    // 8 方位汉字 (北/东北/东/...), 用于方位列与①营地的"你面前有什么"
    Q_INVOKABLE QString compassLabel(qreal degrees) const;
    // 距离展示: <1km 用 m, 否则一位小数 km
    Q_INVOKABLE QString formatBearingDistance(double meters) const;
    // 图鉴编号 (目录卡片号): "SV-007" 这种 前缀-零填充 的形式, 全站一种写法.
    // prefix 传 SV/KN/FA/... 序号取 id 的绝对值, 非数字 id 退回哈希取模, 保证稳定.
    Q_INVOKABLE QString plateCode(const QString &prefix, const QString &id, int width = 3) const;
    // 数据正文的前缀净化 (2026-10-20, 任务 #27/#58).
    // 少数条目把符号写进了字符串: knots.common_mistakes 每条前缀 "⚠️" (19 处),
    // survival_items.warnings/tips 前缀 "⚠️"/"✅" (79 处), danger_species.protective_gear
    // 前缀 "⚠️". Material Icons 与 Android 默认字体都没有这些字形 → 真机是方框.
    // 步骤还带手写的 "1. " 序号, 而详情页自己会排 "01 02", 两条并排就是 "01 1. 绳头…".
    // 只剥前缀, 不回写数据文件 (用户 2026-10-20 定的口径: 数据保持现状).
    Q_INVOKABLE QString stripEntryMarker(const QString &text) const;

    // Canvas 2D 专用: ctx.fillStyle / strokeStyle 只认 CSS 字符串, 不认 QColor.
    // 海拔剖面/图表在 Canvas 里自绘, 之前只能把 hex 再抄一遍进 ctx 语句,
    // 那是改版后残留 hex 的主要来源. 有了 css() 这些 ctx 也能跟着 token 走.
    Q_INVOKABLE QString css(const QColor &c, qreal alpha = 1.0) const;

    // ⑥ 字体就绪 (READ 函数, 供上面 Q_PROPERTY 用)
    bool iconFontReady() const { return s_iconFontReady; }
    // 由 main.cpp 在 addApplicationFont 之后、引擎加载 QML 之前调用
    static void setIconFontReady(bool ready) { s_iconFontReady = ready; }

    // === 下拉选项 (QVariantList of QVariantMap) ===
    Q_INVOKABLE QVariantList difficultyOptions() const;
    Q_INVOKABLE QVariantList daysOptions() const;
    Q_INVOKABLE QVariantList distanceOptions() const;
    Q_INVOKABLE QVariantList monthOptions() const;
    Q_INVOKABLE QVariantList kingdomOptions() const;
    Q_INVOKABLE QVariantList routeNatureOptions() const;

    // === 格式化 ===
    Q_INVOKABLE QString formatDistance(double km) const;
    Q_INVOKABLE QString formatElevation(double m) const;
    Q_INVOKABLE QString formatDuration(qint64 sec) const;

    // === 标签数组 ===
    Q_INVOKABLE QString difficultyLabel(int level) const;
    Q_INVOKABLE QString routeNatureLabel(const QString& key) const;
    // 2026-10-19 真机: 图鉴详情页"性质"卡直接打印 entity.category 原始英文键
    //   (wild_vegetable / venomous_snake ...), 用户看到的是数据字段而不是信息.
    Q_INVOKABLE QString speciesCategoryLabel(const QString& key) const;
    // 同一类问题 (2026-10-20 #40): 可食部位/做法也存的是英文键, 而且 659 条数据里
    // 已经混着手写的中文 ("嫩叶"/"焯水凉拌"), 未知键必须原样返回而不是猜.
    Q_INVOKABLE QString ediblePartLabel(const QString& key) const;
    Q_INVOKABLE QString edibleMethodLabel(const QString& key) const;
    // 动物/昆虫的毒素类型键 (31 种, 数据侧 neurotoxin / neuro_toxin 两种拼法都有)
    Q_INVOKABLE QString venomTypeLabel(const QString& key) const;

    // === POI 名称 / 外部地图导航 (2026-10-19 用户反馈: 导航地点不对) ===
    Q_INVOKABLE QString poiName(const QString& mountain, const QString& rawName) const;
    // 走高德 app URI (dev=1 = 传入 WGS-84, 由高德转 GCJ-02), 失败回退标准 geo:
    Q_INVOKABLE bool openMapMarker(double lat, double lon, const QString& name) const;
    Q_INVOKABLE bool openMapRoute(double slat, double slon, const QString& sname,
                                  double dlat, double dlon, const QString& dname,
                                  const QString& mode) const;   // drive|bus|walk|ride

private:
    // main.cpp 写入, QML 只读 (见上面 iconFontReady)
    static bool s_iconFontReady;
};
