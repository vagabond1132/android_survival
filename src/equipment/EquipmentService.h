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

// 降水等级 (2026-10-21: 补冬季降雪四档)
// 注意 5..8 是雪, 1..4 是雨 —— 规则条件里 precipitation in [heavy, storm] 只认雨,
// 雪要写 snow_heavy / snow_storm, 两者不会互相误触发。
enum class Precipitation {
    None,
    Light,
    Moderate,
    Heavy,
    Storm,
    SnowLight,
    SnowModerate,
    SnowHeavy,
    SnowStorm
};

// 背负方式 (2026-10-22 新增, 用户报"未区分轻装和重装")
// 规则里写 `load >= overnight` 这类条件; 档位序数即枚举序数, 越大背得越多.
// DayHike  轻装一日: 不过夜, 背当天要用的 (20-30L)
// FastPack 单日高强度: 不过夜但长距离/高难度, 要备用保暖与定量水粮
// Overnight 过夜重装: 露营一晚, 帐篷/睡袋/防潮垫/炉具进必带
// Expedition 多日重装: 2 晚以上或 5000m+ 无补给, 再加修理/备份/氧气
enum class LoadStyle {
    DayHike = 0,
    FastPack = 1,
    Overnight = 2,
    Expedition = 3
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
    LoadStyle load = LoadStyle::DayHike;   // 背负方式 (2026-10-22)

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
    QString unit = QStringLiteral("件");   // 计件单位 (件/根/克/片/L), 配合 qty
    QJsonObject specs;
};

// 推荐项
struct RecommendedItem {
    EquipmentItem item;
    Priority priority = Priority::Optional;
    QStringList reasons;        // 推荐理由
    QString sourceRule;          // 来源规则
    // 2026-10-22: 定量. 规则 JSON 里可选 "qty": {"energy_bar": 8} —— 同一 item 被多条
    //   规则命中时取**最大** qty (所以按 days 分档的三条阈值规则天然叠加:
    //   days>=2 给 8 根, days>=4 给 18 根, days>=7 给 30 根, 7 天的行程拿到 30).
    //   重量按 weightG * qty 算, 单件重仍显示 unit weight.
    int qty = 1;
    int weightTotalG() const { return item.weightG * (qty > 0 ? qty : 1); }
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

    // 背负方式中文名 (2026-10-22)。参数用 int 而不是 LoadStyle: 这个枚举没注册 Q_ENUM,
    //   QML 传 JS number 给枚举形参转换不过去。
    Q_INVOKABLE static QString getLoadStyleName(int load);

    // === 往年天气 (省 × 月 气候常态表) =====================================
    // 2026-10-22: 用户报"清单不看路线地点往年天气"。这里给的是 generateList
    //   能直接吃的参数片段 (海拔已按 -6.5℃/1000m 修正到路线高度), 页面拿到之后
    //   合并进表单即可, 不要在 QML 里重算修正量。
    // province 支持 "四川/西藏" 这种跨省路线: 逐个查出来取平均。
    // 查不到 (省份不在表里 / month 不在 1..12) 返回空 map —— 不返回一份假天气。
    Q_INVOKABLE QVariantMap climateFor(const QString& province, int month, int altitudeM) const;
    Q_INVOKABLE QStringList climateProvinceNames() const;
    Q_INVOKABLE int climateTotalProvinces() const { return m_climate.size(); }

    /**
     * 代表站坐标 (2026-10-28 #154): 在线预报要按经纬度请求, 而 QML 只认省名。
     * 返回 {lat, lon, refAltitudeM}; 省名不在表里返回空 map (不编一个坐标出去)。
     */
    Q_INVOKABLE QVariantMap climateStation(const QString& province) const;

    /// 海拔修正系数, 来自 climate_normals.json (2026-10-28 #154: 在线预报服务共用同一份, 不再各存一遍)
    double lapseRateCPer1000m() const { return m_climateLapseCPerKm; }
    double uvRatePer1000m() const { return m_climateUvPerKm; }

    // === 数值 → 档位 (阈值只在这里抄一份, QML 与在线预报服务都走这四个) ======
    /**
     * 2026-09-23: QML 表单只给数值风速/UV 指数, 没有等级下拉框时按标准换算成
     * WindLevel / UVLevel, 否则 wind_level / uv_level 规则永远不触发.
     * 风速按蒲福风级: <0.3 静风 / <3.4 微风 / <8.0 中等 / <10.8 大风 / >=10.8 强风
     * UV 按 WHO 指数: <3 弱 / <6 中等 / <8 强 / <11 很强 / >=11 极强
     */
    static WindLevel windLevelFromSpeed(float speedMs);
    static UVLevel uvLevelFromIndex(float index);

    /**
     * 降水档。**月档与日档阈值不同, 不能共用一套数**:
     * 月表存的是整月累计 (5/30/90/180 mm), 日预报存的是当天累计 (0~几十 mm),
     * 把日量喂进月阈值会把所有雨天都判成 None。tempMinC <= -1 时换雪档
     * (装备引擎里 snow_* 才走冰爪/雪镜/雪套规则)。
     */
    static int precipitationBandMonthly(double precipMm, double tempMinC);
    static int precipitationBandDaily(double precipMm, double tempMinC);
    /// 湿度档: 月表没有实测相对湿度, 只能拿月降水当"这个月大概多湿"的代理 (<25/100)
    static int humidityBandMonthly(double precipMm);
    /// 湿度档: 日预报有实测相对湿度 %, 直接按 % 分档 (<40/75), 不必绕道降水
    static int humidityBandFromRh(double rhPercent);
    /// 季节按气象月划: 3-5 春 / 6-8 夏 / 9-11 秋 / 12-2 冬
    static int seasonFromMonth(int month);

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
    bool loadClimateNormals();
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

    /** sync + 成功时 emit dataChanged, 失败透传 (供 addUserItem/deleteUserItem/updateUserItem 复用) */
    QVariantMap saveUserItemsAndEmit(const QString& ctx);

    QHash<QString, EquipmentItem> m_items;
    QJsonArray m_rules;
    QList<UserPreference> m_preferences;
    QString m_storagePath;
    // 省名 -> 该省 12 个月的数组块 (原样存 JSON, 查询时再换算, 不再造一套 struct)
    QHash<QString, QJsonObject> m_climate;
    double m_climateLapseCPerKm = -6.5;   // 气温直减率, 来自 climate_normals.json
    double m_climateUvPerKm = 0.12;       // 每 1000m 紫外线增量 (比例)
};

} // namespace outdoor

Q_DECLARE_METATYPE(outdoor::RecommendedItem)
Q_DECLARE_METATYPE(QList<outdoor::RecommendedItem>)
