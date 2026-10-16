/**
 * @file SpeciesLocationRepository.h
 * @brief 物种位置记录通用 Repository (2026-09-21 阶段 L4.2)
 *
 * 4 张表结构相同,只是表名 + entity_id 列名前缀不同:
 *   - plant_locations    (plant_id)
 *   - animal_locations   (animal_id)
 *   - insect_locations   (insect_id)
 *   - mushroom_locations (mushroom_id)
 *
 * 由 LocationStorageHelper 重命名而来 — Helper 已升级为 Repository 风格,
 * 因为有独立的 entity (SpeciesLocation) + 标准的 find/save/remove 接口,
 * 属于数据访问层,符合 *Repository 类名前缀约定。
 *
 * 注:目前签名仍与原 Helper 兼容 (record/listByEntity/deleteByEntity),
 *     后续可选择实现 IRepository<SpeciesLocation>。
 */

#pragma once

#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QDateTime>

class QSqlDatabase;

namespace outdoor {

/**
 * @class SpeciesLocationRepository
 * @brief 物种位置记录(4 张表共享)
 */
class SpeciesLocationRepository {
public:
    /**
     * @brief 物种大类 (4 张表对应)
     */
    enum class Kind { Plant, Animal, Insect, Mushroom };

    /**
     * @brief 记录一条位置
     * @return 成功 true
     */
    static bool record(const QSqlDatabase& db, Kind kind,
                       const QString& entityId,
                       double lat, double lon,
                       const QString& note = QString());

    /**
     * @brief 按 entityId 查询
     */
    static QVariantList listByEntity(const QSqlDatabase& db, Kind kind,
                                       const QString& entityId);

    /**
     * @brief 按 entityId 删除
     */
    static bool deleteByEntity(const QSqlDatabase& db, Kind kind,
                                  const QString& entityId);

    // 2026-09-21 阶段 L4.2: SpeciesLocationOps 需要拿表名/列名拼 SQL, 提到 public
    static QString tableName(Kind kind);
    static QString idColumn(Kind kind);

private:
    // 旧位置 (已移至 public)
};

} // namespace outdoor