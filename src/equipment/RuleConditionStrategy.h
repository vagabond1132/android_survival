/**
 * @file RuleConditionStrategy.h
 * @brief 装备规则条件策略模式 (5 阶段架构重构 Phase 3)
 *
 * 背景:
 *   原 EquipmentService::matchCondition 是 5+ 段 if-else 链,每个分支解析一种
 *   condition 字符串 ("altitude >= L3" / "precipitation == 'heavy'" 等)。
 *   新规则加一段 if-else,老规则忘了删就成了死代码。
 *
 * 解决:
 *   把每种条件抽成 RuleConditionStrategy 子类,前缀注册到 Factory,新增条件只需
 *   写一个新策略 + 一行 register,不再碰 EquipmentService。
 *
 * 与 EquipmentService 的关系:
 *   策略接收 QString + TripParameters,这样 matchCondition 里只需
 *   factory.create(prefix)->matches()。
 *
 * 2026-09-23 修复 (真机日志实证):
 *   1. AltitudeCondition 用 cond.mid(12,1) 解析段位, 但下标 12 是 'L' 不是数字
 *      (应为 13) → toInt 永远失败 → 16 条 altitude 规则全部失效。改用正则。
 *   2. equipment_rules.json 使用的 8 个前缀 (uv_level / humidity / diurnal_range /
 *      wind_level / is_rainy_season / is_plateau / is_desert / is_coastal) 没有
 *      对应策略, matchCondition 打 "unknown prefix" 后返回 false → 11 条规则失效。
 *      现全部补齐。
 *   3. 复合条件 "altitude >= L4 AND season in [...]" 之前只按前缀取了 altitude
 *      一段; AND 拆分逻辑放在 EquipmentService::matchCondition。
 *   4. 取值语法 `in [a, b]` 之前各策略只认 `== 'x'`, 现统一支持。
 *
 * 2026-10-22 新增 (装备推荐区分度问题):
 *   1. 数值比较补 `<=` / `<` / `>` —— 保暖规则的写法是 "temp_min <= -10"
 *      (越冷越要穿), 只有 `>=` 时一条温度规则都写不出来。
 *   2. temp_min / temp_avg / load 三个前缀; load 是序数枚举, 同时支持
 *      `>= overnight` 与 `in [overnight, expedition]`。
 */
#pragma once

#include "EquipmentService.h"   // TripParameters / Season / Precipitation / EquipmentAltitudeLevel

#include <QHash>
#include <QRegularExpression>
#include <QString>
#include <QStringList>

