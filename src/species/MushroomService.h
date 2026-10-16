/**
 * @file MushroomService.h
 * @brief 蘑菇图鉴服务(独立)
 *
 * 2026-08-27 V2:从 SpeciesService 拆分。菌物界独立。
 * 蘑菇风险极高:此服务只展示信息,不参与"拍照识别"。
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
 * @class MushroomService
 * @brief 蘑菇图鉴 — 30 种(致命 5 + 常见毒 10 + 易混可食 10 + 其他 5)
 */
class MushroomService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalCount READ totalCount NOTIFY dataChanged)
    Q_PROPERTY(int deadlyCount READ deadlyCount NOTIFY dataChanged)
    Q_PROPERTY(int edibleCount READ edibleCount NOTIFY dataChanged)

public:
    explicit MushroomService(Database* db, QObject* parent = nullptr);
    ~MushroomService() override;

    bool loadInitialData();

    int totalCount() const;
    int deadlyCount() const;     // 致命级(5 级)
    int edibleCount() const;     // 可食

    Q_INVOKABLE QVariantList getAll();
    Q_INVOKABLE QVariantMap getById(const QString& id);
    Q_INVOKABLE QVariantList search(const QString& keyword);

    Q_INVOKABLE QVariantList getByCategory(const QString& category);  // deadly_mushroom/edible_mushroom/common_mushroom
    Q_INVOKABLE QVariantList getDeadly();
    Q_INVOKABLE QVariantList getEdible();
    Q_INVOKABLE QVariantList getByProvince(const QString& province);
    Q_INVOKABLE QVariantList getByMonth(int month);
    // 2026-09-24: 补 - 省份+月份组合筛选 (与 Plant/Animal/Insect 对齐)
    Q_INVOKABLE QVariantList getByProvinceAndMonth(const QString& province, int month);
    Q_INVOKABLE QStringList getAvailableProvinces();

    // 2026-09-16: HSV 颜色粗筛 (用户需求: 拍照识别蘑菇)
    Q_INVOKABLE QVariantList matchByColor(const QVariantMap& userColor, int topK = 5);

    Q_INVOKABLE QVariantList getLookAlike(const QString& id);
    Q_INVOKABLE QVariantList getByFirstAid(const QString& firstAidId);
    Q_INVOKABLE QVariantList getAlongRoute(const QString& routeId, int month = 0);

    // 2026-09-21: 阶段 L3.7 - recordLocation 切 Result<bool>
    Q_INVOKABLE QVariantMap recordLocation(const QString& mushroomId, double lat, double lon,
                                            const QString& note = QString());
    Q_INVOKABLE QVariantList getLocationsByMushroom(const QString& mushroomId);

    // 安全警告:始终返回致命警告文案
    Q_INVOKABLE QString safetyWarning() const;

signals:
    void dataChanged();

private:
    QVariantMap entityToMap(const FieldGuideEntity& e) const;

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    FieldGuideIndex m_index;
};

} // namespace outdoor
