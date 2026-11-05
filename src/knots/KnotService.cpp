/**
 * @file KnotService.cpp
 */

#include "KnotService.h"
#include "../common/DbHelper.h"  // 2026-09-21 阶段 L2.2
#include "../core/AssetLoader.h"
#include "../core/Database.h"
#include "../core/Logger.h"
#include "../core/Result.h"                 // 2026-09-21: Phase 5 批次 3
#include "../core/ServiceErrors.h"          // 2026-09-21: Phase 5 批次 3
#include "../core/internal/QmlResultBridge.h" // 2026-09-21: Phase 5 批次 3
#include "../common/SettingsStore.h"  // 2026-09-21: 阶段 L5.1
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSqlQuery>
#include <QSqlError>
#include <QDateTime>
#include <algorithm>

namespace outdoor {

KnotService::KnotService(Database* db, QObject* parent)
    : ServiceBase(db, "KnotService", parent) {  // 2026-09-21 阶段 L2
}

KnotService::~KnotService() = default;

bool KnotService::loadInitialData() {
    if (!ensureSchema()) return false;

    // 从 JSON 加载数据
    if (!loadFromJson()) return false;

    // 加载学习进度 (2026-09-10: 从 QSettings 迁到 SQLite knot_progress 表)
    // V1 迁移: 如果 SQLite 是空但 QSettings 有 learnedKnots, 自动导入并清理 QSettings
    QSqlDatabase db = m_db->get(Database::Name::Survival);
    QSqlQuery q(db);
    // 2026-09-21 阶段 L2.2: 切 DbHelper::execSelect
    if (!DbHelper::execSelect(q, "SELECT knot_id FROM knot_progress", {},
                              "KnotService::loadInitialData")) {
        return false;
    }
    while (q.next()) {
        m_learned.insert(q.value(0).toString());
    }

    // V1→V2 一次性迁移
    int count = SettingsStore::beginReadArray("learnedKnots");
    if (count > 0 && m_learned.isEmpty()) {
        Logger::info(QString("KnotService: migrating %1 learned knots from QSettings to SQLite").arg(count));
        db.transaction();
        QSqlQuery ins(db);
        ins.prepare("INSERT OR IGNORE INTO knot_progress(knot_id) VALUES (?)");
        for (int i = 0; i < count; ++i) {
            SettingsStore::setArrayIndex(i);
            const QString id = SettingsStore::getString("id");
            if (!id.isEmpty()) {
                ins.addBindValue(id);
                ins.exec();
            }
        }
        db.commit();
        SettingsStore::endArray();
        SettingsStore::remove("learnedKnots");
        SettingsStore::sync();
        Logger::info("KnotService: QSettings migration done, knot_progress populated");
        // 重新读
        m_learned.clear();
        QSqlQuery q2(db);
        q2.exec("SELECT knot_id FROM knot_progress");
        while (q2.next()) m_learned.insert(q2.value(0).toString());
    } else {
        SettingsStore::endArray();
    }

    return true;
}

bool KnotService::ensureSchema() {
    if (!m_db || !m_db->isOpen(Database::Name::Survival)) return false;
    QSqlDatabase db = m_db->get(Database::Name::Survival);
    QSqlQuery q(db);
    // 2026-09-21 阶段 L2.2: 切 DbHelper::execDdl (内含错误日志 + db closed 检查)
    DbHelper::execDdl(q, R"(
        CREATE TABLE IF NOT EXISTS knots (
            id TEXT PRIMARY KEY,
            name_cn TEXT NOT NULL,
            name_en TEXT,
            category TEXT,
            difficulty INTEGER,
            use_cases TEXT,
            description TEXT,
            steps TEXT,
            common_mistakes TEXT,
            related TEXT,
            video_url TEXT,
            animation_url TEXT,
            practice_tip TEXT
        )
    )", "KnotService::ensureSchema.knots");
    DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_knot_cat ON knots(category)",
                      "KnotService::ensureSchema.idx");
    // 2026-09-17: 建 knot_progress 表 (学习进度), 之前没建导致 knot_progress 查询
    // 报 no such table, KnotService 整个 loadInitialData 失败 (ServiceRegistry log 1 failures)
    DbHelper::execDdl(q, R"(
        CREATE TABLE IF NOT EXISTS knot_progress (
            knot_id TEXT PRIMARY KEY,
            learned INTEGER DEFAULT 0,
            learned_at TEXT
        )
    )", "KnotService::ensureSchema.knot_progress");
    return true;
}

