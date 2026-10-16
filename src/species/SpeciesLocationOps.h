/**
 * @file SpeciesLocationOps.h
 * @brief 物种位置记录 协调层 (2026-09-21 阶段 L4.2)
 *
 * 职责:
 *   - 把 4 个物种服务 (Animal/Insect/Mushroom/Plant) 的 recordLocation /
 *     getLocationsByXxx / getLocationsNear 重复代码收敛到一处
 *   - 上层 (SpeciesLocationRepository) 只管 SQL,
 *     Ops 层负责 DB 检查 + QVariantMap 包装 + 补 entityId 字段
 *
 * 设计动机:
 *   - 4 个服务的 recordLocation 实现完全相同 (dbOpenCheck + Repository::record + 包装 Result)
 *   - getLocationsByXxx 仅"补 entityId 字段名" 不同 (animalId/insectId/...)
 *   - getLocationsNear SQL 表名/列名/字段名不同, 可通过 Kind + entityIdField 参数化
 *
 * 与 SpeciesLocationRepository 的区别:
 *   - Repository: 返回 bool / QVariantList, 不做错误包装, 不检查 DB 是否打开
 *   - Ops:       返回 QVariantMap (record) / QVariantList (read), 做 dbOpenCheck + 包装
 *
 * 使用示例:
 *   // recordLocation
 *   return SpeciesLocationOps::recordLocation(m_db, Kind::Animal, animalId, lat, lon, note);
 *
 *   // getLocationsByAnimal (补 "animalId" 字段)
 *   return SpeciesLocationOps::listByEntity(m_db, Kind::Animal, animalId, "animalId");
 *
 *   // getLocationsNear
 *   return SpeciesLocationOps::listNear(m_db, Kind::Plant, lat, lon);
 */

#pragma once

#include "SpeciesLocationRepository.h"  // 复用 Kind 枚举

#include <QVariantList>
#include <QVariantMap>
#include <QString>

class QSqlDatabase;

namespace outdoor {

class Database;  // forward decl

/**
 * @class SpeciesLocationOps
 * @brief 物种位置记录协调层 (DB 检查 + Result 包装 + 字段补全)
 *
 * 纯静态, 不持状态, 不需要 QObject.
 */
class SpeciesLocationOps {
public:
    /**
     * @brief 写入一条位置记录,失败 → DbError 信封
     * @param db          Database* (持有 Settings db)
     * @param kind        物种大类
     * @param entityId    实体 ID (植物 ID / 动物 ID / ...)
     * @param lat / lon   经纬度
     * @param note        备注 (可空)
     * @return 成功 → {ok:true, value:true}; 失败 → {ok:false, error:{...}}
     */
    static QVariantMap recordLocation(Database* db,
                                       SpeciesLocationRepository::Kind kind,
                                       const QString& entityId,
                                       double lat, double lon,
                                       const QString& note);

    /**
     * @brief 按 entityId 查询该物种的所有位置记录,并补上 entityId 字段
     * @param db              Database*
     * @param kind            物种大类
     * @param entityId        实体 ID
     * @param entityIdField   QML 字段名 ("animalId" / "insectId" / "mushroomId" / "plantId")
     * @return QVariantList (失败/DB 未开 → 空 list,不报 error)
     */
    static QVariantList listByEntity(Database* db,
                                      SpeciesLocationRepository::Kind kind,
                                      const QString& entityId,
                                      const QString& entityIdField);

    /**
     * @brief 查询附近的位置记录 (经纬度方框过滤, 全表扫描)
     * @param db          Database*
     * @param kind        物种大类
     * @param lat / lon   中心点经纬度
     * @return QVariantList (失败/DB 未开 → 空 list)
     */
    static QVariantList listNear(Database* db,
                                  SpeciesLocationRepository::Kind kind,
                                  double lat, double lon);
};

} // namespace outdoor