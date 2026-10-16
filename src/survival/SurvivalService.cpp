/**
 * @file SurvivalService.cpp
 */

#include "SurvivalService.h"
#include "../core/AssetLoader.h"
#include "../core/Database.h"
#include "../core/Logger.h"
#include "../common/DbHelper.h"  // 2026-09-21: Phase 2 DbHelper 统一 DDL 错误日志

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSqlQuery>

namespace outdoor {

SurvivalService::SurvivalService(Database* db, QObject* parent)
    
    : ServiceBase(db, "SurvivalService", parent) {
}

SurvivalService::~SurvivalService() = default;

bool SurvivalService::loadInitialData() {
    if (!ensureSchema()) return false;
    return loadFromJson();
}

bool SurvivalService::ensureSchema() {
    if (!m_db || !m_db->isOpen(Database::Name::Survival)) return false;
    QSqlDatabase db = m_db->get(Database::Name::Survival);
    QSqlQuery q(db);

    // 2026-09-21: Phase 2 - 改用 DbHelper::execDdl, 失败自动 log
    int failed = 0;
    const char* tag = "SurvivalService::ensureSchema";

    if (!DbHelper::execDdl(q, R"(
        CREATE TABLE IF NOT EXISTS survival_items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            topic INTEGER,
            category TEXT,
            difficulty INTEGER,
            description TEXT,
            materials TEXT,
            estimated_time_min INTEGER,
            steps TEXT,
            warnings TEXT,
            tips TEXT,
            video_url TEXT,
            source TEXT
        )
    )", tag)) ++failed;

    if (!DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_si_topic ON survival_items(topic)", tag)) ++failed;

    return failed == 0;
}

bool SurvivalService::loadFromJson() {
    QString err;
    auto doc = AssetLoader::loadJson("survival_items.json", &err);
    if (!doc) {
        Logger::warn(QString("SurvivalService: %1").arg(err));
        return false;
    }
    if (!doc->isObject()) {
        Logger::warn("SurvivalService: survival_items.json root is not an object");
        return false;
    }

    QJsonArray arr = doc->object()["items"].toArray();
    int count = 0;
    for (const auto& v : arr) {
        QJsonObject o = v.toObject();
        Item item;
        item.id = o["id"].toString();
        item.name = o["name"].toString();
        item.topic = static_cast<Topic>(o["topic"].toInt());
        item.category = o["category"].toString();
        item.difficulty = o["difficulty"].toInt();
        item.description = o["description"].toString();
        item.estimatedTimeMin = o["estimated_time_min"].toInt();
        item.videoUrl = o["video_url"].toString();
        item.source = o["source"].toString();

        for (const auto& s : o["materials"].toArray()) item.materials << s.toString();
        for (const auto& s : o["steps"].toArray()) item.steps << s.toString();
        for (const auto& s : o["warnings"].toArray()) item.warnings << s.toString();
        for (const auto& s : o["tips"].toArray()) item.tips << s.toString();

        m_items[item.id] = item;
        count++;
    }

    Logger::info(QString("SurvivalService loaded: %1 items").arg(count));
    emit dataChanged();
    return count > 0;
}

int SurvivalService::fireMethodsCount() const {
    int n = 0;
    for (const auto& i : m_items) if (i.topic == Topic::Fire) n++;
    return n;
}

int SurvivalService::shelterCount() const {
    int n = 0;
    for (const auto& i : m_items) if (i.topic == Topic::Shelter) n++;
    return n;
}

int SurvivalService::toolCount() const {
    int n = 0;
    for (const auto& i : m_items) if (i.topic == Topic::Tools) n++;
    return n;
}

QVariantList SurvivalService::getByTopic(Topic topic) {
    QVariantList list;
    for (const auto& i : m_items) {
        if (i.topic == topic) {
            QVariantMap m;
            m["id"] = i.id;
            m["name"] = i.name;
            m["difficulty"] = i.difficulty;
            m["category"] = i.category;
            m["estimatedTimeMin"] = i.estimatedTimeMin;
            list.append(m);
        }
    }
    return list;
}

QVariantList SurvivalService::getByDifficulty(int maxDifficulty) {
    QVariantList list;
    for (const auto& i : m_items) {
        if (i.difficulty <= maxDifficulty) {
            QVariantMap m;
            m["id"] = i.id;
            m["name"] = i.name;
            m["topic"] = static_cast<int>(i.topic);
            m["difficulty"] = i.difficulty;
            list.append(m);
        }
    }
    return list;
}

QVariantMap SurvivalService::getById(const QString& id) {
    QVariantMap result;
    auto it = m_items.constFind(id);
    if (it == m_items.constEnd()) return result;

    const Item& i = it.value();
    result["id"] = i.id;
    result["name"] = i.name;
    result["topic"] = static_cast<int>(i.topic);
    result["category"] = i.category;
    result["difficulty"] = i.difficulty;
    result["description"] = i.description;
    result["materials"] = i.materials;
    result["estimatedTimeMin"] = i.estimatedTimeMin;
    result["steps"] = i.steps;
    result["warnings"] = i.warnings;
    result["tips"] = i.tips;
    result["videoUrl"] = i.videoUrl;
    result["source"] = i.source;
    return result;
}

QVariantList SurvivalService::search(const QString& keyword) {
    QVariantList list;
    if (keyword.isEmpty()) return list;
    for (const auto& i : m_items) {
        if (i.name.contains(keyword, Qt::CaseInsensitive) ||
            i.description.contains(keyword, Qt::CaseInsensitive)) {
            QVariantMap m;
            m["id"] = i.id;
            m["name"] = i.name;
            m["topic"] = static_cast<int>(i.topic);
            m["difficulty"] = i.difficulty;
            list.append(m);
        }
    }
    return list;
}

QStringList SurvivalService::getCategories(Topic topic) {
    QStringList list;
    for (const auto& i : m_items) {
        if (i.topic == topic && !list.contains(i.category)) {
            list << i.category;
        }
    }
    return list;
}

} // namespace outdoor
