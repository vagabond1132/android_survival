/**
 * @file CommonOptions.cpp
 * @brief 设计 token 中的分类/等级色 + 下拉选项 + 格式化函数实现
 */
#include "CommonOptions.h"
#include <QHash>
#include <QDesktopServices>
#include <QUrl>
#include <QtMath>
#include <cmath>

// 构造函数在头文件内联定义. 字体就绪标记由 main.cpp 在 addApplicationFont 后写入.
bool CommonOptions::s_iconFontReady = false;

QVariantList CommonOptions::difficultyOptions() const {
    return QVariantList{
        QVariantMap{{"value", 1}, {"label", "1 入门"}},
        QVariantMap{{"value", 2}, {"label", "2 简单"}},
        QVariantMap{{"value", 3}, {"label", "3 中等"}},
        QVariantMap{{"value", 4}, {"label", "4 困难"}},
        QVariantMap{{"value", 5}, {"label", "5 极难"}}
    };
}

QVariantList CommonOptions::daysOptions() const {
    return QVariantList{
        QVariantMap{{"value", 0}, {"label", "全部"}},
        QVariantMap{{"value", 2}, {"label", "1-2 天"}, {"minDays", 1}, {"maxDays", 2}},
        QVariantMap{{"value", 3}, {"label", "3-5 天"}, {"minDays", 3}, {"maxDays", 5}},
        QVariantMap{{"value", 4}, {"label", "6-10 天"}, {"minDays", 6}, {"maxDays", 10}},
        QVariantMap{{"value", 5}, {"label", "10+ 天"}, {"minDays", 11}, {"maxDays", 99}}
    };
}

QVariantList CommonOptions::distanceOptions() const {
    return QVariantList{
        QVariantMap{{"value", 0}, {"label", "全部"}},
        QVariantMap{{"value", 1}, {"label", "< 500 km"}, {"minKm", 0.0}, {"maxKm", 500.0}},
        QVariantMap{{"value", 2}, {"label", "500-1000 km"}, {"minKm", 500.0}, {"maxKm", 1000.0}},
        QVariantMap{{"value", 3}, {"label", "1000-2000 km"}, {"minKm", 1000.0}, {"maxKm", 2000.0}},
        QVariantMap{{"value", 4}, {"label", "> 2000 km"}, {"minKm", 2000.0}, {"maxKm", 99999.0}}
    };
}

QVariantList CommonOptions::monthOptions() const {
    QVariantList list;
    list.append(QVariantMap{{"value", 0}, {"label", "全部"}});
    // 2026-09-14: 修复"月份下拉框只有全部"bug, 加上 1-12 月
    for (int m = 1; m <= 12; ++m) {
        list.append(QVariantMap{{"value", m}, {"label", QString::number(m) + "月"}});
    }
    return list;
}

QVariantList CommonOptions::kingdomOptions() const {
    // 2026-10-08: 修 - 之前用 emoji (🌿/🐍/🐝/🍄) 作图标, Android 默认字体无
    //   彩色 emoji 字形 → 真机显示为方框. 改用 Material Icons PUA 码位, 与
    //   FieldGuidePage / FieldGuideImagePickPage 的本地 kingdomOptions 保持一致
    //   (码位均已确认包含在 assets/fonts/MaterialIcons-Regular.ttf 中).
    //   消费方需把下拉框 font.family 设为 "Material Icons" 才能出图.
    return QVariantList{
        QVariantMap{{"value", 0}, {"label", "\ue406 植物"}},  // nature (叶子)
        QVariantMap{{"value", 1}, {"label", "\ue91a 动物"}},
        QVariantMap{{"value", 2}, {"label", "\ue1b9 昆虫"}},
        QVariantMap{{"value", 3}, {"label", "\ue239 蘑菇"}}   // emoji_nature
    };
}

QVariantList CommonOptions::routeNatureOptions() const {
    return QVariantList{
        QVariantMap{{"value", ""}, {"label", "全部"}},
        QVariantMap{{"value", "穿越"}, {"label", "穿越"}},
        QVariantMap{{"value", "环线"}, {"label", "环线"}},
        QVariantMap{{"value", "单程"}, {"label", "单程"}}
    };
}

QString CommonOptions::formatDistance(double km) const {
    if (km < 1.0) return QString::number(km * 1000.0, 'f', 0) + " m";
    return QString::number(km, 'f', 1) + " km";
}

QString CommonOptions::formatElevation(double m) const {
    return QString::number(m, 'f', 0) + " m";
}

