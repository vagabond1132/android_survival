/**
 * @file RouteService.h
 * @brief 路线服务 - 路线管理、收藏、推荐
 */

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QList>
#include <QHash>
#include <QSet>
#include <QDateTime>
#include <QGeoCoordinate>
#include <QJsonArray>  // seedWaypoints 参数 (装载时灌 waypoints 表)
#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2

namespace outdoor {

/**
 * @struct Route
 * @brief 路线
 */
struct Route {
    QString id;
    QString name;
    QStringList alias;
    QString province;
    QString provinceCode;
    QString city;
    QString area;
    QString mountain;
    int difficulty = 1;       // 1-5
    QString type;              // 休闲/徒步/重装
    double distanceKm = 0;
    double durationHours = 0;
    int daysNeeded = 1;
    int elevationGainM = 0;
    int elevationLossM = 0;
    int maxAltitudeM = 0;
    int minAltitudeM = 0;
    QStringList bestSeason;
    QStringList terrain;
    QString highlights;
    QString description;
    QString source;            // built_in/user/shared
    QString sourceUrl;
    QString localTrackPath;
    bool permitRequired = false;
    QString permitInfo;
    QString rescuePhone;
    QGeoCoordinate trailhead;
    QGeoCoordinate trailend;
    QString trailheadName;       // 起点中文名(便于导航)
    QString trailendName;         // 终点中文名
    QString trailheadAddress;    // 起点详细地址(省+市+具体)
    QString trailendAddress;      // 终点详细地址
    // 端点坐标的可信度(2026-10-27 #131, 由 scripts/annotate_endpoint_data.js 补标):
    // coordPrecisionM 是坐标字面量的量化误差(米, 取两端最差的那个轴), 0 = 未知;
    // coordSource 说明这个坐标是从哪来的(editorial_estimate / gps_track_2bulu ...)。
    // 二者一起决定 UI 能不能把端点当导航目标用, 见「不给假读数」。
    int coordPrecisionM = 0;
    QString coordSource;
    bool trailheadCoordUnavailable = false;  // 库里坐标被判定不可信后只留名称/地址
    bool trailendCoordUnavailable = false;
    QStringList tags;
    QString routeNature = QStringLiteral("穿越");  // 性质:穿越/环线/单程
    bool isWild = false;          // 是否野线(非景区)
    bool hasPermit = false;       // 是否需办理入山许可(野线常需)
    int score = 0;                // 综合评分 0-100(越高越推荐)
    QString scoreDetail;          // 评分细节 JSON 字符串
    QString author;
    QString associatedSpeciesJson;  // 关联物种 JSON (含 plants/animals/insects/mushrooms)
    int visitCount = 0;
    bool isFavorite = false;
    bool notRecommended = false;  // 6000m+ 攀登类默认不推荐
    QString notRecommendedReason;  // 不推荐原因(展示给用户)
    QDateTime createdAt;
    QDateTime updatedAt;
};

class RouteService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalCount READ totalCount NOTIFY dataChanged)
    Q_PROPERTY(int favoriteCount READ favoriteCount NOTIFY dataChanged)