bool KnotService::loadFromJson() {
    QString err;
    auto doc = AssetLoader::loadJson("knots.json", &err);
    if (!doc) {
        Logger::warn(QString("KnotService: %1").arg(err));
        return false;
    }
    if (!doc->isObject()) {
        Logger::warn("KnotService: knots.json root is not an object");
        return false;
    }

    QJsonArray arr = doc->object()["knots"].toArray();
    int count = 0;
    for (const auto& v : arr) {
        QJsonObject o = v.toObject();
        Knot k;
        k.id = o["id"].toString();
        k.nameCn = o["name_cn"].toString();
        k.nameEn = o["name_en"].toString();
        k.category = o["category"].toString();
        k.difficulty = o["difficulty"].toInt();
        k.description = o["description"].toString();
        k.videoUrl = o["video_url"].toString();
        k.animationUrl = o["animation_url"].toString();
        k.practiceTip = o["practice_tip"].toString();

        for (const auto& s : o["use_cases"].toArray()) k.useCases << s.toString();
        for (const auto& s : o["steps"].toArray()) k.steps << s.toString();
        for (const auto& s : o["common_mistakes"].toArray()) k.commonMistakes << s.toString();
        for (const auto& s : o["related"].toArray()) k.related << s.toString();

        m_knots[k.id] = k;
        count++;
    }

    Logger::info(QString("KnotService loaded: %1 knots").arg(count));
    emit dataChanged();
    return count > 0;
}

int KnotService::totalCount() const {
    return m_knots.size();
}

int KnotService::learnedCount() const {
    return m_learned.size();
}

QVariantList KnotService::getAll() {
    QVariantList list;
    for (const auto& k : m_knots) {
        QVariantMap m;
        m["id"] = k.id;
        m["nameCn"] = k.nameCn;
        m["nameEn"] = k.nameEn;
        m["category"] = k.category;
        m["difficulty"] = k.difficulty;
        m["learned"] = m_learned.contains(k.id);
        list.append(m);
    }
    return list;
}

QVariantList KnotService::getByCategory(const QString& category) {
    QVariantList list;
    for (const auto& k : m_knots) {
        if (k.category == category) {
            QVariantMap m;
            m["id"] = k.id;
            m["nameCn"] = k.nameCn;
            m["difficulty"] = k.difficulty;
            m["learned"] = m_learned.contains(k.id);
            list.append(m);
        }
    }
    return list;
}

QVariantList KnotService::getByDifficulty(int difficulty) {
    QVariantList list;
    for (const auto& k : m_knots) {
        if (k.difficulty == difficulty) {
            QVariantMap m;
            m["id"] = k.id;
            m["nameCn"] = k.nameCn;
            m["category"] = k.category;
            list.append(m);
        }
    }
    return list;
}

QVariantMap KnotService::getById(const QString& id) {
    QVariantMap result;
    auto it = m_knots.constFind(id);
    if (it == m_knots.constEnd()) return result;

    const Knot& k = it.value();
    result["id"] = k.id;
    result["nameCn"] = k.nameCn;
    result["nameEn"] = k.nameEn;
    result["category"] = k.category;
    result["difficulty"] = k.difficulty;
    result["useCases"] = k.useCases;
    result["description"] = k.description;
    result["steps"] = k.steps;
    result["commonMistakes"] = k.commonMistakes;
    result["related"] = k.related;
    result["videoUrl"] = k.videoUrl;
    result["animationUrl"] = k.animationUrl;
    result["practiceTip"] = k.practiceTip;
    result["learned"] = m_learned.contains(k.id);
    return result;
}

QVariantList KnotService::search(const QString& keyword) {
    QVariantList list;
    if (keyword.isEmpty()) return list;
    for (const auto& k : m_knots) {
        if (k.nameCn.contains(keyword, Qt::CaseInsensitive) ||
            k.nameEn.contains(keyword, Qt::CaseInsensitive)) {
            QVariantMap m;
            m["id"] = k.id;
            m["nameCn"] = k.nameCn;
            m["difficulty"] = k.difficulty;
            list.append(m);
        }
    }
    return list;
}