QString CommonOptions::formatDuration(qint64 sec) const {
    if (sec < 60) return QString::number(sec) + " 秒";
    if (sec < 3600) return QString::number(sec / 60) + " 分";
    return QString::number(sec / 3600) + " 小时";
}

QString CommonOptions::difficultyLabel(int level) const {
    static const QStringList labels = {"入门", "简单", "中等", "困难", "极难"};
    if (level < 1 || level > 5) return "";
    return labels[level - 1];
}

QString CommonOptions::routeNatureLabel(const QString& key) const {
    if (key.isEmpty()) return "全部";
    return key;
}

// 2026-10-19: 图鉴 entity.category 存的是数据文件里的英文键 (assets/data/field_guide_*.json,
//   共 38 个). 详情页"性质"卡以前直接打印它, 真机上就是一行 wild_vegetable.
//   键表按四个 kingdom 的数据文件逐一核对过, 未知键原样返回便于发现漏配.
QString CommonOptions::speciesCategoryLabel(const QString& key) const {
    static const QHash<QString, QString> labels {
        // plantae
        { "medicinal", "药用植物" }, { "ornamental", "观赏植物" },
        { "poisonous", "有毒植物" }, { "wild_fruit", "野果" },
        { "wild_vegetable", "野菜" },
        // fungi
        { "edible_mushroom", "食用菌" }, { "common_poisonous", "常见毒菇" },
        { "deadly_mushroom", "致命毒菇" },
        // animalia
        { "bird", "鸟类" }, { "amphibian", "两栖类" }, { "reptile", "爬行类" },
        { "venomous_snake", "毒蛇" }, { "non_venomous_snake", "无毒蛇" },
        { "mammal_common", "常见哺乳类" }, { "mammal_dangerous", "危险哺乳类" },
        { "dangerous_beast", "危险兽类" }, { "leech", "水蛭" },
        // insecta
        { "ant", "蚂蚁" }, { "bee", "蜂类" }, { "wasp", "胡蜂" },
        { "beetle", "甲虫" }, { "rove_beetle", "隐翅虫" },
        { "butterfly", "蝴蝶" }, { "moth", "蛾类" }, { "caterpillar", "毛虫" },
        { "odonata", "蜻蜓目" }, { "fly", "蝇类" }, { "mosquito", "蚊虫" },
        { "spider", "蜘蛛" }, { "scorpion", "蝎子" }, { "centipede", "蜈蚣" },
        { "tick", "蜱虫" }, { "mite", "螨虫" }, { "louse", "虱子" },
        { "flea", "跳蚤" }, { "mantis", "螳螂" }, { "cnidarian", "刺胞动物" },
        { "pest", "害虫" }
    };
    auto it = labels.constFind(key);
    return it == labels.constEnd() ? key : it.value();
}

// 2026-10-20 #40: 可食部位键表按 4 个 field_guide_*.json 的 edible_part 实际取值逐一核对
//   (leaf/stem/root/flower/seed/fruit/bulbil/bulb/shoot/rhizome/bark/whole/peel/aerial).
QString CommonOptions::ediblePartLabel(const QString& key) const {
    static const QHash<QString, QString> labels {
        { "leaf", "叶" }, { "stem", "茎" }, { "root", "根" }, { "flower", "花" },
        { "seed", "种子" }, { "fruit", "果实" }, { "bulbil", "珠芽" },
        { "bulb", "鳞茎" }, { "shoot", "嫩梢" }, { "rhizome", "根茎" },
        { "bark", "树皮" }, { "whole", "全株" }, { "peel", "果皮" },
        { "aerial", "地上部分" }
    };
    auto it = labels.constFind(key);
    return it == labels.constEnd() ? key : it.value();
}

// 2026-10-20 #40: edible_method 实际取值 (31 个英文键 + 数据里手写的中文, 中文原样透出)
QString CommonOptions::edibleMethodLabel(const QString& key) const {
    static const QHash<QString, QString> labels {
        { "raw", "生食" }, { "boiled", "煮食" }, { "blanch", "焯水" },
        { "stir_fry", "炒食" }, { "stew", "炖煮" }, { "soup", "做汤" },
        { "porridge", "煮粥" }, { "pancake", "摊饼" }, { "dumpling", "包饺子" },
        { "stuffed", "做馅" }, { "cold_dressed", "凉拌" }, { "pickled", "腌制" },
        { "pickle", "腌渍" }, { "dried", "制干" }, { "powder", "磨粉" },
        { "flour", "制粉" }, { "spice", "调味" }, { "tea", "泡茶" },
        { "infusion", "冲泡" }, { "decoction", "煎汤" }, { "juice", "榨汁" },
        { "jam", "制酱" }, { "candy", "糖渍" }, { "dessert", "做甜点" },
        { "wine", "泡酒" }, { "moxibustion", "艾灸" }, { "external", "外用" },
        { "dye", "染色" }, { "fodder", "饲料" }
    };
    auto it = labels.constFind(key);
    return it == labels.constEnd() ? key : it.value();
}

