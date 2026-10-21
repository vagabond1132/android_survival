/**
 * @file FirstAidService.cpp
 */

#include "FirstAidService.h"
#include "../core/AssetLoader.h"
#include "../core/Database.h"
#include "../core/Logger.h"
#include "../core/Result.h"                 // 2026-09-21: Phase 5 批次 3
#include "../core/ServiceErrors.h"          // 2026-09-21: Phase 5 批次 3
#include "../core/internal/QmlResultBridge.h" // 2026-09-21: Phase 5 批次 3
#include "../common/DbHelper.h"  // 2026-09-21 阶段 L2.2

#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QSet>
#include <QDir>
#include <QStandardPaths>
#include <QSqlQuery>
#include <QSqlError>
#include <QUrl>

namespace outdoor {

FirstAidService::FirstAidService(Database* db, QObject* parent)
    
    : ServiceBase(db, "FirstAidService", parent) {
}

FirstAidService::~FirstAidService() = default;

bool FirstAidService::loadInitialData() {
    if (!ensureSchema()) {
        Logger::error("FirstAid: ensureSchema failed");
        return false;
    }

    // 1. 优先从 assets 加载初始数据
    if (loadFromJson()) {
        Logger::info("FirstAid: initial data loaded from JSON");
    }

    // 2. 如果数据库空，插入示例
    if (m_entries.isEmpty()) {
        Logger::warn("FirstAid: no entries loaded");
    }

    return true;
}

bool FirstAidService::ensureSchema() {
    if (!m_db || !m_db->isOpen(Database::Name::FirstAid)) {
        return false;
    }

    QSqlDatabase db = m_db->get(Database::Name::FirstAid);
    QSqlQuery q(db);

    // 辅助 lambda: 执行 DDL 并检查返回值, 失败记日志但不中断(后续 INSERT 会暴露问题)
    // 2026-09-21 阶段 L2.2: 切 DbHelper::execDdl (内含错误日志 + db closed 检查)
    auto execDdl = [&q](const QString& sql, const QString& name) {
        return DbHelper::execDdl(q, sql,
            QStringLiteral("FirstAid DDL [%1]").arg(name));
    };

    bool ok = true;
    ok &= execDdl(R"(
        CREATE TABLE IF NOT EXISTS firstaid_entries (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            category INTEGER NOT NULL,
            urgency INTEGER NOT NULL,
            symptoms TEXT,
            description TEXT,
            critical_actions TEXT,
            steps TEXT,
            donts TEXT,
            related_species TEXT,
            video_url TEXT,
            source TEXT,
            reviewer TEXT,
            last_reviewed TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        )
    )", "firstaid_entries");

    ok &= execDdl(R"(
        CREATE TABLE IF NOT EXISTS firstaid_decision_nodes (
            id TEXT PRIMARY KEY,
            entry_id TEXT NOT NULL,
            parent_id TEXT,
            question TEXT,
            text TEXT,
            options TEXT,
            is_terminal INTEGER DEFAULT 0,
            terminal_action TEXT,
            FOREIGN KEY (entry_id) REFERENCES firstaid_entries(id) ON DELETE CASCADE
        )
    )", "firstaid_decision_nodes");

    ok &= execDdl(R"(
        CREATE TABLE IF NOT EXISTS firstaid_kits (
            scenario TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            items TEXT,
            total_weight_g INTEGER,
            estimated_cost_cny INTEGER
        )
    )", "firstaid_kits");

    ok &= execDdl("CREATE INDEX IF NOT EXISTS idx_fa_urgency ON firstaid_entries(urgency)",
                  "idx_fa_urgency");
    ok &= execDdl("CREATE INDEX IF NOT EXISTS idx_fa_category ON firstaid_entries(category)",
                  "idx_fa_category");

    return ok;
}

bool FirstAidService::loadFromJson() {
    // 统一通过 AssetLoader 加载, 路径前缀 ://qt/qml/OutdoorSurvival/assets/data/
    // 之前 2 条候选路径 (含 qrc://) 实际上指向同一资源, 现在收敛到 1 条
    QString err;
    auto doc = AssetLoader::loadJson("firstaid_entries.json", &err);
    if (!doc) {
        Logger::warn(QString("FirstAid: %1").arg(err));
        return false;
    }
    if (!doc->isObject()) {
        Logger::error("FirstAid: invalid JSON root");
        return false;
    }

    QJsonObject root = doc->object();
    int loadedEntries = 0;
    int loadedNodes = 0;
    int loadedKits = 0;

    // 加载 entries
    QJsonArray entries = root["entries"].toArray();
    for (const auto& v : entries) {
        QJsonObject e = v.toObject();
        Entry entry;
        entry.id = e["id"].toString();
        entry.title = e["title"].toString();
        entry.category = static_cast<Category>(e["category"].toInt());
        entry.urgency = static_cast<Urgency>(e["urgency"].toInt());
        entry.description = e["description"].toString();
        entry.videoUrl = e["video_url"].toString();
        entry.source = e["source"].toString();
        entry.reviewer = e["reviewer"].toString();

        // 数组字段
        for (const auto& s : e["symptoms"].toArray())
            entry.symptoms << s.toString();
        for (const auto& s : e["critical_actions"].toArray())
            entry.criticalActions << s.toString();
        for (const auto& s : e["steps"].toArray())
            entry.steps << s.toString();
        for (const auto& s : e["donts"].toArray())
            entry.donts << s.toString();
        for (const auto& s : e["related_species"].toArray())
            entry.relatedSpecies << s.toString();

        m_entries[entry.id] = entry;
        loadedEntries++;
    }

    // 加载决策树
    QJsonArray nodes = root["decision_nodes"].toArray();
    QHash<QString, QString> nodeEntryId;   // nodeId -> entryId (只在建根时用, 不进结构体)
    QSet<QString> referenced;              // 被任何 next_id 指过的节点 = 一定不是根
    for (const auto& v : nodes) {
        QJsonObject n = v.toObject();
        DecisionNode node;
        node.id = n["id"].toString();
        node.question = n["question"].toString();
        node.text = n["text"].toString();
        node.terminalAction = n["terminal_action"].toString();

        const QString entryId = n["entry_id"].toString();

        for (const auto& opt : n["options"].toArray()) {
            QJsonObject o = opt.toObject();
            QString label = o["label"].toString();
            QString nextId = o["next_id"].toString();
            node.options << label;
            node.nextNodes[label] = nextId;
            if (!nextId.isEmpty()) referenced.insert(nextId);
        }

        m_decisionNodes[node.id] = node;
        if (!entryId.isEmpty()) nodeEntryId.insert(node.id, entryId);
        loadedNodes++;
    }

    // 2026-10-20 建根改口径: 原来按"该 entry 第一个出现的节点"当根, 靠的是
    // firstaid_entries.json 里根节点恰好排在最前 —— 数据一旦重排, getDecisionRoot()
    // 就会返回一个终态叶子 (question 为空), 决策页整页没有问题也没有选项 (2026-10-16
    // 那次修的就是这个). 现在按图论定义找根: 没有被任何 next_id 指过的节点才是根.
    for (auto it = nodeEntryId.constBegin(); it != nodeEntryId.constEnd(); ++it) {
        if (referenced.contains(it.key())) continue;
        const QString entryId = it.value();
        const QString existing = m_entryRoots.value(entryId);
        // 一棵树正常情况下只有一个根; 数据里若出现多根 (孤儿节点), 保留字典序小的那个,
        // 免得每次启动随机挑一个 —— m_decisionNodes 是 QHash, 遍历序不稳.
        if (existing.isEmpty() || it.key() < existing) m_entryRoots[entryId] = it.key();
    }

    // 加载急救包模板
    QJsonArray kits = root["kit_templates"].toArray();
    for (const auto& v : kits) {
        QJsonObject kit = v.toObject();
        m_kitTemplates[kit["scenario"].toString()] = kit;
        loadedKits++;
    }

    Logger::info(QString("FirstAid loaded: %1 entries, %2 nodes, %3 kits")
                     .arg(loadedEntries).arg(loadedNodes).arg(loadedKits));
    emit dataChanged();
    return loadedEntries > 0;
}

int FirstAidService::totalEntries() const {
    return m_entries.size();
}

int FirstAidService::criticalCount() const {
    int n = 0;
    for (const auto& e : m_entries) {
        if (e.urgency >= Urgency::High) n++;
    }
    return n;
}

// 2026-09-21: Phase 5 批次 3 - getAllEntries 返回 Result (FirstAidPage 主列表)
QVariantMap FirstAidService::getAllEntries() {
    using namespace outdoor::internal;
    QVariantList list;
    for (const auto& e : m_entries) {
        QVariantMap m;
        m["id"] = e.id;
        m["title"] = e.title;
        m["category"] = static_cast<int>(e.category);
        m["urgency"] = static_cast<int>(e.urgency);
        m["description"] = e.description;
        m["symptoms"] = e.symptoms;
        m["criticalActions"] = e.criticalActions;
        m["donts"] = e.donts;
        list.append(m);
    }
    return toQVariant(Ok(list));
}

QVariantList FirstAidService::getByCategory(Category cat) {
    QVariantList list;
    for (const auto& e : m_entries) {
        if (e.category == cat) {
            QVariantMap m;
            m["id"] = e.id;
            m["title"] = e.title;
            m["urgency"] = static_cast<int>(e.urgency);
            list.append(m);
        }
    }
    return list;
}

QVariantList FirstAidService::getByUrgency(Urgency urgency) {
    QVariantList list;
    for (const auto& e : m_entries) {
        if (e.urgency == urgency) {
            QVariantMap m;
            m["id"] = e.id;
            m["title"] = e.title;
            m["urgency"] = static_cast<int>(e.urgency);
            list.append(m);
        }
    }
    return list;
}

QVariantList FirstAidService::getCritical() {
    QVariantList list;
    for (const auto& e : m_entries) {
        if (e.urgency >= Urgency::High) {
            QVariantMap m;
            m["id"] = e.id;
            m["title"] = e.title;
            m["urgency"] = static_cast<int>(e.urgency);
            m["category"] = static_cast<int>(e.category);
            list.append(m);
        }
    }
    return list;
}

QVariantMap FirstAidService::getById(const QString& id) {
    QVariantMap result;
    auto it = m_entries.constFind(id);
    if (it == m_entries.constEnd()) {
        Logger::warn("FirstAid entry not found: " + id);
        return result;
    }

    const Entry& e = it.value();
    result["id"] = e.id;
    result["title"] = e.title;
    result["category"] = static_cast<int>(e.category);
    result["categoryName"] = [](Category c) {
        switch (c) {
            case Category::Critical: return "急症优先";
            case Category::Trauma: return "创伤处理";
            case Category::Environment: return "环境急症";
            case Category::Poison: return "中毒急救";
            case Category::Emergency: return "应急功能";
        }
        return "";
    }(e.category);
    result["urgency"] = static_cast<int>(e.urgency);
    result["urgencyName"] = [](Urgency u) {
        switch (u) {
            case Urgency::Info: return "知识";
            case Urgency::Low: return "低";
            case Urgency::Medium: return "中";
            case Urgency::High: return "高";
            case Urgency::Crisis: return "危急";
        }
        return "";
    }(e.urgency);
    // 2026-09-14: QStringList 转 QVariantList 让 QML 端是普通 JS array (支持 join/filter/map)
    auto toVL = [](const QStringList& sl) {
        QVariantList vl;
        for (const auto& s : sl) vl.append(s);
        return vl;
    };
    result["symptoms"] = toVL(e.symptoms);
    result["description"] = e.description;
    result["criticalActions"] = toVL(e.criticalActions);
    result["steps"] = toVL(e.steps);
    result["donts"] = toVL(e.donts);
    result["relatedSpecies"] = toVL(e.relatedSpecies);
    result["videoUrl"] = e.videoUrl;
    result["source"] = e.source;
    result["reviewer"] = e.reviewer;
    // 2026-09-14: 是否存在决策树根 (供 QML 决定是否显示 "启动交互式决策" 按钮)
    result["decisionNodeExists"] = m_entryRoots.contains(id);
    return result;
}

QVariantList FirstAidService::search(const QString& keyword) {
    QVariantList list;
    if (keyword.isEmpty()) return list;

    QString kw = keyword.toLower();
    for (const auto& e : m_entries) {
        if (e.title.contains(keyword, Qt::CaseInsensitive) ||
            e.description.contains(keyword, Qt::CaseInsensitive)) {
            QVariantMap m;
            m["id"] = e.id;
            m["title"] = e.title;
            m["urgency"] = static_cast<int>(e.urgency);
            list.append(m);
        }
    }
    return list;
}

QVariantMap FirstAidService::getDecisionRoot(const QString& entryId) {
    auto rootIt = m_entryRoots.constFind(entryId);
    if (rootIt == m_entryRoots.constEnd()) {
        return {};
    }
    return getDecisionNode(rootIt.value());
}

QVariantMap FirstAidService::getDecisionNode(const QString& nodeId) {
    QVariantMap result;
    auto it = m_decisionNodes.constFind(nodeId);
    if (it == m_decisionNodes.constEnd()) {
        return result;
    }

    const DecisionNode& n = it.value();
    result["id"] = n.id;
    result["question"] = n.question;
    result["text"] = n.text;
    result["options"] = n.options;
    result["isTerminal"] = !n.terminalAction.isEmpty();
    result["terminalAction"] = n.terminalAction;
    // 2026-10-20 修决策树走不动: nextNodes 只在 C++ 侧, QML 拿不到就只能猜 id 规则,
    // 而旧页面猜的是 "当前 id + _ + 序号", 数据里的真实 id 是 snake_bite_step2 这种
    // 语义名 → 每一点都查不到节点, 立刻掉进"按关键步骤操作"的假终态. 按 options 的
    // 顺序把下一跳 id 一起给出去, QML 直接按下标走.
    QVariantList nextIds;
    nextIds.reserve(n.options.size());
    for (const QString& label : n.options) nextIds.append(n.nextNodes.value(label));
    result["nextIds"] = nextIds;
    return result;
}

QVariantList FirstAidService::getDecisionPath(const QString& entryId,
                                                  const QStringList& choices) {
    QVariantList path;

    QString currentId = m_entryRoots.value(entryId, QString());
    if (currentId.isEmpty()) return path;

    for (const QString& choice : choices) {
        QVariantMap node = getDecisionNode(currentId);
        if (node.isEmpty()) break;
        path.append(node);

        QString nextId = m_decisionNodes[currentId].nextNodes.value(choice);
        if (nextId.isEmpty()) break;
        currentId = nextId;
    }

    return path;
}

QVariantList FirstAidService::getKitTemplates() {
    QVariantList list;
    for (auto it = m_kitTemplates.constBegin();
         it != m_kitTemplates.constEnd(); ++it) {
        QVariantMap m;
        m["scenario"] = it.key();
        m["name"] = it.value()["name"].toString();
        m["description"] = it.value()["description"].toString();
        m["totalItems"] = it.value()["items"].toArray().size();
        m["totalWeightG"] = it.value()["total_weight_g"].toInt();
        list.append(m);
    }
    return list;
}

QVariantMap FirstAidService::getKitTemplate(const QString& scenario) {
    return m_kitTemplates.value(scenario).toVariantMap();
}

QStringList FirstAidService::getRelatedSpecies(const QString& entryId) {
    auto it = m_entries.constFind(entryId);
    if (it == m_entries.constEnd()) return {};
    return it.value().relatedSpecies;
}

} // namespace outdoor