public:
    explicit RouteService(Database* db, QObject* parent = nullptr);
    ~RouteService() override;

    bool loadInitialData();

    int totalCount() const;
    int favoriteCount() const;

    // CRUD
    // 2026-09-21: 阶段 L3.1 - 写操作切 Result. 返回 QVariantMap {ok, value, error}.
    Q_INVOKABLE QVariantMap saveRoute(const Route& route);
    Q_INVOKABLE QVariantMap updateRoute(const QString& id, const Route& route);
    Q_INVOKABLE QVariantMap deleteRoute(const QString& id);
    Q_INVOKABLE bool routeExists(const QString& id);  // 谓词保留 bool

    // 查询
    Q_INVOKABLE QVariantMap getById(const QString& id);
    Q_INVOKABLE QVariantList getAll();
    Q_INVOKABLE QVariantList getByProvince(const QString& province);
    Q_INVOKABLE QVariantList getByDifficulty(int minLevel, int maxLevel);
    Q_INVOKABLE QVariantList getByType(const QString& type);
    Q_INVOKABLE QVariantList getByMountain(const QString& mountain);
    Q_INVOKABLE QVariantList getByMonth(int month);  // 1-12, 2026-09-20: rename from getBySeason (Phase 4 命名统一)
    Q_INVOKABLE QVariantList getByProvinceAndDifficulty(const QString& province,
                                                       int minLevel,
                                                       int maxLevel);
    // 2026-09-21: Phase 5 批次 3 - getFiltered 返回 Result (RouteListPage 主列表)
    Q_INVOKABLE QVariantMap getFiltered(const QString& province,
                                         int minDifficulty,
                                         int maxDifficulty,
                                         int month);
    Q_INVOKABLE QVariantList getByNature(const QString& nature);  // 穿越/环线/单程
    Q_INVOKABLE QVariantList getByWildness(bool isWild);         // 野线/景区
    Q_INVOKABLE QVariantList getByDaysRange(int minDays, int maxDays);
    Q_INVOKABLE QVariantList getByDistanceRange(double minKm, double maxKm);
    Q_INVOKABLE QVariantList getByAltitudeRange(int minAlt, int maxAlt);
    Q_INVOKABLE QVariantList getAdvanced(const QString& province,
                                         int minDifficulty,
                                         int maxDifficulty,
                                         int month,
                                         const QString& nature,
                                         bool includeWild,
                                         bool includeScenic,
                                         int minDays,
                                         int maxDays,
                                         double minKm,
                                         double maxKm);
    Q_INVOKABLE QStringList getAvailableProvinces();  // 2026-09-21: Phase 4 改 QStringList (与 TravelService 一致)
    Q_INVOKABLE QStringList getAvailableMonths();  // 2026-09-21: Phase 4 改 QStringList
    Q_INVOKABLE QStringList getAvailableNatures();
    Q_INVOKABLE QVariantList search(const QString& keyword);
    // 2026-10-27 #132: 地点级检索. search() 回的是路线卡 (id/name/province/difficulty/
    // distanceKm), 没有坐标, 落不到图上 —— "在地图上搜地点"要的是一条能定位的 POI,
    // 所以这里把 749 条路线的 1498 个起终点摊平成 POI 返回, 每条带 lat/lon 与归属路线.
    // 排序按"命中得多强"而不是字母序: POI 名 > 路线名/别名 > 山/区/市/省.
    Q_INVOKABLE QVariantList searchPlaces(const QString& keyword, int limit = 60);
    Q_INVOKABLE QVariantList getFavorites() const;
    Q_INVOKABLE QVariantList getMostVisited(int limit = 10);
    Q_INVOKABLE QVariantList getNearby(double lat, double lon,
                                        double radiusKm = 100);

    // 收藏
    // 2026-09-21: Phase 5 - 写操作切 Result. addFavorite/deleteFavorite 返回 QVariantMap {ok, value, error}.
    Q_INVOKABLE QVariantMap addFavorite(const QString& id);
    Q_INVOKABLE QVariantMap deleteFavorite(const QString& id);
    Q_INVOKABLE bool isFavorite(const QString& id);

    // 访问计数
    // 2026-09-21: 阶段 L3.5 - incrementVisitCount 切 Result<bool>
    Q_INVOKABLE QVariantMap incrementVisitCount(const QString& id);

    // 路点
    Q_INVOKABLE QVariantList getWaypoints(const QString& routeId);
    // polyline 是否在库: 0 = 没有路径点, 地图上只能画起终点示意直线
    Q_INVOKABLE int waypointCount(const QString& routeId);

    // 危险点
    Q_INVOKABLE QVariantList getDangers(const QString& routeId);

    // 关联物种(图鉴联动) - 返回 {plants: [ids], animals: [ids], insects, mushrooms}
    Q_INVOKABLE QVariantMap getAssociatedSpecies(const QString& routeId);

    // 推荐
    Q_INVOKABLE QVariantList recommend(int limit = 10);

signals:
    void dataChanged();
    void routeAdded(const QString& id);
    void routeUpdated(const QString& id);
    void routeDeleted(const QString& id);
    void favoriteChanged(const QString& id, bool favorite);

private:
    bool ensureSchema();
    bool loadFromJson();
    bool insertRoute(const Route& route);
    // routes.json 里带 "waypoints" 数组的条目(实测 GPS 轨迹)在装载时灌进 waypoints 表;
    // 表里没有这批路线的旧行(含改点后的残留), 所以先按 route_id DELETE 再整批 INSERT.
    // 返回写入的点数, 0 = 没写(调用方据此决定是否告警).
    int seedWaypoints(const QString& routeId, const QJsonArray& points);
    void rebuildIndex();  // 构建省/月二级索引

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    QHash<QString, Route> m_routes;
    // 性能优化:预建索引,避免每次查询 O(n) 扫描
    QHash<QString, QStringList> m_provinceIndex;     // 省份 -> 路线 id 列表
    QSet<QString> m_provinceSet;                     // 唯一省份(去重)
    QHash<int, QList<QString>> m_monthIndex;         // 月份(1-12) -> 路线 id 列表
    QSet<QString> m_routeIdSet;                       // O(1) 查 id 是否存在
    QHash<QString, int> m_difficultyBucket;          // 难度分桶缓存
    bool m_indexBuilt = false;
};

} // namespace outdoor