// 2026-10-20 (#60 详情页改版带出): venom_type 和 edible_part 是同一类问题 ——
//   数据存英文键, 详情页原来直接打印, 用户看到 "neuro_toxin".
//   键表取自 field_guide_*.json 里全部 31 个实际取值 (uniq -c 核过),
//   neurotoxin / neuro_toxin 两种拼法数据里都有, 都得收.
QString CommonOptions::venomTypeLabel(const QString& key) const {
    static const QHash<QString, QString> labels {
        { "none", "无毒" }, { "mild", "毒性较弱" },
        { "blood_toxin", "血液毒素" }, { "neurotoxin", "神经毒素" },
        { "neuro_toxin", "神经毒素" }, { "cytotoxin", "细胞毒素" },
        { "tetrodotoxin", "河豚毒素" }, { "bufotoxin", "蟾毒素" },
        { "paederin", "隐翅虫素" }, { "cantharidin", "斑蝥素" },
        { "hirudin", "水蛭素 (抗凝血)" }, { "nematocyst", "刺丝囊" },
        { "contact_toxin", "接触毒素" }, { "contact_dermatitis", "接触性皮炎" },
        { "caterpillar_hair_toxin", "毛虫毒毛" },
        { "bee_venom", "蜂毒" }, { "wasp_venom", "胡蜂毒" }, { "ant_venom", "蚁毒" },
        { "scorpion_venom", "蝎毒" }, { "centipede_venom", "蜈蚣毒" },
        { "cnidarian_venom", "刺胞毒素" }, { "tick_toxin", "蜱毒素" },
        { "saliva", "唾液" }, { "mosquito_saliva", "蚊唾液" },
        { "mite_saliva", "螨唾液" }, { "louse_saliva", "虱唾液" },
        { "flea_saliva", "蚤唾液" }, { "tabanid_saliva", "虻唾液" },
        { "simuliid_saliva", "蚋唾液" }, { "ceratopogonid_saliva", "蠓唾液" }
    };
    auto it = labels.constFind(key);
    return it == labels.constEnd() ? key : it.value();
}

// === ⑤ 分类 / 等级色 ===
// 改版前这些色值散落在 30+ 个 QML 里当字面 hex, 同一个"危险度 3"在
// DangerSpeciesPage / SpeciesDetailPage / MapPage 三处取的是不同颜色.
// 收敛到此处后, 索引越界一律回落到首色, 不让页面自己写兜底色.

QColor CommonOptions::categoryColor(int index) const {
    // 2026-10-20 「地物图例」: 循环板换成 ISOM 信号色. 顺序按"先常见后生僻"排,
    // 相邻索引要能一眼分开, 所以橙/蓝/绿/紫交替而不是同族渐次.
    static const char* kPalette[] = {
        "#1B6A43", "#0C6C9E", "#DE5B1C", "#752C6B",
        "#B5850F", "#17704A", "#B4290E", "#4C5A53"
    };
    const int n = int(sizeof(kPalette) / sizeof(kPalette[0]));
    int i = index % n;
    if (i < 0) i += n;
    return QColor(QString::fromLatin1(kPalette[i]));
}

QColor CommonOptions::dangerColor(int level) const {
    // 危险度色阶 = 图例信号色阶: 植被绿 → 警示琥珀 → 火橙 → flag 红 → 深 flag 红.
    // 第 4/5 档必须是 hazard 红族 (#B4290E / #8E1F07): 危险条目是 hazard 红在全站
    // 唯一合法的两种用法之一 (另一种是 SOS), 不能借蓝或紫.
    static const char* kScale[] = { "#1B6A43", "#B5850F", "#DE5B1C", "#B4290E", "#8E1F07" };
    if (level < 1 || level > 5) return QColor(QString::fromLatin1("#8B978F"));  // 未知等级 = 三级墨
    return QColor(QString::fromLatin1(kScale[level - 1]));
}

