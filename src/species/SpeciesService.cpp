/**
 * @file SpeciesService.cpp
 */

#include "SpeciesService.h"
#include "../common/DbHelper.h"  // 2026-09-21 阶段 L2.2
#include "../core/AssetLoader.h"
#include "../core/Database.h"
#include "../core/Logger.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSqlQuery>
#include <QSqlError>
#include <algorithm>

namespace outdoor {

SpeciesService::SpeciesService(Database* db, QObject* parent)
    
    : ServiceBase(db, "SpeciesService", parent) {
}

SpeciesService::~SpeciesService() = default;

bool SpeciesService::loadInitialData() {
    if (!ensureSchema()) return false;
    return loadFromJson();
}

bool SpeciesService::ensureSchema() {
    if (!m_db || !m_db->isOpen(Database::Name::Species)) return false;
    QSqlDatabase db = m_db->get(Database::Name::Species);
    QSqlQuery q(db);

    // 2026-09-21 阶段 L2.2: 切 DbHelper::execDdl (内含错误日志 + db closed 检查)
    auto execDdl = [&q](const QString& sql, const QString& name) {
        return DbHelper::execDdl(q, sql, QString("SpeciesService::ensureSchema(%1)").arg(name));
    };

    bool ok = true;
    ok &= execDdl(R"(
        CREATE TABLE IF NOT EXISTS species (
            id TEXT PRIMARY KEY,
            common_name TEXT NOT NULL,
            scientific_name TEXT,
            category INTEGER,
            danger_level INTEGER,
            alias TEXT,
            features TEXT,
            distribution TEXT,
            min_elevation INTEGER,
            max_elevation INTEGER,
            habitats TEXT,
            active_months TEXT,
            symptoms TEXT,
            first_aid_id TEXT,
            protective_gear TEXT,
            photos TEXT,
            description TEXT,
            source TEXT,
            reviewer TEXT
        )
    )", "species");
    ok &= execDdl("CREATE INDEX IF NOT EXISTS idx_sp_category ON species(category)",
                  "idx_sp_category");
    ok &= execDdl("CREATE INDEX IF NOT EXISTS idx_sp_danger ON species(danger_level)",
                  "idx_sp_danger");
    return ok;
}

bool SpeciesService::loadFromJson() {
    QString err;
    auto doc = AssetLoader::loadJson("danger_species.json", &err);
    if (!doc) {
        Logger::warn(QString("SpeciesService: %1").arg(err));
        return false;
    }
    if (!doc->isObject()) {
        Logger::warn("SpeciesService: danger_species.json root is not an object");
        return false;
    }

    QJsonArray arr = doc->object()["species"].toArray();
    int count = 0;
    for (const auto& v : arr) {
        QJsonObject o = v.toObject();
        SpeciesInfo sp;
        sp.id = o["id"].toString();
        sp.commonName = o["common_name"].toString();
        sp.scientificName = o["scientific_name"].toString();
        sp.category = static_cast<Category>(o["category"].toInt());
        sp.dangerLevel = o["danger_level"].toInt();
        sp.minElevation = o["min_elevation"].toInt();
        sp.maxElevation = o["max_elevation"].toInt();
        sp.firstAidId = o["first_aid_id"].toString();
        sp.description = o["description"].toString();
        sp.source = o["source"].toString();
        sp.reviewer = o["reviewer"].toString();

        for (const auto& a : o["alias"].toArray()) sp.alias << a.toString();
        for (const auto& f : o["features"].toArray()) sp.features << f.toString();
        for (const auto& d : o["distribution"].toArray()) sp.distribution << d.toString();
        for (const auto& h : o["habitats"].toArray()) sp.habitats << h.toString();
        for (const auto& m : o["active_months"].toArray()) sp.activeMonths << m.toString();
        for (const auto& s : o["symptoms"].toArray()) sp.symptoms << s.toString();
        for (const auto& g : o["protective_gear"].toArray()) sp.protectiveGear << g.toString();
        for (const auto& p : o["photos"].toArray()) sp.photos << p.toString();

        m_species[sp.id] = sp;
        count++;
    }

    Logger::info(QString("SpeciesService loaded: %1 entries").arg(count));
    emit dataChanged();
    return count > 0;
}

int SpeciesService::totalCount() const {
    return m_species.size();
}

int SpeciesService::dangerousCount() const {
    int n = 0;
    for (const auto& sp : m_species) {
        if (sp.dangerLevel >= 3) n++;
    }
    return n;
}

QVariantList SpeciesService::getAll() {
    QVariantList list;
    for (const auto& sp : m_species) {
        QVariantMap m;
        m["id"] = sp.id;
        m["commonName"] = sp.commonName;
        m["scientificName"] = sp.scientificName;
        m["category"] = static_cast<int>(sp.category);
        m["dangerLevel"] = sp.dangerLevel;
        list.append(m);
    }
    return list;
}

QVariantList SpeciesService::getByCategory(Category cat) {
    QVariantList list;
    for (const auto& sp : m_species) {
        if (sp.category == cat) {
            QVariantMap m;
            m["id"] = sp.id;
            m["commonName"] = sp.commonName;
            m["dangerLevel"] = sp.dangerLevel;
            list.append(m);
        }
    }
    return list;
}

QVariantList SpeciesService::getDangerous(int minLevel) {
    QVariantList list;
    for (const auto& sp : m_species) {
        if (sp.dangerLevel >= minLevel) {
            QVariantMap m;
            m["id"] = sp.id;
            m["commonName"] = sp.commonName;
            m["dangerLevel"] = sp.dangerLevel;
            m["category"] = static_cast<int>(sp.category);
            list.append(m);
        }
    }
    // 按危险度倒序
    std::sort(list.begin(), list.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap()["dangerLevel"].toInt() > b.toMap()["dangerLevel"].toInt();
    });
    return list;
}

