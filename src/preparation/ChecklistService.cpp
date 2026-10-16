/**
 * @file ChecklistService.cpp
 */

#include "ChecklistService.h"
#include "../core/AssetLoader.h"
#include "../core/Database.h"
#include "../core/Logger.h"
#include "../core/Result.h"
#include "../core/ServiceErrors.h"
#include "../core/internal/QmlResultBridge.h"  // 2026-09-21: Phase 5 写操作切 Result
#include "../common/DbHelper.h"  // 2026-09-21: Phase 2 DbHelper 统一 DDL 错误日志

#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QSqlQuery>
#include <QSqlError>
// 2026-09-21 阶段 L5.1: QSettings 不再使用 (ChecklistService 全走 SQLite)
#include <QUuid>
#include <algorithm>

namespace outdoor {

ChecklistService::ChecklistService(Database* db, QObject* parent)
    
    : ServiceBase(db, "ChecklistService", parent) {
}

ChecklistService::~ChecklistService() {
}

bool ChecklistService::loadInitialData() {
    if (!ensureSchema()) return false;
    return loadTemplates();
}

bool ChecklistService::ensureSchema() {
    if (!m_db || !m_db->isOpen(Database::Name::User)) return false;

    QSqlDatabase db = m_db->get(Database::Name::User);
    QSqlQuery q(db);

    // 2026-09-21: Phase 2 - 改用 DbHelper::execDdl, 失败自动 log
    int failed = 0;
    const char* tag = "ChecklistService::ensureSchema";

    if (!DbHelper::execDdl(q, R"(
        CREATE TABLE IF NOT EXISTS checklists (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            scenario TEXT,
            description TEXT,
            is_template INTEGER DEFAULT 0,
            total_weight_g REAL,
            total_count INTEGER,
            checked_count INTEGER,
            created_at TEXT,
            updated_at TEXT,
            is_deleted INTEGER DEFAULT 0
        )
    )", tag)) ++failed;

    if (!DbHelper::execDdl(q, R"(
        CREATE TABLE IF NOT EXISTS checklist_items (
            id TEXT PRIMARY KEY,
            checklist_id TEXT NOT NULL,
            name TEXT,
            category TEXT,
            quantity INTEGER,
            weight_g REAL,
            required INTEGER DEFAULT 0,
            checked INTEGER DEFAULT 0,
            note TEXT,
            alternatives TEXT,
            sequence INTEGER,
            FOREIGN KEY (checklist_id) REFERENCES checklists(id) ON DELETE CASCADE
        )
    )", tag)) ++failed;

    if (!DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_cl_items ON checklist_items(checklist_id)", tag)) ++failed;

    return failed == 0;
}

bool ChecklistService::loadTemplates() {
    using namespace outdoor::internal;
    QString err;
    auto doc = AssetLoader::loadJson("checklists.json", &err);
    if (!doc) {
        Logger::warn(QString("ChecklistService: %1").arg(err));
        return false;
    }
    if (!doc->isObject()) {
        Logger::warn("ChecklistService: checklists.json root is not an object");
        return false;
    }

    QJsonArray arr = doc->object()["checklists"].toArray();
    int count = 0;
    for (const auto& v : arr) {
        QJsonObject o = v.toObject();
        Checklist list;
        list.id = o["scenario"].toString();
        list.name = o["name"].toString();
        list.scenario = o["scenario"].toString();
        list.description = o["description"].toString();
        list.isTemplate = true;

        for (const auto& iv : o["items"].toArray()) {
            QJsonObject io = iv.toObject();
            Item item;
            item.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
            item.name = io["name"].toString();
            item.category = io["category"].toString();
            item.quantity = io["quantity"].toInt();
            item.weightG = io["weight_g"].toDouble();
            item.required = io["required"].toBool();
            item.checked = false;
            item.note = io["note"].toString();
            for (const auto& alt : io["alternatives"].toArray()) {
                item.alternatives << alt.toString();
            }
            list.items.append(item);
        }

        recomputeStats(list);
        m_checklists[list.id] = list;

        // 存到数据库（仅模板）
        if (isOk(saveChecklist(list))) count++;
    }

    m_templateCount = count;
    Logger::info(QString("ChecklistService loaded %1 templates").arg(count));
    emit dataChanged();
    return count > 0;
}

void ChecklistService::recomputeStats(Checklist& list) {
    list.totalCount = list.items.size();
    list.totalWeightG = 0;
    list.checkedCount = 0;
    for (const auto& item : list.items) {
        list.totalWeightG += item.weightG * item.quantity;
        if (item.checked) list.checkedCount++;
    }
    list.updatedAt = QDateTime::currentDateTime();
}

void ChecklistService::saveChecklistItems(const QString& checklistId,
                                             const QList<Item>& items) {
    if (!m_db || !m_db->isOpen(Database::Name::User)) return;

    QSqlDatabase db = m_db->get(Database::Name::User);
    QSqlQuery q(db);

    // 2026-09-21 阶段 L2.2: 切 DbHelper::execDmlPositional
    // 先删除
    DbHelper::execDmlPositional(q,
        "DELETE FROM checklist_items WHERE checklist_id = ?",
        {checklistId},
        "ChecklistService::saveChecklistItems.clear");

    // 重新插入
    db.transaction();
    for (int i = 0; i < items.size(); ++i) {
        const Item& item = items[i];
        DbHelper::execDmlPositional(q, R"(
            INSERT INTO checklist_items (
                id, checklist_id, name, category, quantity, weight_g,
                required, checked, note, alternatives, sequence
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        )",
            {item.id.isEmpty() ?
                  QUuid::createUuid().toString(QUuid::WithoutBraces) :
                  item.id,
             checklistId,
             item.name,
             item.category,
             item.quantity,
             item.weightG,
             item.required ? 1 : 0,
             item.checked ? 1 : 0,
             item.note,
             QJsonDocument(QJsonArray::fromStringList(item.alternatives))
                 .toJson(QJsonDocument::Compact),
             i},
            "ChecklistService::saveChecklistItems.insert");
    }
    db.commit();
}

QList<ChecklistService::Item> ChecklistService::loadChecklistItems(
    const QString& checklistId) {
    QList<Item> items;
    if (!m_db || !m_db->isOpen(Database::Name::User)) return items;

    QSqlDatabase db = m_db->get(Database::Name::User);
    // 2026-09-21 阶段 L2.2: 切 DbHelper::execSelectPositional
    QSqlQuery q(db);
    if (DbHelper::execSelectPositional(q,
            "SELECT id, name, category, quantity, weight_g, required, checked, "
            "note, alternatives FROM checklist_items WHERE checklist_id = ? "
            "ORDER BY sequence",
            {checklistId},
            "ChecklistService::loadChecklistItems")) {
        while (q.next()) {
            Item item;
            item.id = q.value(0).toString();
            item.name = q.value(1).toString();
            item.category = q.value(2).toString();
            item.quantity = q.value(3).toInt();
            item.weightG = q.value(4).toDouble();
            item.required = q.value(5).toBool();
            item.checked = q.value(6).toBool();
            item.note = q.value(7).toString();

            QJsonDocument doc = QJsonDocument::fromJson(
                q.value(8).toString().toUtf8());
            for (const auto& v : doc.array()) {
                item.alternatives << v.toString();
            }
            items.append(item);
        }
    }
    return items;
}

int ChecklistService::totalChecklists() const {
    return m_checklists.size();
}

int ChecklistService::totalTemplates() const {
    return m_templateCount;
}

QVariantList ChecklistService::getTemplates() {
    QVariantList list;
    for (const auto& c : m_checklists) {
        if (c.isTemplate) {
            QVariantMap m;
            m["id"] = c.id;
            m["name"] = c.name;
            m["scenario"] = c.scenario;
            m["description"] = c.description;
            m["totalCount"] = c.totalCount;
            m["totalWeightG"] = c.totalWeightG;
            list.append(m);
        }
    }
    return list;
}

QVariantMap ChecklistService::getTemplate(const QString& scenario) {
    QVariantMap result;
    auto it = m_checklists.constFind(scenario);
    if (it == m_checklists.constEnd()) return result;

    const Checklist& c = it.value();
    result["id"] = c.id;
    result["name"] = c.name;
    result["scenario"] = c.scenario;
    result["description"] = c.description;
    result["totalCount"] = c.totalCount;
    result["totalWeightG"] = c.totalWeightG;

    QVariantList items;
    for (const auto& item : c.items) {
        QVariantMap m;
        m["id"] = item.id;
        m["name"] = item.name;
        m["category"] = item.category;
        m["quantity"] = item.quantity;
        m["weightG"] = item.weightG;
        m["required"] = item.required;
        m["note"] = item.note;
        items.append(m);
    }
    result["items"] = items;
    return result;
}

// 2026-09-21: Phase 5 - createCustom 返回 Result {ok, value=id, error}
QVariantMap ChecklistService::createCustom(const QString& name) {
    using namespace outdoor::internal;
    const char* ctx = "ChecklistService::createCustom";

    if (auto e = requireNonBlank(name, "清单名称", ctx)) return *e;

    QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    Checklist list;
    list.id = id;
    list.name = name;
    list.isTemplate = false;
    list.updatedAt = QDateTime::currentDateTime();

    const QVariantMap subRes = saveChecklist(list);
    if (auto e = propagateError<QString>(subRes, ctx)) return *e;
    m_checklists[id] = list;
    return toQVariant(Ok(id));
}

QVariantList ChecklistService::getCustomLists() {
    QVariantList list;
    for (const auto& c : m_checklists) {
        if (!c.isTemplate) {
            QVariantMap m;
            m["id"] = c.id;
            m["name"] = c.name;
            m["totalCount"] = c.totalCount;
            m["totalWeightG"] = c.totalWeightG;
            m["updatedAt"] = c.updatedAt;
            list.append(m);
        }
    }
    return list;
}

QVariantMap ChecklistService::getById(const QString& id) {  // 2026-09-20: rename
    QVariantMap result;
    auto it = m_checklists.constFind(id);
    if (it == m_checklists.constEnd()) {
        // 从数据库加载
        if (!m_db || !m_db->isOpen(Database::Name::User)) return result;
        // 2026-09-21 阶段 L2.2: 切 DbHelper::execSelectPositional
        QSqlQuery q(m_db->get(Database::Name::User));
        if (!DbHelper::execSelectPositional(q,
                "SELECT name, scenario, description, is_template FROM checklists "
                "WHERE id = ? AND is_deleted = 0",
                {id},
                "ChecklistService::getById")) return result;
        if (!q.next()) return result;

        Checklist list;
        list.id = id;
        list.name = q.value(0).toString();
        list.scenario = q.value(1).toString();
        list.description = q.value(2).toString();
        list.isTemplate = q.value(3).toBool();
        list.items = loadChecklistItems(id);
        recomputeStats(list);
        m_checklists[id] = list;
        it = m_checklists.constFind(id);
    }

    const Checklist& c = it.value();
    result["id"] = c.id;
    result["name"] = c.name;
    result["scenario"] = c.scenario;
    result["description"] = c.description;
    result["isTemplate"] = c.isTemplate;
    result["totalCount"] = c.totalCount;
    result["totalWeightG"] = c.totalWeightG;
    result["checkedCount"] = c.checkedCount;
    result["updatedAt"] = c.updatedAt;

    QVariantList items;
    for (const auto& item : c.items) {
        QVariantMap m;
        m["id"] = item.id;
        m["name"] = item.name;
        m["category"] = item.category;
        m["quantity"] = item.quantity;
        m["weightG"] = item.weightG;
        m["required"] = item.required;
        m["checked"] = item.checked;
        m["note"] = item.note;
        m["alternatives"] = item.alternatives;
        items.append(m);
    }
    result["items"] = items;
    return result;
}

// 2026-09-21: 阶段 L3.3 - saveChecklist 返回 Result<bool>
QVariantMap ChecklistService::saveChecklist(const Checklist& list) {
    using namespace outdoor::internal;
    const char* ctx = "ChecklistService::saveChecklist";

    if (auto e = dbOpenCheck(m_db, Database::Name::User, ctx)) return *e;
    if (auto e = requireNonEmpty(list.id, "checklist.id", ctx)) return *e;

    // 2026-09-21 阶段 L2.2: DbHelper::execDmlPositional 需 QSqlQuery lvalue, 提取本地变量
    QSqlDatabase db = m_db->get(Database::Name::User);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        R"(
        INSERT OR REPLACE INTO checklists (
            id, name, scenario, description, is_template,
            total_weight_g, total_count, checked_count, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    )",
        {list.id,
         list.name,
         list.scenario,
         list.description,
         list.isTemplate ? 1 : 0,
         list.totalWeightG,
         list.totalCount,
         list.checkedCount,
         QDateTime::currentDateTime().toString(Qt::ISODate)},
        ctx);
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }

    saveChecklistItems(list.id, list.items);
    m_checklists[list.id] = list;
    emit checklistChanged(list.id);
    emit dataChanged();
    return toQVariant(Ok(true));
}

// 2026-09-21: 阶段 L3.3 - deleteChecklist 返回 Result<bool>
QVariantMap ChecklistService::deleteChecklist(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "ChecklistService::deleteChecklist";

    if (auto e = dbOpenCheck(m_db, Database::Name::User, ctx)) return *e;

    // 2026-09-21 阶段 L2.2: DbHelper::execDmlPositional 需 QSqlQuery lvalue, 提取本地变量
    QSqlDatabase db = m_db->get(Database::Name::User);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        "UPDATE checklists SET is_deleted = 1 WHERE id = ?", {id}, ctx);
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }

    m_checklists.remove(id);
    emit dataChanged();
    return toQVariant(Ok(true));
}

// 2026-09-21: Phase 5 - 写操作切 Result
QVariantMap ChecklistService::setItemChecked(const QString& checklistId,
                                               const QString& itemId, bool checked) {
    using namespace outdoor::internal;
    const char* ctx = "ChecklistService::setItemChecked";

    if (auto e = dbOpenCheck(m_db, Database::Name::User, ctx)) return *e;

    // 2026-09-21 阶段 L2.2: DbHelper::execDmlPositional 需 QSqlQuery lvalue, 提取本地变量
    QSqlDatabase db = m_db->get(Database::Name::User);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        "UPDATE checklist_items SET checked = ? "
        "WHERE checklist_id = ? AND id = ?",
        {checked ? 1 : 0, checklistId, itemId},
        "ChecklistService::setItemChecked");
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }

    auto it = m_checklists.find(checklistId);
    if (it != m_checklists.end()) {
        for (auto& item : it.value().items) {
            if (item.id == itemId) item.checked = checked;
        }
        recomputeStats(it.value());
        saveChecklist(it.value());
    }
    emit itemChanged(checklistId, itemId);
    return okVoid();
}

// 2026-09-21: 阶段 L3.3 - setItemQuantity 返回 Result<bool>
QVariantMap ChecklistService::setItemQuantity(const QString& checklistId,
                                                const QString& itemId, int qty) {
    using namespace outdoor::internal;
    const char* ctx = "ChecklistService::setItemQuantity";

    if (auto e = dbOpenCheck(m_db, Database::Name::User, ctx)) return *e;

    // 2026-09-21 阶段 L2.2: DbHelper::execDmlPositional 需 QSqlQuery lvalue, 提取本地变量
    QSqlDatabase db = m_db->get(Database::Name::User);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        "UPDATE checklist_items SET quantity = ? "
        "WHERE checklist_id = ? AND id = ?",
        {qty, checklistId, itemId},
        ctx);
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }

    auto it = m_checklists.find(checklistId);
    if (it != m_checklists.end()) {
        for (auto& item : it.value().items) {
            if (item.id == itemId) item.quantity = qty;
        }
        recomputeStats(it.value());
        saveChecklist(it.value());
    }
    return toQVariant(Ok(true));
}

