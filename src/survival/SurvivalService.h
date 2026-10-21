/**
 * @file SurvivalService.h
 * @brief 避险服务 - 取火、庇护所、工具、净水
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
 * @class SurvivalService
 * @brief 户外生存技能服务
 */
class SurvivalService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int fireMethodsCount READ fireMethodsCount NOTIFY dataChanged)
    Q_PROPERTY(int shelterCount READ shelterCount NOTIFY dataChanged)
    Q_PROPERTY(int toolCount READ toolCount NOTIFY dataChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY dataChanged)

public:
    enum class Topic {
        Fire = 0,        // 取火
        Shelter = 1,     // 庇护所
        Water = 2,       // 净水
        Food = 3,        // 食物
        Signaling = 4,   // 求救信号
        Navigation = 5,  // 导航定向
        Weather = 6,     // 天气
        Tools = 7        // 工具
    };
    Q_ENUM(Topic)

    struct Item {
        QString id;
        QString name;
        Topic topic;
        QString category;
        int difficulty;
        QString description;
        QStringList materials;
        int estimatedTimeMin;
        QStringList steps;
        QStringList warnings;
        QStringList tips;
        QString videoUrl;
        QString source;
    };

    explicit SurvivalService(Database* db, QObject* parent = nullptr);
    ~SurvivalService() override;

    bool loadInitialData();

    int fireMethodsCount() const;
    int shelterCount() const;
    int toolCount() const;
    int totalCount() const;

    // 查询
    Q_INVOKABLE QVariantList getByTopic(Topic topic);
    Q_INVOKABLE QVariantList getByDifficulty(int maxDifficulty = 5);
    Q_INVOKABLE QVariantMap getById(const QString& id);
    Q_INVOKABLE QVariantList search(const QString& keyword);

    // 分类标签
    Q_INVOKABLE QStringList getCategories(Topic topic);

signals:
    void dataChanged();

private:
    bool loadFromJson();
    bool ensureSchema();

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    QHash<QString, Item> m_items;
};

} // namespace outdoor
