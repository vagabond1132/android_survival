/**
 * @file KnotService.h
 * @brief 绳结学习服务
 */

#pragma once

#include <QObject>
#include <QString>
#include <QList>
#include <QHash>
#include <QSet>
#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2

namespace outdoor {

class KnotService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalCount READ totalCount NOTIFY dataChanged)
    Q_PROPERTY(int learnedCount READ learnedCount NOTIFY progressChanged)

public:
    struct Knot {
        QString id;
        QString nameCn;
        QString nameEn;
        QString category;
        int difficulty;
        QStringList useCases;
        QString description;
        QStringList steps;
        QStringList commonMistakes;
        QStringList related;
        QString videoUrl;
        QString animationUrl;
        QString practiceTip;
    };

    struct Step {
        int index;
        QString text;
        QString imagePath;
        QString videoTime;
    };

    explicit KnotService(Database* db, QObject* parent = nullptr);
    ~KnotService() override;

    bool loadInitialData();

    int totalCount() const;
    int learnedCount() const;

    Q_INVOKABLE QVariantList getAll();
    Q_INVOKABLE QVariantList getByCategory(const QString& category);
    Q_INVOKABLE QVariantList getByDifficulty(int difficulty);
    Q_INVOKABLE QVariantMap getById(const QString& id);
    Q_INVOKABLE QVariantList search(const QString& keyword);
    // 2026-09-21: Phase 5 批次 3 - getLearningPath 返回 Result (KnotPage 主列表)
    Q_INVOKABLE QVariantMap getLearningPath();

    // 学习进度
    // 2026-09-21: 阶段 L3.2 - 写操作切 Result. markLearned/resetProgress 返回 QVariantMap.
    Q_INVOKABLE QVariantMap markLearned(const QString& id);
    Q_INVOKABLE bool isLearned(const QString& id);  // 谓词保留 bool
    Q_INVOKABLE QVariantMap resetProgress();
    Q_INVOKABLE QVariantList getLearnedList();

    QStringList getCategories() const;

signals:
    void dataChanged();
    void progressChanged();

private:
    bool loadFromJson();
    bool ensureSchema();

    // 2026-09-21 阶段 L2: m_db 字段上移到 ServiceBase
    QHash<QString, Knot> m_knots;
    QSet<QString> m_learned;
};

} // namespace outdoor