// 2026-09-21: 阶段 L3.3 - addItem 返回 Result<bool>
QVariantMap ChecklistService::addItem(const QString& checklistId, const Item& item) {
    using namespace outdoor::internal;
    const char* ctx = "ChecklistService::addItem";

    auto it = m_checklists.find(checklistId);
    if (it == m_checklists.end()) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                       QStringLiteral("清单不存在: %1").arg(checklistId), ctx));
    }

    Item newItem = item;
    if (newItem.id.isEmpty()) {
        newItem.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    }
    it.value().items.append(newItem);
    recomputeStats(it.value());
    return saveChecklist(it.value());
}

// 2026-09-21: 阶段 L3.3 - deleteItem 返回 Result<bool>
QVariantMap ChecklistService::deleteItem(const QString& checklistId,
                                          const QString& itemId) {
    using namespace outdoor::internal;
    const char* ctx = "ChecklistService::deleteItem";

    auto it = m_checklists.find(checklistId);
    if (it == m_checklists.end()) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                       QStringLiteral("清单不存在: %1").arg(checklistId), ctx));
    }

    auto& items = it.value().items;
    items.erase(std::remove_if(items.begin(), items.end(),
                                 [&](const Item& i) { return i.id == itemId; }),
                items.end());
    recomputeStats(it.value());
    return saveChecklist(it.value());
}

