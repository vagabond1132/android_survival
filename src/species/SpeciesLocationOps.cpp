/**
 * @file SpeciesLocationOps.cpp
 * @brief 物种位置记录 协调层 实现 (2026-09-21 阶段 L4.2)
 *
 * 替代 4 个服务里重复的 dbOpenCheck + Repository::record/listByEntity + Result 包装.
 */

#include "SpeciesLocationOps.h"
#include "SpeciesLocationRepository.h"
#include "../common/DbHelper.h"
#include "../core/Database.h"
#include "../core/Logger.h"
#include "../core/Result.h"
#include "../core/ServiceErrors.h"
#include "../core/internal/QmlResultBridge.h"

#include <QSqlDatabase>
#include <QSqlQuery>

namespace outdoor {

QVariantMap SpeciesLocationOps::recordLocation(Database* db,
                                                SpeciesLocationRepository::Kind kind,
                                                const QString& entityId,
                                                double lat, double lon,
                                                const QString& note) {
    using namespace outdoor::internal;
    const char* ctx = "SpeciesLocationOps::recordLocation";

    if (auto e = dbOpenCheck(db, Database::Name::Settings, ctx)) return *e;
    const QSqlDatabase sqlDb = db->get(Database::Name::Settings);
    const bool ok = SpeciesLocationRepository::record(sqlDb, kind, entityId, lat, lon, note);
    if (!ok) {
        return toQVariant(Err<bool>(ServiceErrorCode::DbError,
                                      QStringLiteral("record 失败"), ctx));
    }
    return toQVariant(Ok(true));
}

QVariantList SpeciesLocationOps::listByEntity(Database* db,
                                                 SpeciesLocationRepository::Kind kind,
                                                 const QString& entityId,
                                                 const QString& entityIdField) {
    if (!db || !db->isOpen(Database::Name::Settings)) return {};
    const QSqlDatabase sqlDb = db->get(Database::Name::Settings);
    QVariantList list = SpeciesLocationRepository::listByEntity(sqlDb, kind, entityId);
    // 补 entityId 字段 (QML 端依赖此字段, Repository 不负责 UI 字段名)
    for (auto& v : list) {
        QVariantMap m = v.toMap();
        m[entityIdField] = entityId;
        v = m;
    }
    return list;
}

QVariantList SpeciesLocationOps::listNear(Database* db,
                                            SpeciesLocationRepository::Kind kind,
                                            double lat, double lon) {
    QVariantList list;
    if (!db || !db->isOpen(Database::Name::Settings)) return list;
    const QSqlDatabase sqlDb = db->get(Database::Name::Settings);
    QSqlQuery q(sqlDb);
    // 与原 AnimalService/PlantService 实现一致: ABS(lat - ?) < 0.5 AND ABS(lon - ?) < 0.5
    if (DbHelper::execSelectPositional(q,
            QString("SELECT id, %1, lat, lon, found_at, note FROM %2 "
                    "WHERE ABS(lat - ?) < 0.5 AND ABS(lon - ?) < 0.5")
                .arg(SpeciesLocationRepository::idColumn(kind),
                     SpeciesLocationRepository::tableName(kind)),
            {lat, lon},
            QStringLiteral("SpeciesLocationOps::listNear(%1)")
                .arg(SpeciesLocationRepository::tableName(kind)))) {
        while (q.next()) {
            QVariantMap m;
            m["id"] = q.value(0).toLongLong();
            m["entityId"] = q.value(1).toString();  // 通用字段名 (animal/plant/...)
            m["lat"] = q.value(2).toDouble();
            m["lon"] = q.value(3).toDouble();
            m["foundAt"] = q.value(4).toString();
            m["note"] = q.value(5).toString();
            list.append(m);
        }
    }
    return list;
}

} // namespace outdoor