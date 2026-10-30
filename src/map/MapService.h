/**
 * @file MapService.h
 * @brief 地图服务 - 整合地图显示、轨迹、物种标注、海拔分段
 *
 * 设计要点：
 * - 双方案：在线（天地图）+ 离线（瓦片）
 * - 三种底图：地形/路网/卫星
 * - 与奥维互通：GPX/KML 导入导出
 * - 海拔分段叠加
 * - 照片 GPS 自动标注
 */

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QList>
#include <QHash>
#include <QDateTime>
#include <QGeoCoordinate>
#include <QVariantMap>
#include <QVariantList>
#include <limits>  // 2026-10-26「精度到 1 m」: 形参默认值用 quiet_NaN 表示"未知"
#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2
#include "../common/AltitudeLevel.h"  // 2026-10-21 (#18 C3): 海拔段位改这里统一取

// 轨迹记录频率
enum class TrackFrequency {
    Seconds_5 = 5,    // 5 秒（默认）
    Seconds_10 = 10,  // 10 秒
    Seconds_15 = 15,  // 15 秒
    Seconds_30 = 30   // 30 秒
};

namespace outdoor {

// 底图类型
enum class BaseMapType {
    Terrain,    // 地形图（默认）
    Road,       // 路网图
    Satellite   // 卫星图
};

// 数据源
enum class TileSource {
    TianMap,    // 天地图（在线）
    Offline     // 离线瓦片
};

// 海拔段位的 enum 与阈值都在 ../common/AltitudeLevel.h (2026-10-21 #18 C3: 这里原来
// 自己另立了一份 5 段 L0-L4, 与装备侧的 7 段读成不同档; 颜色也从这里删掉了 —— 色源单一,
// 界面上的海拔色一律走 CommonOptions.altitudeColor(level)).

// 照片结构
struct MapPhoto {
    qint64 id = 0;
    QString imagePath;
    QString imageThumbPath;
    double lat = 0;
    double lon = 0;
    double altitude = 0;
    double accuracy = 0;
    QDateTime takenAt;
    QString speciesId;
    QString speciesName;
    QString speciesCategory;
    QString speciesSource;  // field_guide/manual/imported
    double confidence = 0;
    QString note;
    bool isFavorite = false;
};

// 轨迹结构
struct Track {
    QString id;
    QString name;
    QDateTime startTime;
    QDateTime endTime;
    double totalDistanceM = 0;
    double elevationGainM = 0;
    double elevationLossM = 0;
    double maxAltitudeM = 0;
    double minAltitudeM = 0;
    int pointCount = 0;
    QString source;            // recorded/imported
    QString originalFormat;    // gpx/kml/csv
    QString routeId;
    TrackFrequency frequency = TrackFrequency::Seconds_5;  // 记录频率
    QList<QGeoCoordinate> points;
    QList<double> elevations;
};

// 轨迹点
struct TrackPoint {
    int sequence = 0;
    QGeoCoordinate coord;
    double elevation = 0;
    double accuracy = 0;
    double speed = 0;
    QDateTime timestamp;
};

/**
 * @class MapService
 * @brief 地图服务
 */
class MapService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(int photoCount READ photoCount NOTIFY dataChanged)
    Q_PROPERTY(int trackCount READ trackCount NOTIFY dataChanged)
    Q_PROPERTY(BaseMapType currentBaseMap READ currentBaseMap
               WRITE setCurrentBaseMap NOTIFY baseMapChanged)
    Q_PROPERTY(TileSource currentSource READ currentSource
               WRITE setCurrentSource NOTIFY sourceChanged)

public:
    explicit MapService(QObject* parent = nullptr);
    ~MapService() override;

    // 初始化
    bool initialize();

    // 计数
    int photoCount() const;
    int trackCount() const;

    // 底图控制
    BaseMapType currentBaseMap() const { return m_currentBaseMap; }
    void setCurrentBaseMap(BaseMapType type);
    TileSource currentSource() const { return m_currentSource; }
    void setCurrentSource(TileSource source);
    Q_INVOKABLE QString getTileUrl(int z, int x, int y);
    Q_INVOKABLE QString getBaseMapName(BaseMapType type) const;

