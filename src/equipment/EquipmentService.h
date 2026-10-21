/**
 * @file EquipmentService.h
 * @brief 智能装备推荐引擎
 *
 * 核心功能：
 * - 海拔 7 段分级（L0-L6）
 * - 复合参数计算（海拔 × 天气 × 季节 × 行程）
 * - 规则引擎（30+ 规则）
 * - 微调记忆（本地）
 * - 强装检查（4 级别）
 */

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QList>
#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QDateTime>
#include <QJsonObject>
#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2
#include "../common/AltitudeLevel.h"  // 2026-10-21 (#18 C3): 段位阈值唯一定义在这里

namespace outdoor {

// 海拔段位: 真身是 src/common/AltitudeLevel.h 里的 ::AltitudeLevel (7 段 L0-L6).
//   这里只留一个名字, 装备侧既有代码和单测照旧写 EquipmentAltitudeLevel::L3.
//   2026-10-21 之前它是独立的一份枚举, 与 MapService 那份 5 段版本对同一个高度
//   读出不同档 (4800m: 这边 L5, 那边 L4), C3 就是收这件事.
using EquipmentAltitudeLevel = ::AltitudeLevel;

// 湿度类型
enum class HumidityType {
    Dry,        // 干燥
    Moderate,    // 适中
    Humid        // 闷热
};

// 紫外线等级
enum class UVLevel {
    Weak,        // 弱
    Moderate,    // 中等
    Strong,      // 强
    VeryStrong,  // 很强
    Extreme      // 极强
};

// 风等级
enum class WindLevel {
    Calm,        // 静风
    Light,       // 微风
    Moderate,    // 中等
    Strong,      // 大风
    Gale         // 强风
};

// 优先级
enum class Priority {
    Optional = 0,    // 可选
    Recommended = 1, // 推荐
    Important = 2,   // 强必带
    Critical = 3     // 绝对必带
};

// 季节
enum class Season {
    Spring,
    Summer,
    Autumn,
    Winter
};

// 降水等级
enum class Precipitation {
    None,
    Light,
    Moderate,
    Heavy,
    Storm
};

// 行程参数（输入）
struct TripParameters {
    int altitudeMax = 0;              // 最高海拔（米），最高 5000m
    int altitudeMin = 0;              // 最低海拔（米）
    int altitudeCamp = 0;            // 营地海拔（米）
    int days = 1;                     // 天数
    int people = 1;                   // 人数
    int difficulty = 1;               // 难度 1-5
    Season season = Season::Summer;   // 季节
    float tempAvg = 20.0f;            // 平均温度
    float tempMin = 10.0f;            // 最低温度
    float windSpeed = 0.0f;           // 风速 m/s
    Precipitation precipitation = Precipitation::None;
    float uvIndex = 5.0f;             // UV 指数

    // 地区气候维度（新增）
    int diurnalRange = 10;            // 昼夜温差（°C）
    HumidityType humidity = HumidityType::Moderate;
    UVLevel uvLevel = UVLevel::Moderate;
    WindLevel windLevel = WindLevel::Calm;
    bool isRainySeason = false;
    bool isSnowySeason = false;
    bool isCoastal = false;
    bool isDesert = false;
    bool isPlateau = false;
};

// 装备项
struct EquipmentItem {
    QString id;
    QString name;
    QString category;
    int weightG = 0;
    QString description;
    bool isCritical = false;
    bool isOTC = false;
    QJsonObject specs;
};

// 推荐项
struct RecommendedItem {
    EquipmentItem item;
    Priority priority = Priority::Optional;
    QStringList reasons;        // 推荐理由
    QString sourceRule;          // 来源规则
};

// 装备清单
struct EquipmentList {
    QString id;
    QString name;
    TripParameters params;
    QList<RecommendedItem> critical;   // 绝对必带
    QList<RecommendedItem> important;  // 强必带
    QList<RecommendedItem> recommended; // 推荐
    QList<RecommendedItem> optional;    // 可选
    int totalWeightG = 0;
    int checkedCount = 0;
    QStringList checkedIds;   // 已勾选 item 的 id 列表(幂等去重)
    QDateTime createdAt;
    bool isCompleted = false;
};

// 微调偏好
struct UserPreference {
    QString id;
    QString userId;
    QString equipmentId;         // 装备 ID
    QString action;             // "add" / "remove" / "always_skip"
    QString condition;          // JSON 条件
    int confidence = 50;
    QDateTime createdAt;
    QDateTime lastUsedAt;
    int useCount = 0;
};

/**
 * @class EquipmentService
 * @brief 智能装备推荐引擎（核心服务）
 */
class EquipmentService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalItems READ totalItems NOTIFY dataChanged)
    Q_PROPERTY(int totalRules READ totalRules NOTIFY dataChanged)

