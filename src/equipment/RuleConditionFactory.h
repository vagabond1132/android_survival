/**
 * @file RuleConditionFactory.h
 * @brief 装备规则条件策略工厂 (5 阶段架构重构 Phase 3)
 *
 * 用法:
 *   auto strat = RuleConditionFactory::create("altitude");
 *   if (strat) {
 *       bool ok = strat->matches("altitude >= L3", tripParams);
 *   }
 *
 * 新增策略:
 *   1. 在 RuleConditionStrategy.h 加子类
 *   2. 在本 .cpp 的 initializeDefaults() 加一行 register
 *   3. 无需改 EquipmentService
 */
#pragma once

#include "RuleConditionStrategy.h"

#include <functional>
#include <memory>
#include <QString>

namespace outdoor {

class RuleConditionFactory {
public:
    using Creator = std::function<std::unique_ptr<RuleConditionStrategy>()>;

    /** 注册策略 (按 prefix 索引,后注册的覆盖先注册的) */
    static void registerStrategy(const QString& prefix, Creator creator);

    /** 创建策略。prefix 未注册时返回 nullptr */
    static std::unique_ptr<RuleConditionStrategy> create(const QString& prefix);

    /** 列出所有已注册前缀 (调试用) */
    static QStringList registeredPrefixes();

    /** 卸载全部 (测试用) */
    static void clear();

    /**
     * 一次性注册 14 个内置策略:
     *   altitude / precipitation / season / wind_speed / days / difficulty
     *   diurnal_range / humidity / uv_level / wind_level
     *   is_rainy_season / is_plateau / is_desert / is_coastal
     * (后 8 个 2026-09-23 补齐, 对齐 equipment_rules.json 实际使用的前缀)
     */
    static void initializeDefaults();
};

} // namespace outdoor