/**
 * @file PlantService.cpp
 * @brief 植物图鉴服务实现
 */

#include "PlantService.h"
#include "SpeciesLocationOps.h"        // 2026-09-21 阶段 L4.2: 抽到 Ops
#include "../core/AssetLoader.h"
#include "../core/Logger.h"

#include <QSet>
#include <QVector>
#include <algorithm>
#include <cmath>

namespace outdoor {

namespace {

double hsvDistance(const QVariantMap& a, const QVariantMap& b) {
    int h1 = a.value("h").toInt();
    int s1 = a.value("s").toInt();
    int v1 = a.value("v").toInt();
    int h2 = b.value("h").toInt();
    int s2 = b.value("s").toInt();
    int v2 = b.value("v").toInt();
    // 色相圆周距离
    int dh = std::min(std::abs(h1 - h2), 360 - std::abs(h1 - h2));
    int ds = s1 - s2;
    int dv = v1 - v2;
    return std::sqrt(double(dh * dh + ds * ds + dv * dv));
}

} // namespace

PlantService::PlantService(Database* db, QObject* parent)
    
    : ServiceBase(db, "PlantService", parent) {
}

PlantService::~PlantService() {
}

bool PlantService::loadInitialData() {
    // 之前 applicationDirPath() 候选在 Android 永远失败 (返回 /data/app/.../lib/),
    // 实际只有 qrc 路径生效. 这里直接传 AssetLoader 的根目录给 FieldGuideIndex.
    // 排查日志: 任何 0 加载问题看 PlantService loaded count log.
    const QString dataDir = AssetLoader::assetRoot();
    m_index.loadAll(dataDir);
    emit dataChanged();
    if (m_index.plantCount() == 0) {
        Logger::warn(QString("PlantService: loaded 0 plants from %1").arg(dataDir));
    }
    return m_index.plantCount() > 0;
}

int PlantService::totalCount() const { return m_index.plantCount(); }

int PlantService::edibleCount() const {
    int n = 0;
    for (const auto& e : m_index.plants()) {
        if (!e.ediblePart.isEmpty()) ++n;
    }
    return n;
}

int PlantService::poisonousCount() const {
    int n = 0;
    for (const auto& e : m_index.plants()) {
        if (e.dangerLevel >= 3 && e.category == "poisonous") ++n;
    }
    return n;
}

int PlantService::medicinalCount() const {
    int n = 0;
    for (const auto& e : m_index.plants()) {
        if (e.category == "medicinal") ++n;
    }
    return n;
}

QVariantMap PlantService::entityToMap(const FieldGuideEntity& e) const {
    return FieldGuideIndex::toMap(e);
}

QList<FieldGuideEntity> PlantService::filterEntities(
    const std::function<bool(const FieldGuideEntity&)>& pred) const {
    QList<FieldGuideEntity> r;
    for (const auto& e : m_index.plants()) {
        if (pred(e)) r.append(e);
    }
    return r;
}

QVariantList PlantService::getAll() {
    QVariantList list;
    for (const auto& e : m_index.plants()) list.append(entityToMap(e));
    return list;
}

QVariantMap PlantService::getById(const QString& id) {
    const auto* e = m_index.getById(id);
    if (!e || e->kingdom != "plantae") return {};
    return entityToMap(*e);
}

QVariantList PlantService::search(const QString& keyword) {
    if (keyword.isEmpty()) return getAll();
    QVariantList list;
    for (const auto& e : m_index.plants()) {
        if (e.commonName.contains(keyword, Qt::CaseInsensitive) ||
            e.scientificName.contains(keyword, Qt::CaseInsensitive) ||
            e.alias.join(",").contains(keyword, Qt::CaseInsensitive)) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

QVariantList PlantService::getByCategory(const QString& category) {
    QVariantList list;
    for (const auto& e : m_index.plants()) {
        if (e.category == category) list.append(entityToMap(e));
    }
    return list;
}

QVariantList PlantService::getEdible(int month) {
    QVariantList list;
    for (const auto& e : m_index.plants()) {
        if (e.ediblePart.isEmpty()) continue;
        if (month > 0 && !e.edibleMonths.contains(QString::number(month))) continue;
        list.append(entityToMap(e));
    }
    return list;
}

QVariantList PlantService::getPoisonous() {
    QVariantList list;
    for (const auto& e : m_index.plants()) {
        if (e.category == "poisonous" || e.dangerLevel >= 3) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

QVariantList PlantService::getMedicinal() {
    return getByCategory("medicinal");
}

QVariantList PlantService::getDangerous(int minLevel) {
    QVariantList list;
    for (const auto& e : m_index.plants()) {
        if (e.dangerLevel >= minLevel) list.append(entityToMap(e));
    }
    return list;
}

QVariantList PlantService::getByProvince(const QString& province) {
    if (province.isEmpty() || province == "全部") return getAll();
    QVariantList list;
    for (const auto& e : m_index.plants()) {
        if (FieldGuideIndex::matchProvince(e.distribution, province)) list.append(entityToMap(e));
    }
    return list;
}

QVariantList PlantService::getByMonth(int month) {
    QVariantList list;
    // 2026-09-14: month=0 表示"全部月份", 跳过月份过滤 (修"山东动物月份全部 0 条" bug)
    if (month == 0) {
        for (const auto& e : m_index.plants()) list.append(entityToMap(e));
        return list;
    }
    QString m = QString::number(month);
    for (const auto& e : m_index.plants()) {
        if (e.activeMonths.contains(m) || e.edibleMonths.contains(m)) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

QVariantList PlantService::getByProvinceAndMonth(const QString& province, int month) {
    QVariantList list;
    // 2026-09-14: month=0 表示"全部月份", 跳过月份过滤
    QString m = (month >= 1 && month <= 12) ? QString::number(month) : QString();
    for (const auto& e : m_index.plants()) {
        bool prov = FieldGuideIndex::matchProvince(e.distribution, province);
        bool mon = m.isEmpty() || e.activeMonths.contains(m) || e.edibleMonths.contains(m);
        if (prov && mon) list.append(entityToMap(e));
    }
    return list;
}

QStringList PlantService::getAvailableProvinces() {
    // 2026-09-24: 改用归一化 (原始 distribution 是自由文本 "山东(鲁中)"/"北方多" 等)
    QStringList all;
    for (const auto& e : m_index.plants()) {
        for (const auto& p : e.distribution) all.append(p);
    }
    return FieldGuideIndex::canonicalProvinces(all);
}

QStringList PlantService::getAvailableCategories() {
    QSet<QString> set;
    for (const auto& e : m_index.plants()) set.insert(e.category);
    QStringList list = set.values();
    std::sort(list.begin(), list.end());
    return list;
}

QVariantList PlantService::getAlongRoute(const QString& routeId, int month) {
    QVariantList list;
    QString m = QString::number(month);
    for (const auto& e : m_index.plants()) {
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

QVariantList PlantService::getLookAlike(const QString& id) {
    QVariantList list;
    const auto* e = m_index.getById(id);
    if (!e) return list;
    for (const auto& item : e->lookAlike) {
        const auto* other = item.id.isEmpty() ? nullptr : m_index.getById(item.id);
        QVariantMap m = other ? entityToMap(*other) : QVariantMap();
        // 2026-10-08: 无 id(外部提及)或 id 悬空时, 用 JSON 原文兜底, 保留 name/distinction/fatality
        m["id"] = item.id;
        if (m.value("commonName").toString().isEmpty()) m["commonName"] = item.name;
        m["name"] = item.name;
        m["distinction"] = item.distinction;
        m["fatality"] = item.fatality;
        list.append(m);
    }
    return list;
}

QVariantList PlantService::getByFirstAid(const QString& firstAidId) {
    QVariantList list;
    for (const auto& e : m_index.plants()) {
        if (e.firstAidId == firstAidId ||
            e.firstAidLinks.contains(firstAidId) ||
            e.firstAidLinks.values().contains(firstAidId)) {
            list.append(entityToMap(e));
        }
    }
    return list;
}

// 2026-09-21 阶段 L4.2: 抽到 SpeciesLocationOps
QVariantMap PlantService::recordLocation(const QString& plantId, double lat, double lon,
                                           const QString& note) {
    return SpeciesLocationOps::recordLocation(
        m_db, SpeciesLocationRepository::Kind::Plant, plantId, lat, lon, note);
}

QVariantList PlantService::getLocationsByPlant(const QString& plantId) {
    return SpeciesLocationOps::listByEntity(
        m_db, SpeciesLocationRepository::Kind::Plant, plantId, "plantId");
}

QVariantList PlantService::getLocationsNear(double lat, double lon, double radiusKm) {
    Q_UNUSED(radiusKm);
    return SpeciesLocationOps::listNear(
        m_db, SpeciesLocationRepository::Kind::Plant, lat, lon);
}

QVariantList PlantService::matchByColor(const QVariantMap& userColor, int topK) {
    QVector<QPair<double, QString>> scored;
    for (const auto& e : m_index.plants()) {
        if (e.representativeColor.isEmpty()) continue;
        double d = hsvDistance(userColor, e.representativeColor);
        scored.append({d, e.id});
    }
    std::sort(scored.begin(), scored.end());

    QVariantList list;
    for (int i = 0; i < std::min<long long>(topK, scored.size()); ++i) {
        QVariantMap m = getById(scored[i].second);
        if (!m.isEmpty()) {
            // 相似度 0-100,距离越接近 0 越相似,HSV 距离最大 ~626
            double sim = std::max(0.0, 100.0 - scored[i].first / 6.26);
            m["similarity"] = sim;
            list.append(m);
        }
    }
    return list;
}

} // namespace outdoor
