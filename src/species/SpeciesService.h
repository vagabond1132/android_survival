/**
 * @file SpeciesService.h
 * @brief 危险物种服务 - 中国危险动植物查询
 */

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QList>
#include <QHash>
#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2

namespace outdoor {

/**
 * @class SpeciesService
 * @brief 危险物种服务（P0 核心）
 *
 * 提供：
 * - 10 大剧毒蛇详细数据
 * - 10 大致命蘑菇警示
 * - 10 大毒植物警示
 * - 5 大毒虫信息
 * - 物种急救关联
 */
class SpeciesService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalCount READ totalCount NOTIFY dataChanged)
    Q_PROPERTY(int dangerousCount READ dangerousCount NOTIFY dataChanged)

public:
    enum class Category {
        Snake = 0,
        Mushroom = 1,
        Insect = 2,
        Plant = 3,
        Animal = 4
    };
    Q_ENUM(Category)

    /**
     * @struct SpeciesInfo
     * @brief 物种信息
     */
    struct SpeciesInfo {
        QString id;
        QString commonName;
        QString scientificName;
        Category category;
        int dangerLevel;          // 0-5
        QStringList alias;
        QStringList features;     // 识别特征
        QStringList distribution; // 省份
        int minElevation;
        int maxElevation;
        QStringList habitats;
        QStringList activeMonths;
        QStringList symptoms;     // 中毒症状
        QString firstAidId;       // 关联急救条目
        QStringList protectiveGear;
        QStringList photos;       // 照片路径
        QString description;
        QString source;
        QString reviewer;
    };

    explicit SpeciesService(Database* db, QObject* parent = nullptr);
    ~SpeciesService() override;

    bool loadInitialData();

    int totalCount() const;
    int dangerousCount() const;

    // 查询
    Q_INVOKABLE QVariantList getAll();
    Q_INVOKABLE QVariantList getByCategory(Category cat);
    Q_INVOKABLE QVariantList getDangerous(int minLevel = 3);
    Q_INVOKABLE QVariantMap getById(const QString& id);
    Q_INVOKABLE QVariantList search(const QString& keyword);

    // 区域相关
    Q_INVOKABLE QVariantList getForRegion(const QString& province);

    // 急救联动
    Q_INVOKABLE QString getFirstAidId(const QString& speciesId);

signals:
    void dataChanged();

private:
    bool loadFromJson();
    bool ensureSchema();

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    QHash<QString, SpeciesInfo> m_species;
};

} // namespace outdoor
