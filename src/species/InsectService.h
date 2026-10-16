/**
 * @file InsectService.h
 * @brief 昆虫/节肢图鉴服务(独立于动物)
 *
 * 涵盖:蜱虫/胡蜂/蚂蟥/红火蚁/蜈蚣/蝎子/隐翅虫/蚊等。
 * 2026-08-27 V2:从 SpeciesService 拆分。
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
 * @class InsectService
 * @brief 昆虫图鉴 — 30 种
 */
class InsectService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalCount READ totalCount NOTIFY dataChanged)
    Q_PROPERTY(int dangerousCount READ dangerousCount NOTIFY dataChanged)

public:
    explicit InsectService(Database* db, QObject* parent = nullptr);
    ~InsectService() override;

    bool loadInitialData();

    int totalCount() const;
    int dangerousCount() const;

    Q_INVOKABLE QVariantList getAll();
    Q_INVOKABLE QVariantMap getById(const QString& id);
    Q_INVOKABLE QVariantList search(const QString& keyword);

    Q_INVOKABLE QVariantList getByCategory(const QString& category);
    Q_INVOKABLE QVariantList getByProvince(const QString& province);
    Q_INVOKABLE QVariantList getByMonth(int month);
    // 2026-09-24: 补 - 省份+月份组合筛选 (与 Plant/Animal/Mushroom 对齐)
    Q_INVOKABLE QVariantList getByProvinceAndMonth(const QString& province, int month);
    Q_INVOKABLE QVariantList getDangerous(int minLevel = 4);

    Q_INVOKABLE QVariantList getAlongRoute(const QString& routeId, int month = 0);
    Q_INVOKABLE QVariantList getByFirstAid(const QString& firstAidId);

    // 2026-09-21: 阶段 L3.7 - recordLocation 切 Result<bool>
    Q_INVOKABLE QVariantMap recordLocation(const QString& insectId, double lat, double lon,
                                            const QString& note = QString());
    Q_INVOKABLE QVariantList getLocationsByInsect(const QString& insectId);

    Q_INVOKABLE QStringList getAvailableProvinces();

    // 2026-09-16: HSV 颜色粗筛 (FieldGuideImagePickPage 拍照检索)
    Q_INVOKABLE QVariantList matchByColor(const QVariantMap& userColor, int topK = 5);

signals:
    void dataChanged();

private:
    QVariantMap entityToMap(const FieldGuideEntity& e) const;

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    FieldGuideIndex m_index;
};

} // namespace outdoor