namespace outdoor {

// 2026-09-23: 条件字符串解析工具 (策略共用)
namespace detail {

/**
 * @brief 去掉 "<prefix>" 与紧随的操作符 (== / in), 返回剩余 RHS 原文
 * @note 不裁剪引号, 因为 `in ['a','b']` 需要按逗号再切
 */
inline QString rhsAfterOperator(const QString& cond, const QString& prefix) {
    QString s = cond.trimmed();
    if (!s.startsWith(prefix)) return QString();
    s = s.mid(prefix.size()).trimmed();
    if (s.startsWith(QStringLiteral("=="))) {
        s = s.mid(2).trimmed();
    } else if (s.startsWith(QStringLiteral("in"))) {
        s = s.mid(2).trimmed();
    } else if (s.startsWith(QLatin1Char('='))) {
        s = s.mid(1).trimmed();
    }
    return s;
}

/** @brief 单个标量 RHS: 去操作符 + 去掉外层引号 ("is_desert == true" → "true") */
inline QString rhsOperand(const QString& cond, const QString& prefix) {
    QString s = rhsAfterOperator(cond, prefix);
    if (s.size() >= 2) {
        const QChar q = s.at(0);
        if ((q == QLatin1Char('\'') || q == QLatin1Char('"')) && s.endsWith(q))
            s = s.mid(1, s.size() - 2);
    }
    return s;
}

/**
 * @brief 取值列表: 同时支持 `== 'x'` 与 `in [a, b, 'c']` 两种写法
 * @return 去引号后的 token 列表 (空列表 = 语法不识别, 调用方应视为不匹配)
 */
inline QStringList enumValues(const QString& cond, const QString& prefix) {
    QString s = rhsAfterOperator(cond, prefix);
    if (s.isEmpty()) return {};
    if (s.startsWith(QLatin1Char('[')) && s.endsWith(QLatin1Char(']')))
        s = s.mid(1, s.size() - 2);

    QStringList out;
    const QStringList tokens = s.split(QLatin1Char(','), Qt::SkipEmptyParts);
    for (const QString& raw : tokens) {
        QString t = raw.trimmed();
        if (t.size() >= 2) {
            const QChar q = t.at(0);
            if ((q == QLatin1Char('\'') || q == QLatin1Char('"')) && t.endsWith(q))
                t = t.mid(1, t.size() - 2);
        }
        if (!t.isEmpty()) out << t;
    }
    return out;
}

/**
 * @brief 拆掉开头的比较符, 原地返回去掉操作符后的 RHS
 * @return 命中的操作符文本; 空串 = 不是比较写法
 */
inline QString takeCompareOp(QString& rhs) {
    static const QStringList ops = {
        QStringLiteral(">="), QStringLiteral("<="), QStringLiteral(">"), QStringLiteral("<")
    };
    QString t = rhs.trimmed();
    for (const QString& op : ops) {
        if (t.startsWith(op)) {
            rhs = t.mid(op.size()).trimmed();
            return op;
        }
    }
    rhs = t;
    return QString();
}

/** @brief actual <op> threshold */
inline bool applyCompare(double actual, const QString& op, double threshold) {
    if (op == QLatin1String(">=")) return actual >= threshold;
    if (op == QLatin1String("<=")) return actual <= threshold;
    if (op == QLatin1String(">"))  return actual >  threshold;
    if (op == QLatin1String("<"))  return actual <  threshold;
    return false;
}

/**
 * @brief 数值比较: `<prefix> >=|<=|>|< <num>`
 *
 * 2026-10-22: 取代只有 `>=` 的 numericGe —— 温度类规则的写法天然是反的,
 * "越冷越要保暖" 要写 `temp_min <= -10`, 没有 `<=` 就一条温度规则都挂得上,
 * 42 条规则里 0 条看温度就是这么来的。
 * @note 数字的 `==` 不走这里 (枚举的 == 由 enumValues 处理)
 */
inline bool numericCompare(const QString& cond, const QString& prefix, double actual) {
    QString rhs = rhsAfterOperator(cond, prefix);
    const QString op = takeCompareOp(rhs);
    if (op.isEmpty()) return false;
    bool ok = false;
    const double threshold = rhs.toDouble(&ok);
    return ok && applyCompare(actual, op, threshold);
}

/** @brief 比较符后的取值: ">= overnight" → "overnight" (枚举/序数条件用) */
inline QString compareOperand(const QString& cond, const QString& prefix, QString* opOut) {
    QString rhs = rhsAfterOperator(cond, prefix);
    const QString op = takeCompareOp(rhs);
    if (opOut) *opOut = op;
    return rhs;
}

/** @brief 枚举成员判定: vals 中任一 token 经 table 映射后等于 actual */
template <typename E>
inline bool anyEquals(const QStringList& vals, const QHash<QString, E>& table, E actual) {
    for (const QString& v : vals) {
        auto it = table.constFind(v);
        if (it != table.constEnd() && it.value() == actual) return true;
    }
    return false;
}

} // namespace detail

class RuleConditionStrategy {
public:
    virtual ~RuleConditionStrategy() = default;

    /**
     * @brief 前缀: 用于 Factory 索引,例如 "altitude" / "precipitation" / "season"
     * @note 必须小写且唯一
     */
    virtual QString prefix() const = 0;

    /**
     * @brief 评估 conditionStr 是否匹配 params
     * @return true 满足条件 / false 不满足
     */
    virtual bool matches(const QString& conditionStr,
                         const TripParameters& params) const = 0;
};

// ===== 数值 / 段位策略 =====

/** altitude >= L<N> (0-6) — 当前海拔段位 ≥ N */
class AltitudeCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("altitude"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        // 形式: "altitude >= L3" (也可能是复合条件的第一段)
        // 2026-09-23 修复: 之前用 cond.mid(12,1) 取段位数字, 但下标 12 是 'L'
        //   (数字在下标 13), toInt 永远失败 → 16 条 altitude 规则全灭。
        static const QRegularExpression re(
            QStringLiteral("^altitude\\s*>=\\s*L(\\d)"));
        const auto m = re.match(cond.trimmed());
        if (!m.hasMatch()) return false;
        bool ok = false;
        const int level = m.captured(1).toInt(&ok);
        if (!ok || level < 0 || level > 6) return false;
        const int current = static_cast<int>(EquipmentService::getAltitudeLevel(p.altitudeMax));
        return current >= level;
    }
};

