/**
 * @file TravelService.h
 * @brief 自驾游服务 - 路线管理、收藏、起终点导航
 */

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QList>
#include <QGeoCoordinate>
#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2

namespace outdoor {

/**
 * @struct Travel
 * @brief 自驾游路线
 */
struct Travel {
    QString id;
    QString name;
    QString province;          // 涉及省份(可多省用 / 分隔)
    QString startCity;
    QString endCity;
    QString startName;          // 起点名
    QString endName;            // 终点名
    double startLat = 0;
    double startLon = 0;
    double endLat = 0;
    double endLon = 0;
    // 端点坐标可信度(2026-10-27 #131)。自驾库里 88/101 条的起点与终点是同一个
    // 点 —— 那是城区中心点, 不是路口, coordSource="city_center" 就是用来让 UI
    // 说清这件事的; 量化误差另见 coordPrecisionM(米, 0=未知)。
    int coordPrecisionM = 0;
    QString coordSource;
    bool endCoordUnavailable = false;
    double distanceKm = 0;
    int days = 1;
    int driveHours = 0;         // 驾驶时长
    QString roadType;           // 柏油/碎石/沙漠/山路/草原
    int maxAltitude = 0;        // 最高海拔
    QStringList bestSeason;
    QString highlights;
    QString supply;             // 沿途补给
    int fuelCostCNY = 0;        // 预估油费
    QString description;
    QStringList tags;
    bool isFavorite = false;
    int visitCount = 0;
};

class TravelService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int totalCount READ totalCount NOTIFY dataChanged)

public:
    explicit TravelService(QObject* parent = nullptr);
    ~TravelService() override;

    bool loadInitialData();
    int totalCount() const;

    // 基础查询
    Q_INVOKABLE QVariantMap getById(const QString& id);
    Q_INVOKABLE QVariantList getAll();
    Q_INVOKABLE QVariantList search(const QString& keyword);
    // 2026-10-27 #132: 地点级检索, 与 RouteService::searchPlaces 同一口径 ——
    // search() 回的是线路卡 (没有坐标), 地图要落点必须拿到起终点的 lat/lon.
    // 注意 travel.json 的 startName/endName 101 条全部只到城市级, 所以这里搜出来的
    // 是"成都/拉萨"这类城市点, 不是某个具体路口; 展示层要如实按城市点标注.
    Q_INVOKABLE QVariantList searchPlaces(const QString& keyword, int limit = 60);

    // 筛选
    Q_INVOKABLE QVariantList getByProvince(const QString& province);
    Q_INVOKABLE QVariantList getByDaysRange(int minDays, int maxDays);
    Q_INVOKABLE QVariantList getByDistanceRange(double minKm, double maxKm);
    Q_INVOKABLE QVariantList getByMonth(int month);  // 2026-09-20: rename from getBySeason (Phase 4 命名统一)
    // 2026-09-21: Phase 5 批次 3 - getFiltered 返回 Result (TravelListPage 主列表)
    Q_INVOKABLE QVariantMap getFiltered(const QString& province,
                                         int minDays, int maxDays,
                                         double minKm, double maxKm,
                                         int month);

    // 收藏/计数
    // 2026-09-21: Phase 5 - 写操作切 Result
    Q_INVOKABLE QVariantMap addFavorite(const QString& id);
    Q_INVOKABLE QVariantMap deleteFavorite(const QString& id);
    Q_INVOKABLE bool isFavorite(const QString& id);  // 谓词保留 bool
    Q_INVOKABLE QVariantList getFavorites();
    // 2026-09-21: 阶段 L3.5 - incrementVisitCount 切 Result<bool>
    Q_INVOKABLE QVariantMap incrementVisitCount(const QString& id);

    // 工具
    Q_INVOKABLE QStringList getAvailableProvinces();
    Q_INVOKABLE QStringList getAvailableMonths();

signals:
    void dataChanged();
    void favoriteChanged(const QString& id, bool favorite);

private:
    bool loadFromJson();
    QHash<QString, Travel> m_travels;
};

} // namespace outdoor
