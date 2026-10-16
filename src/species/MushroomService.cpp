/**
 * @file MushroomService.cpp
 * @brief 蘑菇图鉴实现
 */

#include "MushroomService.h"
#include "SpeciesLocationOps.h"        // 2026-09-21 阶段 L4.2: 抽到 Ops
#include "../core/AssetLoader.h"
#include "../core/Logger.h"

#include <QSet>
#include <QVector>
#include <algorithm>

namespace outdoor {

MushroomService::MushroomService(Database* db, QObject* parent)
    
    : ServiceBase(db, "MushroomService", parent) {
}

MushroomService::~MushroomService() {
}

bool MushroomService::loadInitialData() {
    const QString dataDir = AssetLoader::assetRoot();
    m_index.loadAll(dataDir);
    emit dataChanged();
    if (m_index.mushroomCount() == 0) {
        Logger::warn(QString("MushroomService: loaded 0 mushrooms from %1").arg(dataDir));
    }
    return m_index.mushroomCount() > 0;
}

int MushroomService::totalCount() const { return m_index.mushroomCount(); }

int MushroomService::deadlyCount() const {
    int n = 0;
    for (const auto& e : m_index.mushrooms()) if (e.dangerLevel >= 5) ++n;
    return n;
}

int MushroomService::edibleCount() const {
    int n = 0;
    for (const auto& e : m_index.mushrooms()) if (e.dangerLevel == 0) ++n;
    return n;
}

QVariantMap MushroomService::entityToMap(const FieldGuideEntity& e) const {
    return FieldGuideIndex::toMap(e);
}

QVariantList MushroomService::getAll() {
    QVariantList list;
    for (const auto& e : m_index.mushrooms()) list.append(entityToMap(e));
    return list;
}

QVariantMap MushroomService::getById(const QString& id) {
    const auto* e = m_index.getById(id);
    if (!e || e->kingdom != "fungi") return {};
    return entityToMap(*e);
}

QVariantList MushroomService::search(const QString& keyword) {
    QVariantList list;
    for (const auto& e : m_index.mushrooms()) {
        if (e.commonName.contains(keyword, Qt::CaseInsensitive) ||
            e.scientificName.contains(keyword, Qt::CaseInsensitive) ||
            e.alias.join(",").contains(keyword, Qt::CaseInsensitive)) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

QVariantList MushroomService::getByCategory(const QString& category) {
    QVariantList list;
    for (const auto& e : m_index.mushrooms()) {
        if (e.category == category) list.append(entityToMap(e));
    }
    return list;
}

QVariantList MushroomService::getDeadly() {
    return getByCategory("deadly_mushroom");
}

QVariantList MushroomService::getEdible() {
    QVariantList list;
    for (const auto& e : m_index.mushrooms()) {
        if (e.dangerLevel == 0) list.append(entityToMap(e));
    }
    return list;
}

QVariantList MushroomService::getByProvince(const QString& province) {
    if (province.isEmpty() || province == "全部") return getAll();
    QVariantList list;
    for (const auto& e : m_index.mushrooms()) {
        if (FieldGuideIndex::matchProvince(e.distribution, province)) list.append(entityToMap(e));
    }
    return list;
}

QVariantList MushroomService::getByMonth(int month) {
    QVariantList list;
    // 2026-09-14: month=0 表示"全部月份", 跳过月份过滤
    if (month == 0) {
        for (const auto& e : m_index.mushrooms()) list.append(entityToMap(e));
        return list;
    }
    QString m = QString::number(month);
    for (const auto& e : m_index.mushrooms()) {
        if (e.activeMonths.contains(m)) list.append(entityToMap(e));
    }
    return list;
}

// 2026-09-24: 补 - FieldGuidePage 省份+月份组合筛选调用此方法, 之前蘑菇无此方法,
//   ServiceListModel 报 "method not found" → 列表空.
QVariantList MushroomService::getByProvinceAndMonth(const QString& province, int month) {
    QVariantList list;
    QString m = (month >= 1 && month <= 12) ? QString::number(month) : QString();
    for (const auto& e : m_index.mushrooms()) {
        bool prov = FieldGuideIndex::matchProvince(e.distribution, province);
        bool mon = m.isEmpty() || e.activeMonths.contains(m);
        if (prov && mon) list.append(entityToMap(e));
    }
    return list;
}

QStringList MushroomService::getAvailableProvinces() {
    // 2026-09-24: 改用归一化 (原始 distribution 是自由文本 "河南(豫南)"/"河北(坝上)")
    QStringList all;
    for (const auto& e : m_index.mushrooms()) {
        for (const auto& p : e.distribution) all.append(p);
    }
    return FieldGuideIndex::canonicalProvinces(all);
}

QVariantList MushroomService::getLookAlike(const QString& id) {
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

QVariantList MushroomService::getByFirstAid(const QString& firstAidId) {
    QVariantList list;
    for (const auto& e : m_index.mushrooms()) {
        if (e.firstAidId == firstAidId || e.firstAidLinks.values().contains(firstAidId)) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

QVariantList MushroomService::getAlongRoute(const QString& routeId, int month) {
    QVariantList list;
    QString m = QString::number(month);
    for (const auto& e : m_index.mushrooms()) {
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

// 2026-09-21 阶段 L4.2: 抽到 SpeciesLocationOps
QVariantMap MushroomService::recordLocation(const QString& mushroomId, double lat, double lon,
                                              const QString& note) {
    return SpeciesLocationOps::recordLocation(
        m_db, SpeciesLocationRepository::Kind::Mushroom, mushroomId, lat, lon, note);
}

QVariantList MushroomService::getLocationsByMushroom(const QString& mushroomId) {
    return SpeciesLocationOps::listByEntity(
        m_db, SpeciesLocationRepository::Kind::Mushroom, mushroomId, "mushroomId");
}

QString MushroomService::safetyWarning() const {
    return "⚠️ 蘑菇风险极高,仅作信息展示。本应用不推荐采食任何野生蘑菇。"
           "即使是有经验的人也可能误判。出现中毒症状请立即就医。";
}

// 2026-09-16: HSV 颜色距离 (与 InsectService 一致)
static double mushroomHsvDistance(const QVariantMap& a, const QVariantMap& b) {
    if (a.isEmpty() || b.isEmpty()) return 999.0;
    double h1 = a.value("h").toDouble();
    double s1 = a.value("s").toDouble();
    double v1 = a.value("v").toDouble();
    double h2 = b.value("h").toDouble();
    double s2 = b.value("s").toDouble();
    double v2 = b.value("v").toDouble();
    double dh = qAbs(h1 - h2);
    if (dh > 180) dh = 360 - dh;
    return std::sqrt(dh * dh * 0.5 + (s1-s2)*(s1-s2) + (v1-v2)*(v1-v2));
}

QVariantList MushroomService::matchByColor(const QVariantMap& userColor, int topK) {
    QVector<QPair<double, QString>> scored;
    for (const auto& e : m_index.mushrooms()) {
        if (e.representativeColor.isEmpty()) continue;
        double d = mushroomHsvDistance(userColor, e.representativeColor);
        scored.append({d, e.id});
    }
    std::sort(scored.begin(), scored.end());
    QVariantList list;
    for (int i = 0; i < std::min<long long>(topK, scored.size()); ++i) {
        QVariantMap m = getById(scored[i].second);
        if (!m.isEmpty()) {
            double sim = std::max(0.0, 100.0 - scored[i].first / 6.26);
            m["similarity"] = sim;
            list.append(m);
        }
    }
    return list;
}

} // namespace outdoor