/** wind_speed >= <double> (m/s) */
class WindSpeedCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("wind_speed"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        return detail::numericCompare(cond, QStringLiteral("wind_speed"), p.windSpeed);
    }
};

/** days >= <int> */
class DaysCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("days"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        return detail::numericCompare(cond, QStringLiteral("days"), p.days);
    }
};

/** difficulty >= <int> (1-5) */
class DifficultyCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("difficulty"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        return detail::numericCompare(cond, QStringLiteral("difficulty"), p.difficulty);
    }
};

/** diurnal_range >= <int> — 昼夜温差 (°C), 2026-09-23 新增 */
class DiurnalRangeCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("diurnal_range"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        return detail::numericCompare(cond, QStringLiteral("diurnal_range"), p.diurnalRange);
    }
};

/** temp_min <= <num> (°C) — 夜间最低气温, 2026-10-22 新增
 *  写法是 "temp_min <= -10" (越冷越要保暖), 保暖/防冻规则从此挂钩温度 */
class TempMinCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("temp_min"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        return detail::numericCompare(cond, QStringLiteral("temp_min"), p.tempMin);
    }
};

/** temp_avg <= <num> (°C) — 日间平均温度, 2026-10-22 新增
 *  用于防暑/补水这类"越热越要"的条件, 也可写 >= 表达低温风险 */
class TempAvgCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("temp_avg"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        return detail::numericCompare(cond, QStringLiteral("temp_avg"), p.tempAvg);
    }
};

/**
 * load >= overnight / load in [overnight, expedition] — 背负方式, 2026-10-22 新增
 * 序数即档位 (DayHike 0 → Expedition 3), `>=` 比大小, `in [...]` 走枚举表。
 */
class LoadCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("load"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        static const QHash<QString, LoadStyle> table = {
            { QStringLiteral("day_hike"),   LoadStyle::DayHike   },
            { QStringLiteral("fast_pack"),  LoadStyle::FastPack  },
            { QStringLiteral("overnight"),  LoadStyle::Overnight },
            { QStringLiteral("expedition"), LoadStyle::Expedition },
        };
        QString op;
        const QString rhs = detail::compareOperand(cond, prefix(), &op);
        if (!op.isEmpty()) {
            auto it = table.constFind(rhs);
            if (it == table.constEnd()) return false;
            return detail::applyCompare(static_cast<int>(p.load), op,
                                       static_cast<int>(it.value()));
        }
        return detail::anyEquals(detail::enumValues(cond, prefix()), table, p.load);
    }
};

// ===== 枚举策略 (支持 == 'x' 与 in [a, b]) =====

/** precipitation == 'light'|'moderate'|'heavy'|'storm' / in [heavy, storm]
 *  2026-10-21: 补 snow_* 四档, 冬季表单的降水行按降雪出选项 */
class PrecipitationCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("precipitation"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        static const QHash<QString, Precipitation> table = {
            { QStringLiteral("light"),        Precipitation::Light        },
            { QStringLiteral("moderate"),     Precipitation::Moderate     },
            { QStringLiteral("heavy"),        Precipitation::Heavy        },
            { QStringLiteral("storm"),        Precipitation::Storm        },
            { QStringLiteral("snow_light"),    Precipitation::SnowLight    },
            { QStringLiteral("snow_moderate"), Precipitation::SnowModerate },
            { QStringLiteral("snow_heavy"),    Precipitation::SnowHeavy    },
            { QStringLiteral("snow_storm"),    Precipitation::SnowStorm    },
        };
        return detail::anyEquals(
            detail::enumValues(cond, QStringLiteral("precipitation")), table, p.precipitation);
    }
};

