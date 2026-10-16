/**
 * @file PlantService.h
 * @brief 植物图鉴服务
 *
 * 2026-08-27 V2:从 SpeciesService 拆分。可食野菜/野果/药用/毒/观赏。
 */

#pragma once

#include "FieldGuideIndex.h"

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2

namespace outdoor {

/**
 * @class PlantService
 * @brief 植物图鉴 — 鲁晋冀豫 220 种
 */
class PlantService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalCount READ totalCount NOTIFY dataChanged)
    Q_PROPERTY(int edibleCount READ edibleCount NOTIFY dataChanged)
    Q_PROPERTY(int poisonousCount READ poisonousCount NOTIFY dataChanged)
    Q_PROPERTY(int medicinalCount READ medicinalCount NOTIFY dataChanged)

public:
    explicit PlantService(Database* db, QObject* parent = nullptr);
    ~PlantService() override;

    bool loadInitialData();

    int totalCount() const;
    int edibleCount() const;
    int poisonousCount() const;
    int medicinalCount() const;

    Q_INVOKABLE QVariantList getAll();
    Q_INVOKABLE QVariantMap getById(const QString& id);
    Q_INVOKABLE QVariantList search(const QString& keyword);

    Q_INVOKABLE QVariantList getByCategory(const QString& category);
    Q_INVOKABLE QVariantList getEdible(int month = 0);
    Q_INVOKABLE QVariantList getPoisonous();
    Q_INVOKABLE QVariantList getMedicinal();
    Q_INVOKABLE QVariantList getDangerous(int minLevel = 4);

    Q_INVOKABLE QVariantList getByProvince(const QString& province);
    Q_INVOKABLE QVariantList getByMonth(int month);
    Q_INVOKABLE QVariantList getByProvinceAndMonth(const QString& province, int month);
    Q_INVOKABLE QStringList getAvailableProvinces();
    Q_INVOKABLE QStringList getAvailableCategories();

    Q_INVOKABLE QVariantList getAlongRoute(const QString& routeId, int month = 0);
    Q_INVOKABLE QVariantList getLookAlike(const QString& id);
    Q_INVOKABLE QVariantList getByFirstAid(const QString& firstAidId);

    // 2026-09-21: 阶段 L3.7 - recordLocation 切 Result<bool>
    Q_INVOKABLE QVariantMap recordLocation(const QString& plantId, double lat, double lon,
                                            const QString& note = QString());
    Q_INVOKABLE QVariantList getLocationsByPlant(const QString& plantId);
    Q_INVOKABLE QVariantList getLocationsNear(double lat, double lon, double radiusKm);

    Q_INVOKABLE QVariantList matchByColor(const QVariantMap& userColor, int topK = 5);

signals:
    void dataChanged();

private:
    QVariantMap entityToMap(const FieldGuideEntity& e) const;
    QList<FieldGuideEntity> filterEntities(
        const std::function<bool(const FieldGuideEntity&)>& pred) const;

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    FieldGuideIndex m_index;
};

} // namespace outdoor