    // 海拔段位 (真身在 ../common/AltitudeLevel.h, 这里只是转发 + 给单测一个入口)
    Q_INVOKABLE static AltitudeLevel getAltitudeLevel(double altitudeM);
    Q_INVOKABLE static QString getAltitudeLevelName(AltitudeLevel level);
    Q_INVOKABLE static double getAltitudeLevelMin(AltitudeLevel level);
    Q_INVOKABLE static double getAltitudeLevelMax(AltitudeLevel level);

    // 照片管理
    Q_INVOKABLE QVariantMap addPhoto(const QString& imagePath,
                                       const QVariantMap& exifData);
    Q_INVOKABLE QVariantList getAllPhotos() const;
    Q_INVOKABLE QVariantList getPhotosByCategory(const QString& category);
    Q_INVOKABLE QVariantList getPhotosInBounds(double minLat, double maxLat,
                                                double minLon, double maxLon);
    Q_INVOKABLE QVariantMap getPhotoById(qint64 id);  // 2026-09-20: rename from getPhoto (Phase 4 命名统一)
    // 2026-09-21: 阶段 L3.4 - 写操作切 Result
    Q_INVOKABLE QVariantMap deletePhoto(qint64 id);
    Q_INVOKABLE QVariantMap updatePhotoNote(qint64 id, const QString& note);
    Q_INVOKABLE QVariantMap updatePhotoSpecies(qint64 id, const QString& speciesId,
                                                const QString& speciesName,
                                                const QString& category);
    Q_INVOKABLE QVariantMap setPhotoFavorite(qint64 id, bool favorite);

    // EXIF 提取
    Q_INVOKABLE QVariantMap extractExif(const QString& imagePath);

    // 轨迹管理
    // 2026-09-21: Phase 5 - startTrack 返回 Result {ok, value=trackId, error}
    Q_INVOKABLE QVariantMap startTrack(const QString& name,
                                       int frequencySeconds = 5);
    // 2026-09-21: 阶段 L3.4 - addTrackPoint/stopTrack/deleteTrack 切 Result
    // 2026-10-26「精度到 1 m」: 补 accuracy (米, 68% 半径).
    //   "未知"一律传 NaN (或省略) —— 用 -1 当哨兵会被 isfinite 放行、落成"海平面 -1 米"
    //   的假读数; 未知时那一键整条不写.
    Q_INVOKABLE QVariantMap addTrackPoint(const QString& trackId,
                                           double lat, double lon,
                                           double elevation = std::numeric_limits<double>::quiet_NaN(),
                                           double accuracy = std::numeric_limits<double>::quiet_NaN());
    Q_INVOKABLE QVariantMap stopTrack(const QString& trackId);
    Q_INVOKABLE QVariantList getAllTracks() const;
    // 2026-10-09: 契约统一 - 返回 Result 风格 {ok, value, error}.
    //   与 getTrackStats/getTrackProfile/deleteTrack/importXxx 一致, 供 QML 统一判 ok.
    Q_INVOKABLE QVariantMap getTrackById(const QString& id);  // 2026-09-20: rename from getTrack (Phase 4 命名统一)
    Q_INVOKABLE QVariantMap deleteTrack(const QString& id);
    Q_INVOKABLE QList<QGeoCoordinate> getTrackPoints(const QString& trackId);
    Q_INVOKABLE QVariantList getFrequencyOptions();
    Q_INVOKABLE QString getFrequencyLabel(int seconds);
    Q_INVOKABLE int getDefaultFrequency() const;
    // 2026-10-29: 用户选过的采样档位落 QSettings (与 ui/nightMode 同一套机制),
    //   重启后 getDefaultFrequency() 读回它, 不必每次重选. 只认 5/10/15/30.
    Q_INVOKABLE void setFrequencySeconds(int seconds);
    Q_INVOKABLE QVariantList getTrackElevations(const QString& trackId);

    // 导入导出
    // 2026-09-21: Phase 5 - 导入返回 Result {ok, value=trackId, error}
    Q_INVOKABLE QVariantMap importGpx(const QString& filePath);
    Q_INVOKABLE QVariantMap importKml(const QString& filePath);
    Q_INVOKABLE QVariantMap importCsv(const QString& filePath);
    // 2026-09-21: 阶段 L3.4 - 导出切 Result
    Q_INVOKABLE QVariantMap exportTrackAsGpx(const QString& trackId,
                                              const QString& filePath);
    Q_INVOKABLE QVariantMap exportTrackAsKml(const QString& trackId,
                                              const QString& filePath);
    Q_INVOKABLE QVariantMap exportAllSpeciesAsKml(const QString& filePath);