/** season == 'spring'|'summer'|'autumn'|'winter' / in [winter, spring, autumn] */
class SeasonCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("season"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        static const QHash<QString, Season> table = {
            { QStringLiteral("spring"), Season::Spring },
            { QStringLiteral("summer"), Season::Summer },
            { QStringLiteral("autumn"), Season::Autumn },
            { QStringLiteral("winter"), Season::Winter },
        };
        return detail::anyEquals(
            detail::enumValues(cond, QStringLiteral("season")), table, p.season);
    }
};

/** humidity == 'dry'|'moderate'|'humid' — 2026-09-23 新增 */
class HumidityCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("humidity"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        static const QHash<QString, HumidityType> table = {
            { QStringLiteral("dry"),      HumidityType::Dry      },
            { QStringLiteral("moderate"), HumidityType::Moderate },
            { QStringLiteral("humid"),    HumidityType::Humid    },
        };
        return detail::anyEquals(
            detail::enumValues(cond, QStringLiteral("humidity")), table, p.humidity);
    }
};

/** uv_level == 'extreme' / in ['strong', 'very_strong', 'extreme'] — 2026-09-23 新增 */
class UVLevelCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("uv_level"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        static const QHash<QString, UVLevel> table = {
            { QStringLiteral("weak"),        UVLevel::Weak       },
            { QStringLiteral("moderate"),    UVLevel::Moderate   },
            { QStringLiteral("strong"),      UVLevel::Strong     },
            { QStringLiteral("very_strong"), UVLevel::VeryStrong },
            { QStringLiteral("extreme"),     UVLevel::Extreme    },
        };
        return detail::anyEquals(
            detail::enumValues(cond, QStringLiteral("uv_level")), table, p.uvLevel);
    }
};

/** wind_level in ['strong', 'gale'] — 2026-09-23 新增 */
class WindLevelCondition : public RuleConditionStrategy {
public:
    QString prefix() const override { return QStringLiteral("wind_level"); }
    bool matches(const QString& cond, const TripParameters& p) const override {
        static const QHash<QString, WindLevel> table = {
            { QStringLiteral("calm"),     WindLevel::Calm     },
            { QStringLiteral("light"),    WindLevel::Light    },
            { QStringLiteral("moderate"), WindLevel::Moderate },
            { QStringLiteral("strong"),   WindLevel::Strong   },
            { QStringLiteral("gale"),     WindLevel::Gale     },
        };
        return detail::anyEquals(
            detail::enumValues(cond, QStringLiteral("wind_level")), table, p.windLevel);
    }
};

// ===== 布尔标记策略 (is_* == true) =====

/** is_* == true/false 通用基类; 子类只需给 prefix + 取值 */
class BoolFlagCondition : public RuleConditionStrategy {
public:
    bool matches(const QString& cond, const TripParameters& p) const override {
        const QString pfx = prefix();
        if (!cond.trimmed().startsWith(pfx)) return false;
        const QString rhs = detail::rhsOperand(cond, pfx);
        // 省略 RHS ("is_desert") 视为 true; 显式 false/0 为 false
        const bool want = !(rhs == QStringLiteral("false") || rhs == QStringLiteral("0"));
        return value(p) == want;
    }

protected:
    virtual bool value(const TripParameters& p) const = 0;
};

/** is_rainy_season == true — 2026-09-23 新增 */
class RainySeasonCondition : public BoolFlagCondition {
public:
    QString prefix() const override { return QStringLiteral("is_rainy_season"); }
protected:
    bool value(const TripParameters& p) const override { return p.isRainySeason; }
};

/** is_plateau == true — 2026-09-23 新增 */
class PlateauCondition : public BoolFlagCondition {
public:
    QString prefix() const override { return QStringLiteral("is_plateau"); }
protected:
    bool value(const TripParameters& p) const override { return p.isPlateau; }
};

/** is_desert == true — 2026-09-23 新增 */
class DesertCondition : public BoolFlagCondition {
public:
    QString prefix() const override { return QStringLiteral("is_desert"); }
protected:
    bool value(const TripParameters& p) const override { return p.isDesert; }
};

/** is_coastal == true — 2026-09-23 新增 */
class CoastalCondition : public BoolFlagCondition {
public:
    QString prefix() const override { return QStringLiteral("is_coastal"); }
protected:
    bool value(const TripParameters& p) const override { return p.isCoastal; }
};

} // namespace outdoor
