/**
 * @file RuleConditionFactory.cpp
 * @brief 工厂实现 - 注册表 + 17 个内置策略
 */
#include "RuleConditionFactory.h"

#include <QHash>
#include <QStringList>
#include <QMutex>
#include <QRecursiveMutex>  // 2026-09-23: Qt 6 移除 QMutex::Recursive, 改用 QRecursiveMutex 类

namespace outdoor {

namespace {

QHash<QString, RuleConditionFactory::Creator>& registry() {
    static QHash<QString, RuleConditionFactory::Creator> r;
    return r;
}

QRecursiveMutex& registryMutex() {
    // 2026-09-23: 改为 QRecursiveMutex. Qt 6 移除了 QMutex::Recursive enum,
    // 必须用 QRecursiveMutex 类. initializeDefaults() 持锁再调 registerStrategy(),
    // 后者也会 QMutexLocker 同一 mutex. 默认非递归 mutex 同线程二次加锁会
    // 永久阻塞 → App 启动卡死在 EquipmentService::initialize().
    // QMutexLocker 是模板, QMutex / QRecursiveMutex 都兼容, 调用方无需改.
    static QRecursiveMutex m;
    return m;
}

bool g_defaultsInitialized = false;

} // anonymous

void RuleConditionFactory::registerStrategy(const QString& prefix, Creator creator) {
    QMutexLocker lock(&registryMutex());
    registry().insert(prefix, std::move(creator));
}

std::unique_ptr<RuleConditionStrategy> RuleConditionFactory::create(const QString& prefix) {
    QMutexLocker lock(&registryMutex());
    auto it = registry().constFind(prefix);
    if (it == registry().constEnd()) return nullptr;
    return it.value()();
}

QStringList RuleConditionFactory::registeredPrefixes() {
    QMutexLocker lock(&registryMutex());
    return QStringList(registry().keys());
}

void RuleConditionFactory::clear() {
    QMutexLocker lock(&registryMutex());
    registry().clear();
    g_defaultsInitialized = false;
}

void RuleConditionFactory::initializeDefaults() {
    if (g_defaultsInitialized) return;
    QMutexLocker lock(&registryMutex());

    registerStrategy(QStringLiteral("altitude"),     [] { return std::make_unique<AltitudeCondition>();     });
    registerStrategy(QStringLiteral("precipitation"), [] { return std::make_unique<PrecipitationCondition>(); });
    registerStrategy(QStringLiteral("season"),        [] { return std::make_unique<SeasonCondition>();        });
    registerStrategy(QStringLiteral("wind_speed"),    [] { return std::make_unique<WindSpeedCondition>();    });
    registerStrategy(QStringLiteral("days"),          [] { return std::make_unique<DaysCondition>();          });
    registerStrategy(QStringLiteral("difficulty"),    [] { return std::make_unique<DifficultyCondition>();    });

    // 2026-09-23 补注册: equipment_rules.json 实际使用但之前无策略的 8 个前缀,
    // 否则 matchCondition 打 "unknown prefix" 后返回 false → 11 条规则永久失效。
    registerStrategy(QStringLiteral("diurnal_range"),   [] { return std::make_unique<DiurnalRangeCondition>(); });
    registerStrategy(QStringLiteral("humidity"),        [] { return std::make_unique<HumidityCondition>();     });
    registerStrategy(QStringLiteral("uv_level"),        [] { return std::make_unique<UVLevelCondition>();     });
    registerStrategy(QStringLiteral("wind_level"),      [] { return std::make_unique<WindLevelCondition>();   });
    registerStrategy(QStringLiteral("is_rainy_season"), [] { return std::make_unique<RainySeasonCondition>(); });
    registerStrategy(QStringLiteral("is_plateau"),      [] { return std::make_unique<PlateauCondition>();     });
    registerStrategy(QStringLiteral("is_desert"),       [] { return std::make_unique<DesertCondition>();      });
    registerStrategy(QStringLiteral("is_coastal"),      [] { return std::make_unique<CoastalCondition>();     });

    // 2026-10-22 补注册: 温度与背负方式两个维度。
    //   temp_min / temp_avg —— 之前 42 条规则里 0 条看温度, 保暖档位跟冷暖无关;
    //   load —— 轻装/重装以前不区分, 两条行程清单完全一致。
    registerStrategy(QStringLiteral("temp_min"),       [] { return std::make_unique<TempMinCondition>();       });
    registerStrategy(QStringLiteral("temp_avg"),       [] { return std::make_unique<TempAvgCondition>();       });
    registerStrategy(QStringLiteral("load"),           [] { return std::make_unique<LoadCondition>();           });

    g_defaultsInitialized = true;
}

} // namespace outdoor