QVariantMap SpeciesService::getById(const QString& id) {
    QVariantMap result;
    auto it = m_species.constFind(id);
    if (it == m_species.constEnd()) return result;

    const SpeciesInfo& sp = it.value();
    result["id"] = sp.id;
    result["commonName"] = sp.commonName;
    result["scientificName"] = sp.scientificName;
    result["category"] = static_cast<int>(sp.category);
    result["categoryName"] = [](Category c) {
        switch (c) {
            case Category::Snake: return "蛇类";
            case Category::Mushroom: return "蘑菇";
            case Category::Insect: return "昆虫";
            case Category::Plant: return "植物";
            case Category::Animal: return "动物";
        }
        return "";
    }(sp.category);
    result["dangerLevel"] = sp.dangerLevel;
    // 2026-09-19: QStringList → QVariantList 转换 (同 FieldGuideIndex::toMap 修复).
    //   QML 端 QStringList 是 QQmlListModel (有 length 但无 join/filter 等 Array 方法),
    //   而且 Section.qml._refreshItems 用 `items[i]` 取值时部分情况下返回 undefined.
    //   显式转 QVariantList → JS Array, 杜绝"识别特征 无信息"等空数据展示.
    auto toVariantList = [](const QStringList& sl) {
        QVariantList vl;
        for (const auto& s : sl) vl.append(s);
        return vl;
    };
    result["alias"] = toVariantList(sp.alias);
    result["features"] = toVariantList(sp.features);
    result["distribution"] = toVariantList(sp.distribution);
    result["elevationRange"] = QString("%1-%2m").arg(sp.minElevation).arg(sp.maxElevation);
    result["habitats"] = toVariantList(sp.habitats);
    result["activeMonths"] = toVariantList(sp.activeMonths);
    result["symptoms"] = toVariantList(sp.symptoms);
    result["firstAidId"] = sp.firstAidId;
    result["protectiveGear"] = toVariantList(sp.protectiveGear);
    result["photos"] = toVariantList(sp.photos);
    result["description"] = sp.description;
    result["source"] = sp.source;
    result["reviewer"] = sp.reviewer;
    return result;
}

QVariantList SpeciesService::search(const QString& keyword) {
    QVariantList list;
    if (keyword.isEmpty()) return list;
    for (const auto& sp : m_species) {
        if (sp.commonName.contains(keyword, Qt::CaseInsensitive) ||
            sp.scientificName.contains(keyword, Qt::CaseInsensitive)) {
            QVariantMap m;
            m["id"] = sp.id;
            m["commonName"] = sp.commonName;
            m["dangerLevel"] = sp.dangerLevel;
            list.append(m);
        }
    }
    return list;
}

QVariantList SpeciesService::getForRegion(const QString& province) {
    QVariantList list;
    for (const auto& sp : m_species) {
        if (sp.distribution.contains(province)) {
            QVariantMap m;
            m["id"] = sp.id;
            m["commonName"] = sp.commonName;
            m["dangerLevel"] = sp.dangerLevel;
            list.append(m);
        }
    }
    return list;
}

QString SpeciesService::getFirstAidId(const QString& speciesId) {
    auto it = m_species.constFind(speciesId);
    if (it == m_species.constEnd()) return QString();
    return it.value().firstAidId;
}

} // namespace outdoor