    // 物种位置
    // 2026-09-21: 阶段 L3.4 - addSpeciesLocation 切 Result
    // 2026-10-26「轨迹/标注点精度到 1 m」: 末尾补 accuracy (米, 68% 半径).
    //   注意第 6 个参数一直是 **altitude** 不是 accuracy (以前被误读过一次).
    //   altitude/accuracy 未知时传 NaN (或省略), 那一键整条不写 —— 原来 QML 各调用点
    //   一律写 0, 落盘就成了"海平面 0 米 / 精度 0 米"两个假数.
    // 2026-10-28 问题2: 末尾补 dangerLevel. 「添加标注」对话框已经算出危险档
    //   (选物种取物种的, 只选类别按类别估), 原来第 9 参不存在、C++ 把 dangerLevel
    //   写死 0 → 用户在弹层里看到的危险档根本没进文件; 现在原样落盘.
    //   读侧仍走 MapPage.dangerLevelOf() 反查, 这一键只是把当时的判定留住.
    Q_INVOKABLE QVariantMap addSpeciesLocation(const QString& speciesId,
                                                 const QString& speciesName,
                                                 const QString& category,
                                                 double lat, double lon,
                                                 double altitude = std::numeric_limits<double>::quiet_NaN(),
                                                 const QString& note = QString(),
                                                 double accuracy = std::numeric_limits<double>::quiet_NaN(),
                                                 int dangerLevel = 0);
    Q_INVOKABLE QVariantList getSpeciesLocations();
    Q_INVOKABLE QVariantList getSpeciesLocationsInBounds(
        double minLat, double maxLat, double minLon, double maxLon);
    // 2026-10-23 #113: 删除一条标注 (物种详情页「地图上的记录」每行的删除入口).
    //   locationId = addSpeciesLocation 生成的 epoch-ms 字符串, 直接拼进 species_<id>.json
    //   文件名, 所以只收纯数字. 返回 Result {ok, value=是否真的删掉一个文件}.
    Q_INVOKABLE QVariantMap deleteSpeciesLocation(const QString& locationId);

    // 统计
    Q_INVOKABLE QVariantMap getStats();
    Q_INVOKABLE QVariantMap getAltitudeStats();

    // 2026-09-14: P1 轨迹详细分析
    // getTrackStats: 8 项基础统计 (距离/时长/配速/累计升降/平均速度/最高/最低)
    //   + 休息点 (speed=0 持续 N 分钟) + 卡路里估算
    //   返回: { distanceM, durationS, avgSpeed, maxSpeed, avgPace, elevationGainM,
    //           elevationLossM, maxAlt, minAlt, calorieKcal, restPoints:[{lat,lon,ts}],
    //           splits:[{km, durationS, avgPace}], ok }
    Q_INVOKABLE QVariantMap getTrackStats(const QString& trackId, double weightKg = 65.0);

    // 2026-09-14: P1 海拔+速度曲线数据 (供 qml/components/base/LineProfile.qml 自绘;
    //   原先写"供 QtCharts 使用", 2026-10-26 #121 把 Charts 整个依赖删了)
    // 返回: { distances:[m], elevations:[m], speeds:[m/s], pointCount }
    Q_INVOKABLE QVariantMap getTrackProfile(const QString& trackId);

    // 清理
    Q_INVOKABLE int cleanupOldData(int daysOld = 90);

    // 地图辅助
    Q_INVOKABLE QString formatDistance(double meters);
    Q_INVOKABLE QString formatDuration(qint64 seconds);
    Q_INVOKABLE QString formatElevation(double meters);

signals:
    void dataChanged();
    void baseMapChanged();
    void sourceChanged();
    void trackStarted(QString trackId);
    void trackPointAdded(QString trackId, double lat, double lon);
    void trackStopped(QString trackId);
    void photoAdded(qint64 photoId);
    void photoUpdated(qint64 photoId);
    void photoDeleted(qint64 photoId);
    void trackImported(QString trackId, int pointCount);
    void warningTriggered(QString message);

private:
    QString generateId() const;
    bool ensureSchema();
    QString m_storagePath;
    BaseMapType m_currentBaseMap = BaseMapType::Terrain;
    TileSource m_currentSource = TileSource::TianMap;
    QString m_tianMapKey;  // 天地图 Key
};

} // namespace outdoor