QColor CommonOptions::difficultyColor(int level) const {
    // 与 dangerColor 同族但起点更低: 难度是"要花多大力气", 不是"会不会出事",
    // 所以 1 档用植被绿、5 档用深 flag 红, 中间不让 hazard 红提前出现.
    static const char* kScale[] = { "#1B6A43", "#B5850F", "#DE5B1C", "#B4290E", "#8E1F07" };
    if (level < 1 || level > 5) return QColor(QString::fromLatin1(kScale[1]));
    return QColor(QString::fromLatin1(kScale[level - 1]));
}

QColor CommonOptions::kingdomColor(int index) const {
    // 索引与 kingdomOptions() 对齐: 0 植物 / 1 动物 / 2 昆虫 / 3 蘑菇
    // 图例读法: 植物=植被绿; 动物=水蓝(地图上的动物分布历来跟水系走);
    // 昆虫=火橙(小体积需要高对比); 蘑菇=紫(与路线同色但只出现在图鉴内, 不冲突).
    static const char* kKinds[] = { "#1B6A43", "#0C6C9E", "#DE5B1C", "#752C6B" };
    const int n = int(sizeof(kKinds) / sizeof(kKinds[0]));
    int i = index % n;
    if (i < 0) i += n;
    return QColor(QString::fromLatin1(kKinds[i]));
}

QColor CommonOptions::altitudeColor(int level) const {
    // AltitudeLevel L0-L6: 低海拔植被绿 → 雪线白. 浅色底下最后一档不能再用
    // #ECEFF1 (会并进 paper 底色), 换成描边灰 + 由调用方保证描边.
    static const char* kScale[] = {
        "#145234", "#1B6A43", "#B5850F", "#DE5B1C", "#B4290E", "#752C6B", "#4C5A53"
    };
    const int n = int(sizeof(kScale) / sizeof(kScale[0]));
    int i = level < 0 ? 0 : (level >= n ? n - 1 : level);
    return QColor(QString::fromLatin1(kScale[i]));
}

QColor CommonOptions::withAlpha(const QColor &c, qreal alpha) const {
    QColor out = c;
    out.setAlphaF(qBound<qreal>(0.0, alpha, 1.0));
    return out;
}

QString CommonOptions::css(const QColor &c, qreal alpha) const {
    QColor col = c;
    if (!qFuzzyCompare(alpha, 1.0))
        col.setAlphaF(qBound<qreal>(0.0, alpha, 1.0));
    if (col.alpha() >= 255)
        return QString::asprintf("rgb(%d,%d,%d)", col.red(), col.green(), col.blue());
    return QString::asprintf("rgba(%d,%d,%d,%.3g)",
                             col.red(), col.green(), col.blue(),
                             col.alpha() / 255.0);
}

// === 方位 / 图鉴编号 (2026-10-20 「地物图例」丁骨架) =========================
// ②资源按"离我多远 + 在哪个方位"排序, 每行左列 50px 方位列; ①营地的
// 「你面前有什么」两格也用它. 距离与方位都在展示层算: 服务层已经有
// currentLat/currentLon, 而条目表里只有 lat/lon, 不必为此动数据库.

qreal CommonOptions::bearingDegrees(double fromLat, double fromLon,
                                   double toLat, double toLon) const {
    // 球面初始方位角公式 (forward azimuth), 结果归一到 [0,360)
    const double phi1 = fromLat * M_PI / 180.0;
    const double phi2 = toLat * M_PI / 180.0;
    const double dLon = (toLon - fromLon) * M_PI / 180.0;
    const double y = std::sin(dLon) * std::cos(phi2);
    const double x = std::cos(phi1) * std::sin(phi2)
                   - std::sin(phi1) * std::cos(phi2) * std::cos(dLon);
    if (qFuzzyIsNull(x) && qFuzzyIsNull(y)) return 0.0;   // 同点: 方位无意义, 给正北
    qreal deg = std::atan2(y, x) * 180.0 / M_PI;
    deg = std::fmod(deg + 360.0, 360.0);
    return deg;
}

double CommonOptions::distanceMeters(double lat1, double lon1,
                                     double lat2, double lon2) const {
    constexpr double kEarthR = 6371008.8;   // 平均地球半径 (m)
    const double phi1 = lat1 * M_PI / 180.0;
    const double phi2 = lat2 * M_PI / 180.0;
    const double dPhi = phi2 - phi1;
    const double dLam = (lon2 - lon1) * M_PI / 180.0;
    const double a = std::sin(dPhi / 2.0) * std::sin(dPhi / 2.0)
                   + std::cos(phi1) * std::cos(phi2)
                   * std::sin(dLam / 2.0) * std::sin(dLam / 2.0);
    return 2.0 * kEarthR * std::atan2(std::sqrt(a), std::sqrt(1.0 - a));
}

