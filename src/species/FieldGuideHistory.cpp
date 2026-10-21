/**
 * @file FieldGuideHistory.cpp
 * @brief 图鉴浏览历史实现
 *
 * 替代原 RecognitionStorage(AI 识别历史)。
 * 2026-08-27 V2 重构:不再有 AI 识别,改为图鉴浏览历史。
 * 兼容: 旧 recognition_history 表保留(不动),新表 field_guide_history 独立建。
 */

#include "FieldGuideHistory.h"
#include "../core/Database.h"
#include "../core/Logger.h"
#include "../core/Result.h"                 // 2026-09-21: 阶段 L3.7
#include "../core/ServiceErrors.h"          // 2026-09-21: 阶段 L3.7
#include "../core/internal/QmlResultBridge.h" // 2026-09-21: 阶段 L3.7
#include "../common/DbHelper.h"  // 2026-09-21: Phase 2 DbHelper 统一 DDL 错误日志

#include <QSqlQuery>
#include <QSqlError>

namespace outdoor {

FieldGuideHistory::FieldGuideHistory(Database* db, QObject* parent)
    
    : ServiceBase(db, "FieldGuideHistory", parent) {
    ensureSchema();
    refreshCounts();
}

FieldGuideHistory::~FieldGuideHistory() {
}

bool FieldGuideHistory::ensureSchema() {
    if (!m_db || !m_db->isOpen(Database::Name::Settings)) return false;

    QSqlDatabase db = m_db->get(Database::Name::Settings);
    QSqlQuery q(db);

    // 2026-09-21: Phase 2 - 改用 DbHelper::execDdl, 失败自动 log
    int failed = 0;
    const char* tag = "FieldGuideHistory::ensureSchema";

    if (!DbHelper::execDdl(q, R"(
        CREATE TABLE IF NOT EXISTS field_guide_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_id TEXT NOT NULL,
            kingdom TEXT NOT NULL,
            common_name TEXT,
            scientific_name TEXT,
            category TEXT,
            danger_level INTEGER DEFAULT 0,
            view_source TEXT,
            route_id TEXT,
            first_aid_id TEXT,
            location_lat REAL,
            location_lon REAL,
            note TEXT,
            is_favorite INTEGER DEFAULT 0,
            viewed_at TEXT NOT NULL
        )
    )", tag)) ++failed;

    if (!DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_fgh_viewed ON field_guide_history(viewed_at DESC)", tag)) ++failed;
    if (!DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_fgh_entity ON field_guide_history(entity_id)", tag)) ++failed;
    if (!DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_fgh_kingdom ON field_guide_history(kingdom)", tag)) ++failed;
    if (!DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_fgh_route ON field_guide_history(route_id)", tag)) ++failed;
    if (!DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_fgh_favorite ON field_guide_history(is_favorite)", tag)) ++failed;

    return failed == 0;
}

void FieldGuideHistory::refreshCounts() {
    if (!m_db || !m_db->isOpen(Database::Name::Settings)) return;
    QSqlDatabase db = m_db->get(Database::Name::Settings);

    auto count = [&](const QString& where) {
        // 2026-09-21 阶段 L2.2: 切 DbHelper::execSelect / execSelectPositional
        QSqlQuery q(db);  // 每次 new 避免状态污染
        QString sql = "SELECT COUNT(*) FROM field_guide_history";
        QString tag = QStringLiteral("FieldGuideHistory::refreshCounts[") + where + "]";
        bool ok = where.isEmpty()
            ? DbHelper::execSelect(q, sql, {}, tag)
            : DbHelper::execSelectPositional(q, sql + " WHERE " + where, {}, tag);
        if (!ok) return 0;
        return q.next() ? q.value(0).toInt() : 0;
    };

    m_totalCount = count("");
    m_plantCount = count("kingdom = 'plantae'");
    m_animalCount = count("kingdom = 'animalia'");
    m_insectCount = count("kingdom = 'insecta'");
    m_mushroomCount = count("kingdom = 'fungi'");
}

// 2026-09-21: 阶段 L3.7 - addRecord 返回 Result<qint64> (value=id)
QVariantMap FieldGuideHistory::addRecord(const ViewRecord& record) {
    using namespace outdoor::internal;
    const char* ctx = "FieldGuideHistory::addRecord";

    if (auto e = dbOpenCheck(m_db, Database::Name::Settings, ctx)) return *e;

    QSqlDatabase db = m_db->get(Database::Name::Settings);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        R"(INSERT INTO field_guide_history
           (entity_id, kingdom, common_name, scientific_name, category, danger_level,
            view_source, route_id, first_aid_id, location_lat, location_lon,
            note, is_favorite, viewed_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?))",
        {record.entityId, record.kingdom, record.commonName, record.scientificName,
         record.category, record.dangerLevel, record.viewSource, record.routeId,
         record.firstAidId,
         record.location.isValid() ? QVariant(record.location.latitude()) : QVariant(),
         record.location.isValid() ? QVariant(record.location.longitude()) : QVariant(),
         record.note, record.isFavorite ? 1 : 0,
         record.viewedAt.isValid()
             ? record.viewedAt.toString(Qt::ISODate)
             : QDateTime::currentDateTime().toString(Qt::ISODate)},
        ctx);
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }

    qint64 id = q.lastInsertId().toLongLong();
    refreshCounts();
    emit recordAdded(id);
    emit dataChanged();
    return toQVariant(Ok(id));
}

// 2026-09-21 阶段 L4.x: 6 个简单写方法切到 execDmlReturning (addRecord 因需 lastInsertId 保留模板)
QVariantMap FieldGuideHistory::deleteRecord(qint64 id) {
    using namespace outdoor::internal;
    const QString ctx = "FieldGuideHistory::deleteRecord";
    auto err = execDmlReturning(m_db, Database::Name::Settings, ctx,
        [&id, &ctx](QSqlQuery& q) {
            return DbHelper::execDmlPositional(q,
                "DELETE FROM field_guide_history WHERE id = ?", {id}, ctx);
        });
    if (!isOk(err)) return err;
    refreshCounts();
    emit recordDeleted(id);
    emit dataChanged();
    return toQVariant(Ok(true));
}

QVariantMap FieldGuideHistory::deleteByEntity(const QString& entityId) {
    using namespace outdoor::internal;
    const QString ctx = "FieldGuideHistory::deleteByEntity";
    auto err = execDmlReturning(m_db, Database::Name::Settings, ctx,
        [&entityId, &ctx](QSqlQuery& q) {
            return DbHelper::execDmlPositional(q,
                "DELETE FROM field_guide_history WHERE entity_id = ?", {entityId}, ctx);
        });
    if (!isOk(err)) return err;
    refreshCounts();
    emit dataChanged();
    return toQVariant(Ok(true));
}

QVariantMap FieldGuideHistory::deleteAll() {
    using namespace outdoor::internal;
    const QString ctx = "FieldGuideHistory::deleteAll";
    auto err = execDmlReturning(m_db, Database::Name::Settings, ctx,
        [&ctx](QSqlQuery& q) {
            return DbHelper::execDml(q,
                "DELETE FROM field_guide_history", {}, ctx);
        });
    if (!isOk(err)) return err;
    refreshCounts();
    emit dataChanged();
    return toQVariant(Ok(true));
}

QVariantList FieldGuideHistory::getRecent(int limit) {
    if (!m_db || !m_db->isOpen(Database::Name::Settings)) return {};
    QSqlDatabase db = m_db->get(Database::Name::Settings);
    QSqlQuery q(db);
    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectList
    return DbHelper::selectList(q,
        "SELECT id, entity_id, kingdom, common_name, scientific_name, "
        "category, danger_level, view_source, route_id, first_aid_id, "
        "is_favorite, viewed_at "
        "FROM field_guide_history ORDER BY viewed_at DESC LIMIT ?",
        {limit},
        "FieldGuideHistory::getRecent",
        [](const QSqlQuery& q) {
            QVariantMap m;
            m["id"] = q.value(0).toLongLong();
            m["entityId"] = q.value(1).toString();
            m["kingdom"] = q.value(2).toString();
            m["commonName"] = q.value(3).toString();
            m["scientificName"] = q.value(4).toString();
            m["category"] = q.value(5).toString();
            m["dangerLevel"] = q.value(6).toInt();
            m["viewSource"] = q.value(7).toString();
            m["routeId"] = q.value(8).toString();
            m["firstAidId"] = q.value(9).toString();
            m["isFavorite"] = q.value(10).toBool();
            m["viewedAt"] = q.value(11).toString();
            return m;
        });
}

QVariantList FieldGuideHistory::getByKingdom(const QString& kingdom, int limit) {
    if (!m_db || !m_db->isOpen(Database::Name::Settings)) return {};
    QSqlDatabase db = m_db->get(Database::Name::Settings);
    QSqlQuery q(db);
    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectList
    return DbHelper::selectList(q,
        "SELECT id, entity_id, common_name, scientific_name, category, "
        "danger_level, is_favorite, viewed_at "
        "FROM field_guide_history WHERE kingdom = ? "
        "ORDER BY viewed_at DESC LIMIT ?",
        {kingdom, limit},
        "FieldGuideHistory::getByKingdom",
        [](const QSqlQuery& q) {
            QVariantMap m;
            m["id"] = q.value(0).toLongLong();
            m["entityId"] = q.value(1).toString();
            m["commonName"] = q.value(2).toString();
            m["scientificName"] = q.value(3).toString();
            m["category"] = q.value(4).toString();
            m["dangerLevel"] = q.value(5).toInt();
            m["isFavorite"] = q.value(6).toBool();
            m["viewedAt"] = q.value(7).toString();
            return m;
        });
}

QVariantList FieldGuideHistory::getByRoute(const QString& routeId) {
    if (!m_db || !m_db->isOpen(Database::Name::Settings)) return {};
    QSqlDatabase db = m_db->get(Database::Name::Settings);
    QSqlQuery q(db);
    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectList + 共享 rowToShortRecord
    return DbHelper::selectList(q,
        "SELECT id, entity_id, kingdom, common_name, category, danger_level, viewed_at "
        "FROM field_guide_history WHERE route_id = ? "
        "ORDER BY viewed_at DESC",
        {routeId},
        "FieldGuideHistory::getByRoute",
        &FieldGuideHistory::rowToShortRecord);
}

QVariantList FieldGuideHistory::getByFirstAid(const QString& firstAidId) {
    if (!m_db || !m_db->isOpen(Database::Name::Settings)) return {};
    QSqlDatabase db = m_db->get(Database::Name::Settings);
    QSqlQuery q(db);
    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectList + 共享 rowToShortRecord
    return DbHelper::selectList(q,
        "SELECT id, entity_id, kingdom, common_name, category, danger_level, viewed_at "
        "FROM field_guide_history WHERE first_aid_id = ? "
        "ORDER BY viewed_at DESC",
        {firstAidId},
        "FieldGuideHistory::getByFirstAid",
        &FieldGuideHistory::rowToShortRecord);
}

QVariantList FieldGuideHistory::getFavorites() {
    if (!m_db || !m_db->isOpen(Database::Name::Settings)) return {};
    QSqlDatabase db = m_db->get(Database::Name::Settings);
    QSqlQuery q(db);
    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectList (无 bind) + 共享 rowToShortRecord
    return DbHelper::selectList(q,
        "SELECT id, entity_id, kingdom, common_name, category, danger_level, viewed_at "
        "FROM field_guide_history WHERE is_favorite = 1 "
        "ORDER BY viewed_at DESC",
        {},
        "FieldGuideHistory::getFavorites",
        &FieldGuideHistory::rowToShortRecord);
}

// 2026-09-21 阶段 L4.x: 7 列短 record 共享 row 映射
QVariantMap FieldGuideHistory::rowToShortRecord(const QSqlQuery& q) {
    QVariantMap m;
    m["id"] = q.value(0).toLongLong();
    m["entityId"] = q.value(1).toString();
    m["kingdom"] = q.value(2).toString();
    m["commonName"] = q.value(3).toString();
    m["category"] = q.value(4).toString();
    m["dangerLevel"] = q.value(5).toInt();
    m["viewedAt"] = q.value(6).toString();
    return m;
}

QVariantMap FieldGuideHistory::getById(qint64 id) {
    if (!m_db || !m_db->isOpen(Database::Name::Settings)) return {};
    QSqlDatabase db = m_db->get(Database::Name::Settings);
    QSqlQuery q(db);
    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectOne
    return DbHelper::selectOne(q,
        "SELECT * FROM field_guide_history WHERE id = ?",
        {id},
        "FieldGuideHistory::getById",
        [](const QSqlQuery& q) {
            QVariantMap m;
            m["id"] = q.value("id").toLongLong();
            m["entityId"] = q.value("entity_id").toString();
            m["kingdom"] = q.value("kingdom").toString();
            m["commonName"] = q.value("common_name").toString();
            m["scientificName"] = q.value("scientific_name").toString();
            m["category"] = q.value("category").toString();
            m["dangerLevel"] = q.value("danger_level").toInt();
            m["viewSource"] = q.value("view_source").toString();
            m["routeId"] = q.value("route_id").toString();
            m["firstAidId"] = q.value("first_aid_id").toString();
            m["note"] = q.value("note").toString();
            m["isFavorite"] = q.value("is_favorite").toBool();
            m["viewedAt"] = q.value("viewed_at").toString();
            return m;
        });
}

QVariantMap FieldGuideHistory::statsByKingdom() {
    QVariantMap m;
    m["plant"] = m_plantCount;
    m["animal"] = m_animalCount;
    m["insect"] = m_insectCount;
    m["mushroom"] = m_mushroomCount;
    m["total"] = m_totalCount;
    return m;
}

// 2026-09-21 阶段 L4.x: 6 个简单写方法切到 execDmlReturning (addRecord 因需 lastInsertId 保留模板)
QVariantMap FieldGuideHistory::setFavorite(qint64 id, bool favorite) {
    using namespace outdoor::internal;
    const QString ctx = "FieldGuideHistory::setFavorite";
    auto err = execDmlReturning(m_db, Database::Name::Settings, ctx,
        [id, favorite, &ctx](QSqlQuery& q) {
            return DbHelper::execDmlPositional(q,
                "UPDATE field_guide_history SET is_favorite = ? WHERE id = ?",
                {favorite ? 1 : 0, id}, ctx);
        });
    if (!isOk(err)) return err;
    emit dataChanged();
    return toQVariant(Ok(true));
}

QVariantMap FieldGuideHistory::addNote(qint64 id, const QString& note) {
    using namespace outdoor::internal;
    const QString ctx = "FieldGuideHistory::addNote";
    auto err = execDmlReturning(m_db, Database::Name::Settings, ctx,
        [id, &note, &ctx](QSqlQuery& q) {
            return DbHelper::execDmlPositional(q,
                "UPDATE field_guide_history SET note = ? WHERE id = ?",
                {note, id}, ctx);
        });
    if (!isOk(err)) return err;
    emit dataChanged();
    return toQVariant(Ok(true));
}

// 详情页的收藏开关: 已有浏览记录就翻 is_favorite, 一条都没有就先落一条再收藏.
// 只看 viewed_at 最新那行, 和 getFavorites() 的读法对齐, 免得同一物种被收成两行.
QVariantMap FieldGuideHistory::toggleFavoriteByEntity(const QString& entityId,
                                                      const QString& kingdom,
                                                      const QString& commonName,
                                                      const QString& scientificName,
                                                      const QString& category,
                                                      int dangerLevel) {
    using namespace outdoor::internal;
    const QString ctx = "FieldGuideHistory::toggleFavoriteByEntity";
    if (entityId.isEmpty())
        return fail(ServiceErrorCode::InvalidArgument, QStringLiteral("entityId 为空"), ctx);
    if (auto e = dbOpenCheck(m_db, Database::Name::Settings, ctx)) return *e;

    QSqlDatabase db = m_db->get(Database::Name::Settings);
    QSqlQuery q(db);
    const QVariantMap found = DbHelper::selectOne(q,
        "SELECT id, is_favorite FROM field_guide_history WHERE entity_id = ? "
        "ORDER BY viewed_at DESC LIMIT 1",
        {entityId}, ctx,
        [](const QSqlQuery& r) {
            QVariantMap m;
            m["id"] = r.value(0).toLongLong();
            m["favorite"] = r.value(1).toBool();
            return m;
        });

    QVariantMap out;
    if (!found.isEmpty()) {
        const bool next = !found.value("favorite").toBool();
        QVariantMap res = setFavorite(found.value("id").toLongLong(), next);
        if (!isOk(res)) return res;
        out["favorite"] = next;
        out["recordId"] = found.value("id");
        return toQVariant(Ok(out));
    }

    ViewRecord rec;
    rec.entityId = entityId;
    rec.kingdom = kingdom;
    rec.commonName = commonName;
    rec.scientificName = scientificName;
    rec.category = category;
    rec.dangerLevel = dangerLevel;
    rec.viewSource = QStringLiteral("manual");
    rec.isFavorite = true;
    rec.viewedAt = QDateTime::currentDateTime();
    QVariantMap res = addRecord(rec);
    if (!isOk(res)) return res;
    out["favorite"] = true;
    out["recordId"] = res.value("value");
    return toQVariant(Ok(out));
}

bool FieldGuideHistory::isFavoriteEntity(const QString& entityId) {
    if (!m_db || !m_db->isOpen(Database::Name::Settings) || entityId.isEmpty()) return false;
    QSqlDatabase db = m_db->get(Database::Name::Settings);
    QSqlQuery q(db);
    const QVariantMap found = DbHelper::selectOne(q,
        "SELECT is_favorite FROM field_guide_history WHERE entity_id = ? "
        "ORDER BY viewed_at DESC LIMIT 1",
        {entityId}, QStringLiteral("FieldGuideHistory::isFavoriteEntity"),
        [](const QSqlQuery& r) {
            QVariantMap m;
            m["favorite"] = r.value(0).toBool();
            return m;
        });
    return found.value("favorite").toBool();
}

QVariantMap FieldGuideHistory::cleanOldRecords(int daysOld) {
    using namespace outdoor::internal;
    const QString ctx = "FieldGuideHistory::cleanOldRecords";
    auto err = execDmlReturning(m_db, Database::Name::Settings, ctx,
        [daysOld, &ctx](QSqlQuery& q) {
            return DbHelper::execDmlPositional(q,
                "DELETE FROM field_guide_history "
                "WHERE viewed_at < datetime('now', ? || ' days') "
                "AND is_favorite = 0",
                {-daysOld}, ctx);
        });
    if (!isOk(err)) return err;
    refreshCounts();
    emit dataChanged();
    return toQVariant(Ok(true));
}

} // namespace outdoor