public:
    explicit EquipmentService(QObject* parent = nullptr);
    ~EquipmentService() override;

    // 初始化
    bool initialize();

    // 基础数据
    int totalItems() const;
    int totalRules() const;

    // 海拔段位 (阈值/名称的真身在 src/common/AltitudeLevel.h; 颜色一律找 CommonOptions.altitudeColor)
    Q_INVOKABLE static EquipmentAltitudeLevel getAltitudeLevel(int altitudeM);
    Q_INVOKABLE static QString getAltitudeLevelName(EquipmentAltitudeLevel level);
    Q_INVOKABLE static QJsonObject getAltitudeSegment(EquipmentAltitudeLevel level);

    // 装备查询
    Q_INVOKABLE QVariantList getAllItems();
    Q_INVOKABLE QVariantList getItemsByCategory(const QString& category);
    Q_INVOKABLE QVariantMap getById(const QString& id);  // 2026-09-20: rename from getItem (Phase 4 命名统一)
    Q_INVOKABLE QVariantList getCriticalItems();

    // 推荐生成
    Q_INVOKABLE QVariantMap generateList(const QString& name,
                                          const QVariantMap& paramsMap);

    // 清单管理
    // 2026-09-21: Phase 5 - 写操作切 Result
    Q_INVOKABLE QVariantMap saveList(const QVariantMap& listMap);
    // 2026-09-21: Phase 5 批次 3 - getAllLists 返回 Result, ServiceListModel 自动解包
    Q_INVOKABLE QVariantMap getAllLists();
    Q_INVOKABLE QVariantMap getList(const QString& id);
    Q_INVOKABLE QVariantMap deleteList(const QString& id);

    // 微调
    Q_INVOKABLE QVariantMap modifyList(const QString& id, const QVariantMap& listMap);

    // 偏好记忆
    // 2026-09-21: 阶段 L3.8 - addPreference/deletePreference 切 Result<bool>
    Q_INVOKABLE QVariantMap addPreference(const QString& equipmentId,
                                            const QString& action,
                                            const QVariantMap& condition = {});
    Q_INVOKABLE QVariantList getPreferences();
    Q_INVOKABLE QVariantMap deletePreference(const QString& id);
    Q_INVOKABLE void clearPreferences();

    // 2026-09-17: 用户自定义装备 (存在 QSettings, 区别于 base JSON 库)
    // 2026-09-21: Phase 5 - 写操作切 Result
    Q_INVOKABLE QVariantMap addUserItem(const QString& name, const QString& category,
                                        int weightG, bool isCritical);
    Q_INVOKABLE QVariantMap deleteUserItem(const QString& id);
    Q_INVOKABLE QVariantList getUserItems();
    // 2026-09-20: 编辑 user item (改名/换类/换重量/改关键标记), 走同一个 QSettings
    Q_INVOKABLE QVariantMap updateUserItem(const QString& id, const QString& name,
                                            const QString& category, int weightG,
                                            bool isCritical);

    // 强装检查
    Q_INVOKABLE QVariantMap startCheck(const QString& listId);
    // 2026-09-21: Phase 5 - checkItem/setItemChecked 返回 Result
    Q_INVOKABLE QVariantMap checkItem(const QString& listId,
                                      const QString& equipmentId,
                                      bool checked);
    // 2026-09-21: CategorySection.qml 调用 setItemChecked (在 ListModel delegate
    //   onToggled), 之前报 "EquipmentService.setItemChecked is not a function"
    //   因为只声明了 checkItem. 加这个 alias, 与 checkItem 行为完全一致.
    Q_INVOKABLE QVariantMap setItemChecked(const QString& listId,
                                           const QString& equipmentId,
                                           bool checked) {
        return checkItem(listId, equipmentId, checked);
    }
    // 2026-09-21: 阶段 L3.8 - confirmSkip 切 Result<bool>
    Q_INVOKABLE QVariantMap confirmSkip(const QString& listId,
                                          const QString& equipmentId,
                                          const QString& reason);
    Q_INVOKABLE QVariantMap getCheckProgress(const QString& listId);

    // PDF 导出
    Q_INVOKABLE QString exportToPdf(const QString& listId,
                                    const QString& filePath);

signals:
    void dataChanged();
    void listGenerated(QString listId);
    void listModified(QString listId);
    void listCompleted(QString listId);
    void criticalWarning(QString equipmentId, QString message);
    void preferenceLearned(QString preferenceId);

private:
    bool loadItems();
    bool loadRules();
    QList<RecommendedItem> applyRules(const TripParameters& params,
                                       const QHash<QString, EquipmentItem>& items);
    QList<RecommendedItem> applyPreferences(
        const QList<RecommendedItem>& baseList,
        const TripParameters& params);
    QList<RecommendedItem> removeUserExcluded(
        const QList<RecommendedItem>& list,
        const QHash<QString, EquipmentItem>& items);
    int calculateTotalWeight(const QList<RecommendedItem>& items);
    QString generateListId() const;
    void saveListToStorage(const EquipmentList& list);
    EquipmentList loadListFromStorage(const QString& id) const;
    QString matchCondition(const QString& conditionStr,
                            const TripParameters& params) const;
    bool preferenceMatchesParams(const QString& conditionJson,
                                 const TripParameters& params) const;

    /**
     * 2026-09-23: QML 表单只给数值风速/UV 指数, 没有等级下拉框时按标准换算成
     * WindLevel / UVLevel, 否则 wind_level / uv_level 规则永远不触发.
     * 风速按蒲福风级: <0.3 静风 / <3.4 微风 / <8.0 中等 / <10.8 大风 / >=10.8 强风
     * UV 按 WHO 指数: <3 弱 / <6 中等 / <8 强 / <11 很强 / >=11 极强
     */
    static WindLevel windLevelFromSpeed(float speedMs);
    static UVLevel uvLevelFromIndex(float index);

    /** sync + 成功时 emit dataChanged, 失败透传 (供 addUserItem/deleteUserItem/updateUserItem 复用) */
    QVariantMap saveUserItemsAndEmit(const QString& ctx);

    QHash<QString, EquipmentItem> m_items;
    QJsonArray m_rules;
    QList<UserPreference> m_preferences;
    QString m_storagePath;
};

} // namespace outdoor

Q_DECLARE_METATYPE(outdoor::RecommendedItem)
Q_DECLARE_METATYPE(QList<outdoor::RecommendedItem>)
