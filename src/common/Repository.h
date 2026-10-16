/**
 * @file Repository.h
 * @brief 通用 Repository 接口 (阶段 L4.2)
 *
 * 设计意图:
 * - 把"按 ID 查 / 查全部 / 存 / 删"四件套抽出来
 * - 每个具体 Repository 继承并实现 (Plant / Animal / Insect / Mushroom 共享一套逻辑)
 * - 不强求泛型全部场景;CRUD 模板留给 QueryTemplate.h
 *
 * 用法示例:
 *   class SpeciesLocationRepository : public IRepository<SpeciesLocation> { ... };
 *
 * 命名规范: 见 doc/05-工程规范/NamingSpec.md §1 (类名前缀 *Repository)
 */

#pragma once

#include <QString>
#include <QList>
#include <optional>

#include "../core/Result.h"

namespace outdoor {

/**
 * @brief 数据实体基接口 (空标记, 仅约束 T 有 default ctor)
 *
 * 具体实体 (SpeciesLocation, FieldGuideRecord, KnotProgress 等) 不必继承,
 * 仅需满足 std::is_default_constructible<T> 即可作为模板参数.
 */
template<typename T>
class IRepository {
public:
    virtual ~IRepository() = default;

    /**
     * @brief 按主键查一条
     * @return 找到则 filled, 否则 std::nullopt
     */
    virtual std::optional<T> findById(const QString& id) = 0;

    /**
     * @brief 列出全部
     */
    virtual QList<T> findAll() = 0;

    /**
     * @brief 保存实体 (新建或更新由实现决定)
     * @return 成功 Ok(主键 ID) / 失败 Err
     */
    virtual Result<QString> save(const T& entity) = 0;

    /**
     * @brief 按主键删除
     * @return 成功 Ok / 失败 Err
     */
    virtual Result<std::monostate> remove(const QString& id) = 0;
};

} // namespace outdoor