QString CommonOptions::compassLabel(qreal degrees) const {
    const qreal d = std::fmod(degrees + 360.0, 360.0);
    // 16 方位里取 8 个: 一格 45°, 边界往右邻靠 (与指南针刻度读法一致)
    static const char* kDirs[8] = { "北", "东北", "东", "东南", "南", "西南", "西", "西北" };
    const int idx = int(std::floor((d + 22.5) / 45.0)) % 8;
    return QString::fromUtf8(kDirs[idx]);
}

QString CommonOptions::formatBearingDistance(double meters) const {
    if (meters < 0.0) return QString();
    if (meters < 1000.0) return QString::number(qRound(meters)) + QStringLiteral(" m");
    return QString::number(meters / 1000.0, 'f', 1) + QStringLiteral(" km");
}

QString CommonOptions::plateCode(const QString &prefix, const QString &id, int width) const {
    // 编号是"目录卡片号", 不是数据库主键: 只要求同一前缀下稳定且短到能进角标.
    QString num;
    bool isNumber = false;
    const long long v = id.toLongLong(&isNumber);
    if (isNumber && v >= 0) {
        num = QString::number(v);
    } else {
        // 非数字 id (物种用中文名当主键的表) 走 FNV-1a, 保证跨启动不变.
        quint32 h = 2166136261u;
        for (const QChar c : id) { h ^= c.unicode(); h *= 16777619u; }
        num = QString::number(h % 1000);
    }
    if (num.length() < width) num.prepend(QString(width - num.length(), QLatin1Char('0')));
    return prefix.isEmpty() ? num : prefix + QLatin1Char('-') + num;
}

// 数据正文的前缀净化 —— 见 CommonOptions.h 里 #27/#58 的说明.
// 不用 QRegularExpression 处理 emoji: 星平面字符 (🆘 U+1F198) 在 QString 里是两个
// QChar 代理对, 正则要么按 UTF-8 要么按 UTF-16 匹配, 这里直接按码元判更直白,
// 也不会因为 Qt 版本换 PCRE 配置而行为漂移.
QString CommonOptions::stripEntryMarker(const QString &text) const {
    QString t = text;
    for (;;) {
        if (t.isEmpty()) return t;
        const ushort c = t.at(0).unicode();
        // 星平面 emoji: 高代理必须紧跟低代理, 两个一起丢
        if (QChar::isHighSurrogate(c)) {
            if (t.size() > 1 && QChar::isLowSurrogate(t.at(1).unicode())) { t.remove(0, 2); continue; }
            t.remove(0, 1); continue;
        }
        // BMP 符号段:Misc Symbols 2600-27BF (⚠ ✅ ❗ ✓ ✗ ➕) / Dingbats /
        // 变体选择符 FE0F (跟在前一个 emoji 后面) / 带圈数字 2460-24FF (①②) /
        // 杂项符号与箭头 2B00-2BFF (⬤⭐)
        if ((c >= 0x2600 && c <= 0x27BF) || (c >= 0x2460 && c <= 0x24FF)
            || (c >= 0x2B00 && c <= 0x2BFF) || c == 0xFE0F) {
            t.remove(0, 1); continue;
        }
        // 前缀符号后面总跟一个空格 (半角 / 全角 / NBSP)
        if (c == QChar::Space || c == 0x3000 || c == 0x00A0) { t.remove(0, 1); continue; }
        break;
    }
    // 手写序号 "1. " / "12、" / "3)" —— 列表自己会排号, 留着就是 "01 1. 绳头绕一圈".
    // 半角点必须后跟空白才算序号, 否则 "2.5 米" 这种正文会被削成 "5 米";
    // 顿号与括号在中文正文里不会出现在小数位置, 可以直接认.
    int i = 0;
    while (i < t.size() && i < 3 && t.at(i).isDigit()) ++i;
    if (i > 0 && i < t.size()) {
        const ushort sep = t.at(i).unicode();
        const bool spaceNext = i + 1 < t.size()
                && (t.at(i + 1) == QChar::Space || t.at(i + 1).unicode() == 0x3000);
        const bool strip = (sep == QLatin1Char('.')) ? spaceNext
                        : (sep == 0x3001 || sep == QLatin1Char(')') || sep == 0xFF09);
        if (strip) t.remove(0, i + 1);
    }
    return t.trimmed();
}

