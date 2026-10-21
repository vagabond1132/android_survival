/**
 * @file FieldGuideHistory.h
 * @brief 图鉴浏览历史(植物/动物/昆虫/蘑菇)
 *
 * 替代原 RecognitionStorage,语义从"AI 识别历史"改为"图鉴浏览历史"。
 * 命名: 历史记录条目,用户可收藏/加笔记/按类别筛选。
 * 向后兼容: 旧 RecognitionRecord 字段映射到新 ViewRecord。
 */

#pragma once

#include <QObject>
#include <QString>
#include <QList>
#include <QDateTime>
#include <QGeoCoordinate>
#include <QSqlQuery>
#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2

namespace outdoor {

/**
 * @enum FieldGuideKingdom
 * @brief 4 大生物界
 */
enum class FieldGuideKingdom {
    Plantae = 0,    // 植物
    Animalia = 1,   // 动物
    Insecta = 2,    // 昆虫(节肢)
    Fungi = 3       // 蘑菇(菌物)
};

/**
 * @struct ViewRecord
 * @brief 图鉴浏览记录
 */
struct ViewRecord {
    qint64 id = 0;
    QString entityId;          // 物种 ID
    QString kingdom;           // plantae/animalia/insecta/fungi
    QString commonName;        // 冗余存储,加速列表
    QString scientificName;
    QString category;          // 子分类(可食/毒/伤人 等)
    int dangerLevel = 0;       // 0-5
    QString viewSource;        // search/route/firstaid/map/manual
    QString routeId;           // 触发场景:哪条路线
    QString firstAidId;        // 触发场景:哪个急救动作
    QGeoCoordinate location;   // 触发场景:地图位置
    QString note;              // 用户笔记
    bool isFavorite = false;
    QDateTime viewedAt;
};

/**
 * @class FieldGuideHistory
 * @brief 图鉴浏览历史管理
 */
class FieldGuideHistory : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalCount READ totalCount NOTIFY dataChanged)
    Q_PROPERTY(int plantCount READ plantCount NOTIFY dataChanged)
    Q_PROPERTY(int animalCount READ animalCount NOTIFY dataChanged)
    Q_PROPERTY(int insectCount READ insectCount NOTIFY dataChanged)
    Q_PROPERTY(int mushroomCount READ mushroomCount NOTIFY dataChanged)

public:
    explicit FieldGuideHistory(Database* db, QObject* parent = nullptr);
    ~FieldGuideHistory() override;

    // 增删改
    // 2026-09-21: 阶段 L3.7 - 写操作切 Result. addRecord 返回 id (Result<qint64>)
    Q_INVOKABLE QVariantMap addRecord(const ViewRecord& record);
    Q_INVOKABLE QVariantMap deleteRecord(qint64 id);
    Q_INVOKABLE QVariantMap deleteByEntity(const QString& entityId);
    Q_INVOKABLE QVariantMap deleteAll();

    // 查询
    Q_INVOKABLE QVariantList getRecent(int limit = 50);
    Q_INVOKABLE QVariantList getByKingdom(const QString& kingdom, int limit = 100);
    Q_INVOKABLE QVariantList getByRoute(const QString& routeId);
    Q_INVOKABLE QVariantList getByFirstAid(const QString& firstAidId);
    Q_INVOKABLE QVariantList getFavorites();
    Q_INVOKABLE QVariantMap getById(qint64 id);

    // 统计
    Q_INVOKABLE int totalCount() const { return m_totalCount; }
    Q_INVOKABLE int plantCount() const { return m_plantCount; }
    Q_INVOKABLE int animalCount() const { return m_animalCount; }
    Q_INVOKABLE int insectCount() const { return m_insectCount; }
    Q_INVOKABLE int mushroomCount() const { return m_mushroomCount; }
    Q_INVOKABLE QVariantMap statsByKingdom();

    // 收藏 + 笔记
    Q_INVOKABLE QVariantMap setFavorite(qint64 id, bool favorite);
    Q_INVOKABLE QVariantMap addNote(qint64 id, const QString& note);

    // ViewRecord 没有 Q_GADGET, QML 既构造不出这个结构体, 也没法按位置传它那 12 个
    // 参数 (2026-10-20 真机上图鉴详情"收藏"点了没反应就是这个). 详情页只有 entity
    // 级别的上下文, 所以收藏走下面两个基本类型入口.
    Q_INVOKABLE QVariantMap toggleFavoriteByEntity(const QString& entityId,
                                                   const QString& kingdom,
                                                   const QString& commonName,
                                                   const QString& scientificName,
                                                   const QString& category,
                                                   int dangerLevel);
    Q_INVOKABLE bool isFavoriteEntity(const QString& entityId);

    // 清理
    Q_INVOKABLE QVariantMap cleanOldRecords(int daysOld = 90);

signals:
    void dataChanged();
    void recordAdded(qint64 id);
    void recordDeleted(qint64 id);

private:
    bool ensureSchema();
    void refreshCounts();

    // 2026-09-21 阶段 L4.x: 7 列 (id/entity_id/kingdom/common_name/category/danger_level/viewed_at)
    // row 映射, getByRoute/getByFirstAid/getFavorites 共用
    static QVariantMap rowToShortRecord(const QSqlQuery& q);

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    int m_totalCount = 0;
    int m_plantCount = 0;
    int m_animalCount = 0;
    int m_insectCount = 0;
    int m_mushroomCount = 0;
};

} // namespace outdoor

Q_DECLARE_METATYPE(outdoor::ViewRecord)