QString ChecklistService::exportToText(const QString& checklistId) {
    auto it = m_checklists.constFind(checklistId);
    if (it == m_checklists.constEnd()) return QString();

    const Checklist& c = it.value();
    QString out;
    out += QString("=== %1 ===\n").arg(c.name);
    if (!c.description.isEmpty()) {
        out += QString("%1\n\n").arg(c.description);
    }
    out += QString("总重量: %1 g\n").arg(c.totalWeightG, 0, 'f', 1);
    out += QString("项目数: %1\n").arg(c.totalCount);
    out += QString("\n");

    for (const auto& item : c.items) {
        QString mark = item.required ? "[必]" : "[选]";
        QString check = item.checked ? "[√]" : "[ ]";
        out += QString("%1 %2 %3 x %4 (%5 g)\n")
                  .arg(mark, check, item.name)
                  .arg(item.quantity)
                  .arg(item.weightG * item.quantity, 0, 'f', 0);
        if (!item.note.isEmpty()) {
            out += QString("    %1\n").arg(item.note);
        }
    }

    return out;
}

QJsonObject ChecklistService::exportToJson(const QString& checklistId) {
    auto it = m_checklists.constFind(checklistId);
    if (it == m_checklists.constEnd()) return QJsonObject();

    const Checklist& c = it.value();
    QJsonObject obj;
    obj["id"] = c.id;
    obj["name"] = c.name;
    obj["scenario"] = c.scenario;
    obj["description"] = c.description;
    obj["isTemplate"] = c.isTemplate;
    obj["totalWeightG"] = c.totalWeightG;
    obj["totalCount"] = c.totalCount;

    QJsonArray items;
    for (const auto& item : c.items) {
        QJsonObject io;
        io["id"] = item.id;
        io["name"] = item.name;
        io["category"] = item.category;
        io["quantity"] = item.quantity;
        io["weightG"] = item.weightG;
        io["required"] = item.required;
        io["note"] = item.note;
        io["alternatives"] = QJsonArray::fromStringList(item.alternatives);
        items.append(io);
    }
    obj["items"] = items;
    return obj;
}