// 2026-09-21: Phase 5 批次 3 - getLearningPath 返回 Result
QVariantMap KnotService::getLearningPath() {
    using namespace outdoor::internal;

    // 按难度递进排序
    QVariantList list;
    QStringList byOrder = {
        // 入门
        "single", "figure_eight", "square", "truckers",
        // 进阶
        "double_fisherman", "figure_eight_bend", "round_lumber", "bowline",
        // 高级
        "double_bowline", "prussik", "外科结"
    };

    for (const QString& id : byOrder) {
        if (m_knots.contains(id)) {
            QVariantMap m;
            m["id"] = id;
            m["nameCn"] = m_knots[id].nameCn;
            m["difficulty"] = m_knots[id].difficulty;
            m["learned"] = m_learned.contains(id);
            list.append(m);
        }
    }
    // byOrder 只表达"同难度内的教学顺序", 真正的递进靠 difficulty 稳定排序保证。
    // 2026-10-16: 原实现直接返回 byOrder, truckers(难度1) 排在 square(难度2) 之后,
    //   与函数注释"按难度递进排序"不符, 也违反 KnotLearningPage 的预期顺序。
    std::stable_sort(list.begin(), list.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap()["difficulty"].toInt() < b.toMap()["difficulty"].toInt();
    });
    return toQVariant(Ok(list));
}

// 2026-09-21: 阶段 L3.2 - markLearned 返回 Result<bool>
QVariantMap KnotService::markLearned(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "KnotService::markLearned";

    if (!m_knots.contains(id)) {
        Logger::warn(QString("%1: 目录里没有这个绳结: %2").arg(ctx, id));
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("这个绳结在目录里没有"), ctx));
    }
    if (auto e = dbOpenCheck(m_db, Database::Name::Survival, ctx)) return *e;

    m_learned.insert(id);

    // 2026-09-10: 写 SQLite knot_progress, 不再用 QSettings
    // 2026-09-21 阶段 L2.2: DbHelper::execDmlPositional 需 QSqlQuery lvalue, 提取本地变量
    QSqlDatabase db = m_db->get(Database::Name::Survival);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        "INSERT OR IGNORE INTO knot_progress(knot_id, learned, learned_at) VALUES (?, 1, ?)",
        {id, QDateTime::currentDateTime().toString(Qt::ISODate)},
        ctx);
    if (rc != DmlResult::Ok && rc != DmlResult::AlreadyExists) {
        // 失败已由 DbHelper log, 此处返回 Err
        return toQVariant(Err<bool>(ServiceErrorCode::DbError,
                                      QStringLiteral("这个绳结的进度没记到本机"), ctx));
    }

    emit progressChanged();
    return toQVariant(Ok(true));
}

bool KnotService::isLearned(const QString& id) {
    return m_learned.contains(id);
}

// 2026-09-21: 阶段 L3.2 - resetProgress 返回 Result<bool>
QVariantMap KnotService::resetProgress() {
    using namespace outdoor::internal;
    const char* ctx = "KnotService::resetProgress";

    m_learned.clear();
    // 2026-09-10: 清 SQLite knot_progress
    if (m_db && m_db->isOpen(Database::Name::Survival)) {
        QSqlDatabase db = m_db->get(Database::Name::Survival);
        // 2026-09-21 阶段 L2.2: 切 DbHelper::execDml (无 binds), 需 QSqlQuery lvalue
        QSqlQuery q(db);
        auto rc = DbHelper::execDml(q,
            "DELETE FROM knot_progress", {}, ctx);
        if (rc != DmlResult::Ok) {
            return dbErr(rc, db, ctx);
        }
    }
    emit progressChanged();
    return toQVariant(Ok(true));
}

QVariantList KnotService::getLearnedList() {
    QVariantList list;
    for (const QString& id : m_learned) {
        if (m_knots.contains(id)) {
            QVariantMap m;
            m["id"] = id;
            m["nameCn"] = m_knots[id].nameCn;
            m["difficulty"] = m_knots[id].difficulty;
            list.append(m);
        }
    }
    return list;
}

QStringList KnotService::getCategories() const {
    QStringList list;
    for (const auto& k : m_knots) {
        if (!list.contains(k.category)) list << k.category;
    }
    return list;
}

} // namespace outdoor
