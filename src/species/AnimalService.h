/**
 * @file AnimalService.h
 * @brief 动物图鉴服务(蛇/兽/鸟/两栖,不含昆虫)
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
 * @class AnimalService
 * @brief 动物图鉴 — 鲁晋冀豫 120 种
 */
class AnimalService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalCount READ totalCount NOTIFY dataChanged)
    Q_PROPERTY(int snakeCount READ snakeCount NOTIFY dataChanged)
    Q_PROPERTY(int dangerousCount READ dangerousCount NOTIFY dataChanged)

public:
    explicit AnimalService(Database* db, QObject* parent = nullptr);
    ~AnimalService() override;

    bool loadInitialData();

    int totalCount() const;
    int snakeCount() const;
    int dangerousCount() const;

    Q_INVOKABLE QVariantList getAll();
    Q_INVOKABLE QVariantMap getById(const QString& id);
    Q_INVOKABLE QVariantList search(const QString& keyword);

    Q_INVOKABLE QVariantList getSnakes(bool venomousOnly = false);
    Q_INVOKABLE QVariantList getMammals();
    Q_INVOKABLE QVariantList getDangerous(int minLevel = 4);
    Q_INVOKABLE QVariantList getByCategory(const QString& category);

    Q_INVOKABLE QVariantList getByProvince(const QString& province);
    Q_INVOKABLE QVariantList getByMonth(int month);
    Q_INVOKABLE QVariantList getByProvinceAndMonth(const QString& province, int month);
    Q_INVOKABLE QStringList getAvailableProvinces();

    Q_INVOKABLE QVariantList getAlongRoute(const QString& routeId, int month = 0);
    Q_INVOKABLE QVariantList getLookAlike(const QString& id);
    Q_INVOKABLE QVariantList getByFirstAid(const QString& firstAidId);

    // 2026-09-21: 阶段 L3.7 - recordLocation 切 Result<bool>
    Q_INVOKABLE QVariantMap recordLocation(const QString& animalId, double lat, double lon,
                                            const QString& note = QString());
    Q_INVOKABLE QVariantList getLocationsByAnimal(const QString& animalId);
    Q_INVOKABLE QVariantList getLocationsNear(double lat, double lon, double radiusKm);

    Q_INVOKABLE QVariantList matchByColor(const QVariantMap& userColor, int topK = 5);

signals:
    void dataChanged();

private:
    QVariantMap entityToMap(const FieldGuideEntity& e) const;

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    FieldGuideIndex m_index;
};

} // namespace outdoor