// === POI 名称规范化 ============================================================
// routes.json 749 条里 68 条把山名拼了两遍 ("华山华山山门" / "武功山武功山山门"),
// 另有 189 条起点名与终点名逐字相同. 方向区分靠调用方加 "起点:" / "终点:" 前缀,
// 这里只修重复拼接.
// 放在展示层而不是直接改 JSON: RouteService::insertRoute 对已存在的 id 直接
// return (src/routes/RouteService.cpp:262), 真机数据库早就灌过旧数据, 改
// assets/data/routes.json 不会重新入库.
QString CommonOptions::poiName(const QString& mountain, const QString& rawName) const {
    QString name = rawName.trimmed();
    if (name.isEmpty()) return QString();
    const QString m = mountain.trimmed();
    if (m.length() >= 2 && name.startsWith(m + m))
        name = m + name.mid(2 * m.length());
    return name;
}

// === 外部地图导航 ==============================================================
namespace {

bool isValidWgs84(double lat, double lon) {
    if (lat == 0.0 && lon == 0.0) return false;      // 数据缺坐标时服务层给 0
    if (lat < -90.0 || lat > 90.0) return false;
    if (lon < -180.0 || lon > 180.0) return false;
    return true;
}

QString encoded(const QString& text) {
    return QString::fromUtf8(QUrl::toPercentEncoding(text));
}

QString coord(double v) { return QString::number(v, 'f', 6); }

} // namespace

// 高德地图 app URI. dev=1 声明传入的是 GPS(WGS-84) 坐标, 由高德内部转成它自己的
// GCJ-02; 本 App 的起终点数据和 OSM/CARTO 瓦片都是 WGS-84, 若按 dev=0 交给高德,
// 落点会整体偏 300~800m —— 这就是"导航地点不对"的直接原因.
bool CommonOptions::openMapMarker(double lat, double lon, const QString& name) const {
    if (!isValidWgs84(lat, lon)) return false;
    const QString poi = name.trimmed().isEmpty() ? QStringLiteral("位置") : name.trimmed();

    const QString amap = QStringLiteral("androidamap://viewMap"
                                        "?sourceApplication=OutdoorSurvival"
                                        "&lat=%1&lon=%2&dev=1&poiname=%3&zoom=16")
                             .arg(coord(lat))
                             .arg(coord(lon))
                             .arg(encoded(poi));
    if (QDesktopServices::openUrl(QUrl(amap))) return true;

    // 兜底: 标准 geo: URI, 由系统默认地图接管 (name 作查询词).
    const QString geo = QStringLiteral("geo:%1,%2?q=%3")
                            .arg(coord(lat))
                            .arg(coord(lon))
                            .arg(encoded(poi));
    return QDesktopServices::openUrl(QUrl(geo));
}

bool CommonOptions::openMapRoute(double slat, double slon, const QString& sname,
                                 double dlat, double dlon, const QString& dname,
                                 const QString& mode) const {
    if (!isValidWgs84(dlat, dlon)) return false;
    // t: 0 驾车 / 1 公交 / 2 步行 / 3 骑行
    int t = 0;
    if (mode == QLatin1String("bus"))        t = 1;
    else if (mode == QLatin1String("walk"))  t = 2;
    else if (mode == QLatin1String("ride"))  t = 3;

    const QString startName = sname.trimmed().isEmpty() ? QStringLiteral("起点") : sname.trimmed();
    const QString endName   = dname.trimmed().isEmpty() ? QStringLiteral("终点") : dname.trimmed();

    QString url = QStringLiteral("androidamap://route/plan/?sourceApplication=OutdoorSurvival");
    if (isValidWgs84(slat, slon)) {
        url += QStringLiteral("&slat=%1&slon=%2&sname=%3")
                   .arg(coord(slat))
                   .arg(coord(slon))
                   .arg(encoded(startName));
    }
    url += QStringLiteral("&dlat=%1&dlon=%2&dname=%3&dev=1&t=%4")
               .arg(coord(dlat))
               .arg(coord(dlon))
               .arg(encoded(endName))
               .arg(t);
    if (QDesktopServices::openUrl(QUrl(url))) return true;

    // 兜底: 没有起终点路线能力时, 至少把终点交出去.
    return openMapMarker(dlat, dlon, dname);
}
