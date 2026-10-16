/**
 * @file SpeciesLocationRepository.cpp
 * @brief 物种位置记录通用实现 (2026-09-21 阶段 L4.2 从 LocationStorageHelper 改名)
 *
 * 2026-09-21 阶段 L2.2 切 DbHelper
 * 2026-09-21 阶段 L4.2 重命名 Helper → Repository
 */

#include "SpeciesLocationRepository.h"
#include "../common/DbHelper.h"
#include "../core/Logger.h"

#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QDateTime>

namespace outdoor {

bool SpeciesLocationRepository::record(const QSqlDatabase& db, Kind kind,
                                        const QString& entityId,
                                        double lat, double lon,
                                        const QString& note) {
    // 2026-09-17: 早退空 entityId, 避免写入无主记录
    if (entityId.isEmpty()) {
        Logger::warn(QString("SpeciesLocationRepository::record(%1) skipped: empty entityId")
                         .arg(tableName(kind)));
        return false;
    }
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        QString("INSERT INTO %1 (%2, lat, lon, found_at, note) "
                "VALUES (?, ?, ?, ?, ?)")
            .arg(tableName(kind), idColumn(kind)),
        {entityId, lat, lon,
         QDateTime::currentDateTime().toString(Qt::ISODate), note},
        QStringLiteral("SpeciesLocationRepository::record(%1)").arg(tableName(kind)));
    return rc == DmlResult::Ok;
}

QVariantList SpeciesLocationRepository::listByEntity(const QSqlDatabase& db, Kind kind,
                                                       const QString& entityId) {
    QVariantList list;
    QSqlQuery q(db);
    if (!DbHelper::execSelectPositional(q,
            QString("SELECT id, lat, lon, found_at, note FROM %1 "
                    "WHERE %2 = ? ORDER BY found_at DESC")
                .arg(tableName(kind), idColumn(kind)),
            {entityId},
            QStringLiteral("SpeciesLocationRepository::listByEntity(%1)").arg(tableName(kind)))) {
        return list;
    }
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toLongLong();
        m["lat"] = q.value(1).toDouble();
        m["lon"] = q.value(2).toDouble();
        m["foundAt"] = q.value(3).toString();
        m["note"] = q.value(4).toString();
        list.append(m);
    }
    return list;
}

bool SpeciesLocationRepository::deleteByEntity(const QSqlDatabase& db, Kind kind,
                                                 const QString& entityId) {
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        QString("DELETE FROM %1 WHERE %2 = ?")
            .arg(tableName(kind), idColumn(kind)),
        {entityId},
        QStringLiteral("SpeciesLocationRepository::deleteByEntity(%1)").arg(tableName(kind)));
    return rc == DmlResult::Ok;
}

// 2026-09-21 阶段 L4.2: 提到 .cpp (供 SpeciesLocationOps 拼 SQL 用)
QString SpeciesLocationRepository::tableName(Kind kind) {
    switch (kind) {
    case Kind::Plant: return "plant_locations";
    case Kind::Animal: return "animal_locations";
    case Kind::Insect: return "insect_locations";
    case Kind::Mushroom: return "mushroom_locations";
    }
    return {};
}

QString SpeciesLocationRepository::idColumn(Kind kind) {
    switch (kind) {
    case Kind::Plant: return "plant_id";
    case Kind::Animal: return "animal_id";
    case Kind::Insect: return "insect_id";
    case Kind::Mushroom: return "mushroom_id";
    }
    return {};
}

} // namespace outdoor