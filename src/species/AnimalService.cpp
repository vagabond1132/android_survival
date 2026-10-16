/**
 * @file AnimalService.cpp
 * @brief 动物图鉴服务实现
 */

#include "AnimalService.h"
#include "SpeciesLocationOps.h"        // 2026-09-21 阶段 L4.2: 抽到 Ops
#include "../core/AssetLoader.h"
#include "../core/Logger.h"

#include <QSet>
#include <QVector>
#include <algorithm>
#include <cmath>

namespace outdoor {

AnimalService::AnimalService(Database* db, QObject* parent)
    
    : ServiceBase(db, "AnimalService", parent) {
}

AnimalService::~AnimalService() {
}

bool AnimalService::loadInitialData() {
    // 之前 applicationDirPath() 候选在 Android 永远失败, 实际只有 qrc 路径生效
    const QString dataDir = AssetLoader::assetRoot();
    m_index.loadAll(dataDir);
    emit dataChanged();
    if (m_index.animalCount() == 0) {
        Logger::warn(QString("AnimalService: loaded 0 animals from %1").arg(dataDir));
    }
    return m_index.animalCount() > 0;
}

int AnimalService::totalCount() const { return m_index.animalCount(); }

int AnimalService::snakeCount() const {
    int n = 0;
    for (const auto& e : m_index.animals()) {
        if (e.category.startsWith("venomous_snake") || e.category.startsWith("non_venomous_snake")) ++n;
    }
    return n;
}

int AnimalService::dangerousCount() const {
    int n = 0;
    for (const auto& e : m_index.animals()) if (e.dangerLevel >= 4) ++n;
    return n;
}

QVariantMap AnimalService::entityToMap(const FieldGuideEntity& e) const {
    return FieldGuideIndex::toMap(e);
}

QVariantList AnimalService::getAll() {
    QVariantList list;
    for (const auto& e : m_index.animals()) list.append(entityToMap(e));
    return list;
}

QVariantMap AnimalService::getById(const QString& id) {
    const auto* e = m_index.getById(id);
    if (!e || e->kingdom != "animalia") return {};
    return entityToMap(*e);
}

QVariantList AnimalService::search(const QString& keyword) {
    QVariantList list;
    for (const auto& e : m_index.animals()) {
        if (e.commonName.contains(keyword, Qt::CaseInsensitive) ||
            e.scientificName.contains(keyword, Qt::CaseInsensitive) ||
            e.alias.join(",").contains(keyword, Qt::CaseInsensitive)) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

QVariantList AnimalService::getSnakes(bool venomousOnly) {
    QVariantList list;
    for (const auto& e : m_index.animals()) {
        if (e.category.startsWith("venomous_snake") ||
            (!venomousOnly && e.category.startsWith("non_venomous_snake"))) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

QVariantList AnimalService::getMammals() {
    QVariantList list;
    for (const auto& e : m_index.animals()) {
        if (e.category.startsWith("mammal") || e.category == "dangerous_beast") {
            list.append(entityToMap(e));
        }
    }
    return list;
}

QVariantList AnimalService::getDangerous(int minLevel) {
    QVariantList list;
    for (const auto& e : m_index.animals()) {
        if (e.dangerLevel >= minLevel) list.append(entityToMap(e));
    }
    return list;
}

QVariantList AnimalService::getByCategory(const QString& category) {
    QVariantList list;
    for (const auto& e : m_index.animals()) {
        if (e.category == category) list.append(entityToMap(e));
    }
    return list;
}

QVariantList AnimalService::getByProvince(const QString& province) {
    if (province.isEmpty() || province == "全部") return getAll();
    QVariantList list;
    for (const auto& e : m_index.animals()) {
        if (FieldGuideIndex::matchProvince(e.distribution, province)) list.append(entityToMap(e));
    }
    return list;
}

QVariantList AnimalService::getByMonth(int month) {
    QVariantList list;
    // 2026-09-14: month=0 表示"全部月份", 跳过月份过滤 (修"山东动物月份全部 0 条" bug)
    if (month == 0) {
        for (const auto& e : m_index.animals()) list.append(entityToMap(e));
        return list;
    }
    QString m = QString::number(month);
    for (const auto& e : m_index.animals()) {
        if (e.activeMonths.contains(m) && !e.hibernationMonths.contains(m)) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

QVariantList AnimalService::getByProvinceAndMonth(const QString& province, int month) {
    QVariantList list;
    // 2026-09-14: month=0 表示"全部月份", 跳过月份过滤
    QString m = (month >= 1 && month <= 12) ? QString::number(month) : QString();
    for (const auto& e : m_index.animals()) {
        bool prov = FieldGuideIndex::matchProvince(e.distribution, province);
        // 冬眠月过滤: month=0 不过滤; 具体月时排除冬眠
        bool hibernationOk = m.isEmpty() || !e.hibernationMonths.contains(m);
        // 活动月过滤: month=0 全部通过; 具体月时要求 activeMonths 包含
        bool activeOk = m.isEmpty() || e.activeMonths.contains(m);
        if (prov && activeOk && hibernationOk) list.append(entityToMap(e));
    }
    return list;
}

QStringList AnimalService::getAvailableProvinces() {
    // 2026-09-24: 改用归一化 (原始 distribution 是自由文本 "河北(燕山)"/"安徽(邻近)")
    QStringList all;
    for (const auto& e : m_index.animals()) {
        for (const auto& p : e.distribution) all.append(p);
    }
    return FieldGuideIndex::canonicalProvinces(all);
}

QVariantList AnimalService::getAlongRoute(const QString& routeId, int month) {
    QVariantList list;
    QString m = QString::number(month);
    for (const auto& e : m_index.animals()) {
        for (const auto& p : e.routeAssociations) {
            if (p.first == routeId) {
                if (month <= 0 || p.second.contains(m)) {
                    list.append(entityToMap(e));
                    break;
                }
            }
        }
    }
    return list;
}

QVariantList AnimalService::getLookAlike(const QString& id) {
    QVariantList list;
    const auto* e = m_index.getById(id);
    if (!e) return list;
    for (const auto& item : e->lookAlike) {
        const auto* other = item.id.isEmpty() ? nullptr : m_index.getById(item.id);
        QVariantMap m = other ? entityToMap(*other) : QVariantMap();
        m["id"] = item.id;
        if (m.value("commonName").toString().isEmpty()) m["commonName"] = item.name;
        m["name"] = item.name;
        m["distinction"] = item.distinction;
        m["fatality"] = item.fatality;
        list.append(m);
    }
    return list;
}

QVariantList AnimalService::getByFirstAid(const QString& firstAidId) {
    QVariantList list;
    for (const auto& e : m_index.animals()) {
        if (e.firstAidId == firstAidId ||
            e.firstAidLinks.values().contains(firstAidId)) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

// 2026-09-21 阶段 L4.2: 抽到 SpeciesLocationOps
QVariantMap AnimalService::recordLocation(const QString& animalId, double lat, double lon,
                                            const QString& note) {
    return SpeciesLocationOps::recordLocation(
        m_db, SpeciesLocationRepository::Kind::Animal, animalId, lat, lon, note);
}

QVariantList AnimalService::getLocationsByAnimal(const QString& animalId) {
    return SpeciesLocationOps::listByEntity(
        m_db, SpeciesLocationRepository::Kind::Animal, animalId, "animalId");
}

QVariantList AnimalService::getLocationsNear(double lat, double lon, double radiusKm) {
    Q_UNUSED(radiusKm);
    return SpeciesLocationOps::listNear(
        m_db, SpeciesLocationRepository::Kind::Animal, lat, lon);
}

QVariantList AnimalService::matchByColor(const QVariantMap& userColor, int topK) {
    QVector<QPair<double, QString>> scored;
    for (const auto& e : m_index.animals()) {
        if (e.representativeColor.isEmpty()) continue;
        int dh = std::min(std::abs(userColor.value("h").toInt() - e.representativeColor.value("h").toInt()),
                          360 - std::abs(userColor.value("h").toInt() - e.representativeColor.value("h").toInt()));
        int ds = userColor.value("s").toInt() - e.representativeColor.value("s").toInt();
        int dv = userColor.value("v").toInt() - e.representativeColor.value("v").toInt();
        double d = std::sqrt(double(dh * dh + ds * ds + dv * dv));
        scored.append({d, e.id});
    }
    std::sort(scored.begin(), scored.end());
    QVariantList list;
    for (int i = 0; i < std::min<long long>(topK, scored.size()); ++i) {
        QVariantMap m = getById(scored[i].second);
        if (!m.isEmpty()) {
            m["similarity"] = std::max(0.0, 100.0 - scored[i].first / 6.26);
            list.append(m);
        }
    }
    return list;
}

} // namespace outdoor
