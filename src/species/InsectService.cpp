/**
 * @file InsectService.cpp
 * @brief 昆虫图鉴实现
 */

#include "InsectService.h"
#include "SpeciesLocationOps.h"        // 2026-09-21 阶段 L4.2: 抽到 Ops
#include "../core/AssetLoader.h"
#include "../core/Logger.h"

#include <QSet>
#include <QVector>
#include <algorithm>

namespace outdoor {

InsectService::InsectService(Database* db, QObject* parent)
    
    : ServiceBase(db, "InsectService", parent) {
}

InsectService::~InsectService() {
}

bool InsectService::loadInitialData() {
    const QString dataDir = AssetLoader::assetRoot();
    m_index.loadAll(dataDir);
    emit dataChanged();
    if (m_index.insectCount() == 0) {
        Logger::warn(QString("InsectService: loaded 0 insects from %1").arg(dataDir));
    }
    return m_index.insectCount() > 0;
}

int InsectService::totalCount() const { return m_index.insectCount(); }

int InsectService::dangerousCount() const {
    int n = 0;
    for (const auto& e : m_index.insects()) if (e.dangerLevel >= 3) ++n;
    return n;
}

QVariantMap InsectService::entityToMap(const FieldGuideEntity& e) const {
    return FieldGuideIndex::toMap(e);
}

QVariantList InsectService::getAll() {
    QVariantList list;
    for (const auto& e : m_index.insects()) list.append(entityToMap(e));
    return list;
}

QVariantMap InsectService::getById(const QString& id) {
    const auto* e = m_index.getById(id);
    if (!e || e->kingdom != "insecta") return {};
    return entityToMap(*e);
}

QVariantList InsectService::search(const QString& keyword) {
    QVariantList list;
    for (const auto& e : m_index.insects()) {
        if (e.commonName.contains(keyword, Qt::CaseInsensitive) ||
            e.scientificName.contains(keyword, Qt::CaseInsensitive) ||
            e.alias.join(",").contains(keyword, Qt::CaseInsensitive)) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

QVariantList InsectService::getByCategory(const QString& category) {
    QVariantList list;
    for (const auto& e : m_index.insects()) {
        if (e.category == category) list.append(entityToMap(e));
    }
    return list;
}

QVariantList InsectService::getByProvince(const QString& province) {
    if (province.isEmpty() || province == "全部") return getAll();
    QVariantList list;
    for (const auto& e : m_index.insects()) {
        if (FieldGuideIndex::matchProvince(e.distribution, province)) list.append(entityToMap(e));
    }
    return list;
}

QVariantList InsectService::getByMonth(int month) {
    QVariantList list;
    // 2026-09-14: month=0 表示"全部月份", 跳过月份过滤
    if (month == 0) {
        for (const auto& e : m_index.insects()) list.append(entityToMap(e));
        return list;
    }
    QString m = QString::number(month);
    for (const auto& e : m_index.insects()) {
        if (e.activeMonths.contains(m)) list.append(entityToMap(e));
    }
    return list;
}

// 2026-09-24: 补 - FieldGuidePage 省份+月份组合筛选调用此方法, 之前昆虫无此方法,
//   ServiceListModel 报 "method not found" → 列表空.
QVariantList InsectService::getByProvinceAndMonth(const QString& province, int month) {
    QVariantList list;
    QString m = (month >= 1 && month <= 12) ? QString::number(month) : QString();
    for (const auto& e : m_index.insects()) {
        bool prov = FieldGuideIndex::matchProvince(e.distribution, province);
        bool mon = m.isEmpty() || e.activeMonths.contains(m);
        if (prov && mon) list.append(entityToMap(e));
    }
    return list;
}

QVariantList InsectService::getDangerous(int minLevel) {
    QVariantList list;
    for (const auto& e : m_index.insects()) {
        if (e.dangerLevel >= minLevel) list.append(entityToMap(e));
    }
    return list;
}

QVariantList InsectService::getAlongRoute(const QString& routeId, int month) {
    QVariantList list;
    QString m = QString::number(month);
    for (const auto& e : m_index.insects()) {
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

QVariantList InsectService::getByFirstAid(const QString& firstAidId) {
    QVariantList list;
    for (const auto& e : m_index.insects()) {
        if (e.firstAidId == firstAidId || e.firstAidLinks.values().contains(firstAidId)) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

// 2026-09-21 阶段 L4.2: 抽到 SpeciesLocationOps
QVariantMap InsectService::recordLocation(const QString& insectId, double lat, double lon,
                                            const QString& note) {
    return SpeciesLocationOps::recordLocation(
        m_db, SpeciesLocationRepository::Kind::Insect, insectId, lat, lon, note);
}

QVariantList InsectService::getLocationsByInsect(const QString& insectId) {
    return SpeciesLocationOps::listByEntity(
        m_db, SpeciesLocationRepository::Kind::Insect, insectId, "insectId");
}

QStringList InsectService::getAvailableProvinces() {
    // 2026-09-24: 改用归一化 (原始 distribution 是自由文本 "山东(沿海)"/"河南(局部)"),
    //   直接暴露给下拉框会出现长尾脏项且与 matchProvince 不一致.
    QStringList all;
    for (const auto& e : m_index.insects()) {
        for (const auto& p : e.distribution) all.append(p);
    }
    return FieldGuideIndex::canonicalProvinces(all);
}

// 2026-09-16: HSV 颜色距离 (简化版, 与 PlantService 一致)
static double insectHsvDistance(const QVariantMap& a, const QVariantMap& b) {
    if (a.isEmpty() || b.isEmpty()) return 999.0;
    double h1 = a.value("h").toDouble();
    double s1 = a.value("s").toDouble();
    double v1 = a.value("v").toDouble();
    double h2 = b.value("h").toDouble();
    double s2 = b.value("s").toDouble();
    double v2 = b.value("v").toDouble();
    double dh = qAbs(h1 - h2);
    if (dh > 180) dh = 360 - dh;
    double ds = s1 - s2;
    double dv = v1 - v2;
    return std::sqrt(dh * dh * 0.5 + ds * ds + dv * dv);
}

QVariantList InsectService::matchByColor(const QVariantMap& userColor, int topK) {
    QVector<QPair<double, QString>> scored;
    for (const auto& e : m_index.insects()) {
        if (e.representativeColor.isEmpty()) continue;
        double d = insectHsvDistance(userColor, e.representativeColor);
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
