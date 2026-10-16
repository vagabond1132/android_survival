/**
 * @file ChecklistService.h
 * @brief 应急储备清单服务
 */

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QList>
#include <QHash>
#include <QDateTime>
#include <QJsonObject>
#include <QJsonValue>
#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2

namespace outdoor {

class ChecklistService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalChecklists READ totalChecklists NOTIFY dataChanged)
    Q_PROPERTY(int totalTemplates READ totalTemplates NOTIFY dataChanged)

public:
    struct Item {
        QString id;
        QString name;
        QString category;
        int quantity = 1;
        double weightG = 0;
        bool required = false;
        bool checked = false;
        QString note;
        QStringList alternatives;
    };

    struct Checklist {
        QString id;
        QString name;
        QString scenario;        // 场景
        QString description;
        bool isTemplate = false;
        QList<Item> items;
        double totalWeightG = 0;
        int totalCount = 0;
        int checkedCount = 0;
        QDateTime updatedAt;
    };

    explicit ChecklistService(Database* db, QObject* parent = nullptr);
    ~ChecklistService() override;

    bool loadInitialData();

    int totalChecklists() const;
    int totalTemplates() const;

    // 模板
    Q_INVOKABLE QVariantList getTemplates();
    Q_INVOKABLE QVariantMap getTemplate(const QString& scenario);

    // 自定义清单
    // 2026-09-21: Phase 5 - createCustom 返回 Result {ok, value=id, error}
    Q_INVOKABLE QVariantMap createCustom(const QString& name);
    Q_INVOKABLE QVariantList getCustomLists();
    Q_INVOKABLE QVariantMap getById(const QString& id);  // 2026-09-20: rename from getChecklist (Phase 4 命名统一)
    // 2026-09-21: 阶段 L3.3 - saveChecklist/deleteChecklist 写操作切 Result
    Q_INVOKABLE QVariantMap saveChecklist(const Checklist& list);
    Q_INVOKABLE QVariantMap deleteChecklist(const QString& id);

    // 项目操作
    // 2026-09-21: Phase 5 - 写操作切 Result
    Q_INVOKABLE QVariantMap setItemChecked(const QString& checklistId,
                                            const QString& itemId, bool checked);
    // 2026-09-21: 阶段 L3.3 - setItemQuantity/addItem/deleteItem 切 Result
    Q_INVOKABLE QVariantMap setItemQuantity(const QString& checklistId,
                                             const QString& itemId, int qty);
    Q_INVOKABLE QVariantMap addItem(const QString& checklistId, const Item& item);
    Q_INVOKABLE QVariantMap deleteItem(const QString& checklistId, const QString& itemId);

    // 导出
    Q_INVOKABLE QString exportToText(const QString& checklistId);
    Q_INVOKABLE QJsonObject exportToJson(const QString& checklistId);
    // 2026-09-21: 阶段 L3.3 - importFromJson 切 Result
    Q_INVOKABLE QVariantMap importFromJson(const QJsonObject& json);

    // 统计
    Q_INVOKABLE double getTotalWeight(const QString& checklistId);
    Q_INVOKABLE int getCheckedCount(const QString& checklistId);

signals:
    void dataChanged();
    void checklistChanged(const QString& id);
    void itemChanged(const QString& checklistId, const QString& itemId);

private:
    bool ensureSchema();
    bool loadTemplates();
    void saveChecklistItems(const QString& checklistId, const QList<Item>& items);
    QList<Item> loadChecklistItems(const QString& checklistId);
    void recomputeStats(Checklist& list);

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    QHash<QString, Checklist> m_checklists;
    int m_templateCount = 0;
};

} // namespace outdoor