// 2026-09-21: 阶段 L3.3 - importFromJson 返回 Result<bool>
QVariantMap ChecklistService::importFromJson(const QJsonObject& json) {
    using namespace outdoor::internal;

    Checklist list;
    list.id = json["id"].toString();
    if (list.id.isEmpty()) {
        list.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    }
    list.name = json["name"].toString();
    list.scenario = json["scenario"].toString();
    list.description = json["description"].toString();
    list.isTemplate = false;

    for (const auto& v : json["items"].toArray()) {
        QJsonObject io = v.toObject();
        Item item;
        item.id = io["id"].toString();
        if (item.id.isEmpty()) {
            item.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        }
        item.name = io["name"].toString();
        item.category = io["category"].toString();
        item.quantity = io["quantity"].toInt();
        item.weightG = io["weightG"].toDouble();
        item.required = io["required"].toBool();
        item.note = io["note"].toString();
        for (const auto& a : io["alternatives"].toArray()) {
            item.alternatives << a.toString();
        }
        list.items.append(item);
    }

    recomputeStats(list);
    return saveChecklist(list);  // 透传 saveChecklist 的 Result
}

double ChecklistService::getTotalWeight(const QString& checklistId) {
    auto it = m_checklists.constFind(checklistId);
    if (it == m_checklists.constEnd()) return 0;
    return it.value().totalWeightG;
}

int ChecklistService::getCheckedCount(const QString& checklistId) {
    auto it = m_checklists.constFind(checklistId);
    if (it == m_checklists.constEnd()) return 0;
    return it.value().checkedCount;
}

} // namespace outdoor
