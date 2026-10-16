/**
 * @file FirstAidService.h
 * @brief 急救服务 - 急救条目查询、决策树、急救包管理
 */

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QList>
#include <QDateTime>
#include <QJsonObject>
#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2

namespace outdoor {

/**
 * @class FirstAidService
 * @brief 急救服务（核心救命模块）
 *
 * 提供：
 * - 急救条目查询（按类别、紧急度、症状）
 * - 决策树引导
 * - 急救包配置模板
 * - 急救知识学习
 *
 * @note 重要：本服务内容必须经执业医师审核后才可上线
 */
class FirstAidService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalEntries READ totalEntries NOTIFY dataChanged)
    Q_PROPERTY(int criticalCount READ criticalCount NOTIFY dataChanged)

public:
    /**
     * @enum Urgency
     * @brief 紧急程度
     *
     * 2026-09-19: 重命名 Critical → Crisis, 避免与 Category::Critical
     *   同名在 Qt MOC 注册时 clash (日志: "Previously registered enum
     *   will be overwritten due to name clash: FirstAidService.Critical").
     *   语义上 危急 = Crisis 更准确, 数值不变 (5), 不破坏 QML 端 numeric 比较.
     */
    enum class Urgency {
        Info = 1,         // 知识
        Low = 2,          // 低
        Medium = 3,       // 中
        High = 4,         // 高
        Crisis = 5        // 危急 (原 Critical, 改名避免与 Category::Critical 冲突)
    };
    Q_ENUM(Urgency)

    /**
     * @enum Category
     * @brief 急救分类
     */
    enum class Category {
        Critical,    // 急症优先 (MOC 注册名, 保持不变)
        Trauma,      // 创伤
        Environment, // 环境
        Poison,      // 中毒
        Emergency    // 应急功能
    };
    Q_ENUM(Category)

    /**
     * @struct Entry
     * @brief 急救条目
     */
    struct Entry {
        QString id;
        QString title;
        Category category;
        Urgency urgency;
        QStringList symptoms;
        QString description;
        QStringList criticalActions;
        QStringList steps;
        QStringList donts;
        QStringList relatedSpecies;
        QString videoUrl;
        QString source;
        QString reviewer;        // 审核医师
        QDateTime lastReviewed;
    };

    /**
     * @struct DecisionNode
     * @brief 决策树节点
     */
    struct DecisionNode {
        QString id;
        QString question;
        QString text;
        QStringList options;          // 选项
        QMap<QString, QString> nextNodes;  // option -> nextNodeId
        QString terminalAction;       // 终止动作（叶节点）
    };

    explicit FirstAidService(Database* db, QObject* parent = nullptr);
    ~FirstAidService() override;

    // 初始化
    bool loadInitialData();

    // 总数
    int totalEntries() const;
    int criticalCount() const;

    // 查询
    // 2026-09-21: Phase 5 批次 3 - getAllEntries 返回 Result (FirstAidPage 主列表)
    Q_INVOKABLE QVariantMap getAllEntries();
    Q_INVOKABLE QVariantList getByCategory(Category cat);
    Q_INVOKABLE QVariantList getByUrgency(Urgency urgency);
    Q_INVOKABLE QVariantList getCritical();  // 紧急
    Q_INVOKABLE QVariantMap getById(const QString& id);
    Q_INVOKABLE QVariantList search(const QString& keyword);

    // 决策树
    Q_INVOKABLE QVariantMap getDecisionRoot(const QString& entryId);
    Q_INVOKABLE QVariantMap getDecisionNode(const QString& nodeId);
    Q_INVOKABLE QVariantList getDecisionPath(const QString& entryId,
                                                const QStringList& choices);

    // 急救包
    Q_INVOKABLE QVariantList getKitTemplates();
    Q_INVOKABLE QVariantMap getKitTemplate(const QString& scenario);

    // 关联物种
    Q_INVOKABLE QStringList getRelatedSpecies(const QString& entryId);

signals:
    void dataChanged();
    void criticalWarning(QString entryId, QString title);
    void decisionNodeChanged(QString nodeId);

private:
    bool loadFromJson();
    bool ensureSchema();

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    QHash<QString, Entry> m_entries;       // id -> entry
    QHash<QString, DecisionNode> m_decisionNodes;  // nodeId -> node
    QHash<QString, QString> m_entryRoots;  // entryId -> rootNodeId
    QHash<QString, QJsonObject> m_kitTemplates;  // scenario -> kit
};

} // namespace outdoor
