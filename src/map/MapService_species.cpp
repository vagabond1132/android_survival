/**
 * @file MapService_species.cpp
 * @brief MapService::species + 通用 stats + 轨迹分析 (2026-09-21 阶段 L5.4 拆分)
 *
 * 从 MapService.cpp 拆出, 包含:
 *   - addSpeciesLocation / getSpeciesLocations / getSpeciesLocationsInBounds
 *     / deleteSpeciesLocation (2026-10-23 #113)
 *   - getStats / getAltitudeStats / cleanupOldData
 *   - getTrackStats / getTrackProfile (P1 轨迹详细分析)
 *   - appendRestRun 匿名 namespace 帮手 (被 getTrackStats 的休息点检测用)
 *
 * 注: 轨迹的距离/升降/速度口径全在 ../common/TrackMetrics.h, 这里只负责读文件、
 *     按"文件自述优先"取舍、把结果填成 QVariantMap.
 *
 * 注: formatDistance/formatDuration/formatElevation + generateId
 *     在 MapService.cpp (core) 定义.
 */

#include "MapService.h"
#include "../common/TrackMetrics.h"  // 2026-10-29 #168: 轨迹统计口径 (与 stopTrack 同一份)
#include "../core/Logger.h"
#include "../core/Result.h"
#include "../core/ServiceErrors.h"
#include "../core/internal/QmlResultBridge.h"

#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QDateTime>
#include <cmath>
#include <limits>  // 2026-10-26: quiet_NaN 哨兵, 缺 elevation 键时不当 0 用
#include <algorithm>

namespace outdoor {

QVariantMap MapService::addSpeciesLocation(const QString& speciesId,
                                              const QString& speciesName,
                                              const QString& category,
                                              double lat, double lon,
                                              double altitude,
                                              const QString& note,
                                              double accuracy,
                                              int dangerLevel) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::addSpeciesLocation";

    // 2026-10-26「精度到 1 m」: 标注点先自证坐标有效. 无权限时 currentLatitude 恒为 0,
    // 之前会安静地落一个 (0,0) 的标注 —— ①营地方位条里那批"未命名标注"就是这么来的.
    if (!std::isfinite(lat) || !std::isfinite(lon)
            || lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0
            || (lat == 0.0 && lon == 0.0)) {
        return toQVariant(Err<bool>(ServiceErrorCode::InvalidArgument,
                                      QStringLiteral("标注点坐标无效"), ctx));
    }

    qint64 id = QDateTime::currentMSecsSinceEpoch();
    QJsonObject obj;
    obj["id"] = QString::number(id);
    obj["speciesId"] = speciesId;
    obj["speciesName"] = speciesName;
    obj["speciesCategory"] = category;
    obj["lat"] = lat;
    obj["lon"] = lon;
    // 2026-10-26: 高程/精度未知 (NaN 或 <=0) 时整键不写 —— 写 0 会被读成"海平面 0 米"
    // /"精度 0 米", 而界面会照抄这个假数 (见 [[no-fake-readout-rule]]).
    if (std::isfinite(altitude)) obj["altitude"] = altitude;
    if (std::isfinite(accuracy) && accuracy > 0) obj["accuracy"] = accuracy;
    obj["note"] = note;
    obj["takenAt"] = QDateTime::currentDateTime().toString(Qt::ISODate);
    // 2026-09-15: 写 dangerLevel 字段 - 暂时固定 0, MapPage 端用 speciesId 反查
    // (后续如需在此处查询, 通过 ServiceRegistry 拿 SpeciesService)
    // 2026-10-28 问题2: 不再写死 0. 「添加标注」对话框算出的危险档以前根本没有落点
    // (签名里没有这一参), 于是文件里的 dangerLevel 永远是 0, 与用户当时看到的判定
    // 对不上. 现在收调用方传进来的值; 读侧仍走 MapPage.dangerLevelOf() 反查, 这一键
    // 只把"记录那一刻的判定"留住。范围夹到 0..5 (与图鉴 dangerLevel 同一口径)。
    obj["dangerLevel"] = qBound(0, dangerLevel, 5);

    QFile file(m_storagePath + QString("/species_%1.json").arg(id));
    if (!file.open(QIODevice::WriteOnly)) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                      QStringLiteral("无法写入物种位置文件"), ctx));
    }
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    file.close();

    emit dataChanged();
    return toQVariant(Ok(true));
}

QVariantList MapService::getSpeciesLocations() {
    QVariantList list;
    QDir dir(m_storagePath);
    QStringList files = dir.entryList({"species_*.json"}, QDir::Files);
    for (const QString& f : files) {
        QFile file(m_storagePath + "/" + f);
        if (!file.open(QIODevice::ReadOnly)) continue;
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        file.close();
        if (doc.isObject()) {
            list.append(doc.object().toVariantMap());
        }
    }
    return list;
}

QVariantList MapService::getSpeciesLocationsInBounds(double minLat, double maxLat,
                                                          double minLon, double maxLon) {
    QVariantList list;
    auto all = getSpeciesLocations();
    for (const auto& v : all) {
        QVariantMap m = v.toMap();
        double lat = m["lat"].toDouble();
        double lon = m["lon"].toDouble();
        if (lat >= minLat && lat <= maxLat &&
            lon >= minLon && lon <= maxLon) {
            list.append(m);
        }
    }
    return list;
}

QVariantMap MapService::deleteSpeciesLocation(const QString& locationId) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::deleteSpeciesLocation";

    const QString id = locationId.trimmed();
    // id 会被拼成 species_<id>.json 的路径片段 —— 只收纯数字, 挡掉 "../x" 这类注入.
    bool digitsOnly = !id.isEmpty();
    for (const QChar& c : id) {
        if (!c.isDigit()) { digitsOnly = false; break; }
    }
    if (!digitsOnly) {
        return toQVariant(Err<bool>(ServiceErrorCode::InvalidArgument,
                                    QStringLiteral("标注 ID 非法: %1").arg(id), ctx));
    }

    QFile file(m_storagePath + QString("/species_%1.json").arg(id));
    if (!file.exists()) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                    QStringLiteral("标注不存在: %1").arg(id), ctx));
    }
    if (!file.remove()) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
            QStringLiteral("标注文件删除失败: %1").arg(file.errorString()), ctx));
    }
    emit dataChanged();
    return toQVariant(Ok(true));
}

QVariantMap MapService::getStats() {
    QVariantMap stats;
    stats["photoCount"] = photoCount();
    stats["trackCount"] = trackCount();
    stats["speciesCount"] = getSpeciesLocations().size();

    int totalPoints = 0;
    double totalDist = 0;
    for (const auto& v : getAllTracks()) {
        totalPoints += v.toMap()["pointCount"].toInt();
        totalDist += v.toMap()["totalDistanceM"].toDouble();
    }
    stats["totalTrackPoints"] = totalPoints;
    stats["totalDistanceKm"] = totalDist / 1000.0;

    return stats;
}

QVariantMap MapService::getAltitudeStats() {
    QVariantMap stats;
    QHash<AltitudeLevel, int> levelCount;
    int overLimit = 0;

    for (const auto& v : getAllPhotos()) {
        double alt = v.toMap()["altitude"].toDouble();
        if (alt > 5000) overLimit++;
        else levelCount[getAltitudeLevel(alt)]++;
    }

    for (auto it = levelCount.constBegin(); it != levelCount.constEnd(); ++it) {
        stats[getAltitudeLevelName(it.key())] = it.value();
    }
    stats["over5000"] = overLimit;

    return stats;
}

int MapService::cleanupOldData(int daysOld) {
    QDateTime threshold = QDateTime::currentDateTime().addDays(-daysOld);
    int cleaned = 0;

    QDir dir(m_storagePath);
    QStringList files = dir.entryList({"*.json"}, QDir::Files);
    for (const QString& f : files) {
        QFile file(m_storagePath + "/" + f);
        if (!file.open(QIODevice::ReadOnly)) continue;
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        file.close();
        if (!doc.isObject()) continue;

        QString dtStr = doc.object()["takenAt"].toString();
        if (dtStr.isEmpty()) dtStr = doc.object()["startTime"].toString();
        QDateTime dt = QDateTime::fromString(dtStr, Qt::ISODate);
        if (dt.isValid() && dt < threshold) {
            if (file.remove()) cleaned++;
        }
    }

    emit dataChanged();
    return cleaned;
}


// =====================================================================
// 2026-09-14: P1 轨迹详细分析
// =====================================================================

namespace {
    // 一段"短窗速度贴着 0"的点收成一个休息点: 首末都得有时刻, 且时长 >= 3 分钟才算.
    // 坐标取这一段的中间点 —— 列表里要点到地图上.
    void appendRestRun(QVariantList& out,
                       const QVector<outdoor::track::Sample>& samples,
                       const QVector<qint64>& tsMs,
                       int startIdx, int endIdx) {
        if (startIdx < 0 || endIdx <= startIdx) return;
        if (endIdx >= samples.size() || endIdx >= tsMs.size()) return;
        if (tsMs[startIdx] < 0 || tsMs[endIdx] < 0) return;
        const qint64 restSec = (tsMs[endIdx] - tsMs[startIdx]) / 1000;
        if (restSec < 180) return;
        const int mid = (startIdx + endIdx) / 2;
        QVariantMap rest;
        rest["lat"] = samples[mid].lat;
        rest["lon"] = samples[mid].lon;
        rest["durationS"] = restSec;
        rest["startIdx"] = startIdx;
        rest["endIdx"] = endIdx;
        out.append(rest);
    }
}

QVariantMap MapService::getTrackStats(const QString& trackId, double weightKg) {
    QVariantMap result;
    result["ok"] = false;
    result["error"] = "";

    // 2026-10-23 #115 (A19): 这三个 error 会被 TrackDetailPage.qml:134 直接拼进页面上的
    //   note ("统计没算出来: " + stats.error —— 这条通道给的是纯 QString, 与 QmlResultBridge
    //   的 ServiceError 不同), 原来是英文, 中文界面里就露出 "track points file not found"。
    //   注意别跟着加 .message: 这里没有 ServiceError 那一层。
    if (trackId.isEmpty()) {
        result["error"] = QStringLiteral("没给轨迹编号");
        return result;
    }

    // 加载点
    QFile pf(m_storagePath + QString("/track_%1_points.json").arg(trackId));
    if (!pf.open(QIODevice::ReadOnly)) {
        result["error"] = QStringLiteral("这条轨迹的点数据读不到");
        return result;
    }
    QJsonDocument pdoc = QJsonDocument::fromJson(pf.readAll());
    pf.close();
    if (!pdoc.isArray()) {
        result["error"] = QStringLiteral("这条轨迹的点数据格式不对");
        return result;
    }
    QJsonArray points = pdoc.array();
    if (points.size() < 2) {
        result["error"] = "too few points";
        return result;
    }

    // 加载 track meta
    QDateTime startTime, endTime;
    // 文件自述的升降 (两步路 KML 的 <Document><ExtendedData>): 与 stopTrack 同一条
    //   优先级 —— 有自述用自述, 没有才用下面算出来的平滑值. 用户是拿 App 里那个数
    //   对账的, 两处给两个答案就成了「累计爬升不正确」.
    double declaredGain = std::numeric_limits<double>::quiet_NaN();
    double declaredLoss = std::numeric_limits<double>::quiet_NaN();
    {
        QFile tf(m_storagePath + QString("/track_%1.json").arg(trackId));
        if (tf.open(QIODevice::ReadOnly)) {
            QJsonObject obj = QJsonDocument::fromJson(tf.readAll()).object();
            startTime = QDateTime::fromString(obj["startTime"].toString(), Qt::ISODate);
            endTime = QDateTime::fromString(obj["endTime"].toString(), Qt::ISODate);
            const QJsonValue g = obj.value(QStringLiteral("declaredElevationGainM"));
            const QJsonValue l = obj.value(QStringLiteral("declaredElevationLossM"));
            if (g.isDouble() && g.toDouble() >= 0.0) declaredGain = g.toDouble();
            if (l.isDouble() && l.toDouble() >= 0.0) declaredLoss = l.toDouble();
        }
    }
    if (!endTime.isValid() && points.size() > 0) {
        endTime = QDateTime::fromString(
            points.last().toObject()["timestamp"].toString(), Qt::ISODate);
    }
    if (!startTime.isValid() && points.size() > 0) {
        startTime = QDateTime::fromString(
            points.first().toObject()["timestamp"].toString(), Qt::ISODate);
    }

    // 距离 / 升降 / 最高最低 / 最快 / 精度画像: 一律走 outdoor::track::compute()
    //   (见 TrackMetrics.h 头注释里的对账实测)。这里原来自己写了一遍:
    //     * 1 m 逐点死区 —— 采样间隔是设备给的, 不是地形给的. 实测那条 0.7 s 一点的
    //       藏龙涧 (8505 m / 文件自述爬升 445 m), 死区口径只算出 20 m.
    //     * 单段速度当最快 —— 一个 GPS 抖动除以 0.7 s = 19.2 m/s (69 km/h).
    //   逐点数组 (累计距离 / 时刻 / >=10 s 短窗速度) 也从模块里拿, 下面的分段与休息点
    //   不再自己算第二套.
    const QVector<outdoor::track::Sample> samples = outdoor::track::samplesFromJson(points);
    const outdoor::track::Metrics mt = outdoor::track::compute(samples);
    const double totalDist = mt.distanceM;
    const double gain = std::isfinite(declaredGain) ? declaredGain : mt.gainM;
    const double loss = std::isfinite(declaredLoss) ? declaredLoss : mt.lossM;
    const QVector<qint64>& tsMs = mt.tsAtPointMs;   // -1 = 那一帧没给时刻

    // 时长
    qint64 durationS = 0;
    if (startTime.isValid() && endTime.isValid()) {
        durationS = startTime.secsTo(endTime);
    }
    if (durationS <= 0 && points.size() > 1) {
        if (tsMs.first() >= 0 && tsMs.last() >= 0) {
            durationS = (tsMs.last() - tsMs.first()) / 1000;
        }
    }
    if (durationS < 0) durationS = 0;

    // 平均配速 (分钟/公里)
    double avgPace = 0;
    if (totalDist > 0 && durationS > 0) {
        double distKm = totalDist / 1000.0;
        double durMin = durationS / 60.0;
        avgPace = durMin / distKm;
    }

    // 平均速度
    double avgSpeed = 0;
    if (durationS > 0) {
        avgSpeed = totalDist / durationS;
    }

    // === 分段配速 (每 1km) ===
    //   档位边界按 mt.distAtPoint (累积距离, 单调) 找, 时间用同一批点的时刻 ——
    //   累积距离与时刻都来自 compute(), 与上面的总里程同一口径, 不会出现"分段加起来
    //   比总里程多/少一截"。游标只前进, 12552 点那条也只扫一遍。
    QVariantList splits;
    if (totalDist >= 1000.0) {
        const QVector<double>& cum = mt.distAtPoint;
        int cursor = 0;
        for (int km = 1; km * 1000.0 <= totalDist; ++km) {
            int startIdx = cursor;
            while (startIdx < cum.size() && cum[startIdx] < (km - 1) * 1000.0) ++startIdx;
            int endIdx = startIdx;
            while (endIdx < cum.size() && cum[endIdx] < km * 1000.0) ++endIdx;
            cursor = endIdx;
            if (endIdx >= cum.size()) endIdx = cum.size() - 1;
            if (endIdx > startIdx && tsMs[startIdx] >= 0 && tsMs[endIdx] >= 0) {
                qint64 segSec = (tsMs[endIdx] - tsMs[startIdx]) / 1000;
                double segKm = (cum[endIdx] - cum[startIdx]) / 1000.0;
                QVariantMap split;
                split["km"] = km;
                split["distanceKm"] = segKm;
                split["durationS"] = segSec;
                split["avgPace"] = (segKm > 0) ? (segSec / 60.0) / segKm : 0;
                splits.append(split);
            }
        }
    }

    // === 休息点检测 (>=10 s 短窗速度 < 0.3 m/s, 持续 >= 3 分钟) ===
    //   用 mt.restSpeedMs 而不是单段速度: 站着不动时 GPS 抖动会把单段顶到
    //   0.5~1 m/s, 于是"休息"永远判不出来; 摊到 10 s 窗口才掉回真值。
    //   -1 = 窗口凑不齐 (没有时刻), 这一格不算休息也不算活动, 直接断开这一段。
    QVariantList restPoints;
    int restStart = -1;
    for (int i = 1; i < mt.restSpeedMs.size(); ++i) {
        const bool resting = mt.restSpeedMs[i] >= 0.0 && mt.restSpeedMs[i] < 0.3;
        if (resting) {
            if (restStart < 0) restStart = i;
        } else {
            if (restStart >= 0) {
                appendRestRun(restPoints, samples, tsMs, restStart, i - 1);
                restStart = -1;
            }
        }
    }
    if (restStart >= 0) {
        appendRestRun(restPoints, samples, tsMs, restStart, mt.restSpeedMs.size() - 1);
    }

    // === 卡路里估算 ===
    // 简化公式: METs × 体重 (kg) × 时间 (h)
    // 平地徒步 ~6 METs, 越野/爬升 ~8 METs, 下降/平路快走 ~5 METs
    // 按爬升占比调整
    double calories = 0.0;
    if (durationS > 0 && weightKg > 0) {
        double hours = durationS / 3600.0;
        double totalM = totalDist;
        double climbingRatio = (totalM > 0) ? (gain / totalM) : 0;  // 平均坡度
        double met = 6.0;
        if (climbingRatio > 0.15) met = 8.0;
        else if (climbingRatio > 0.08) met = 7.0;
        if (avgSpeed > 1.7) met += 1.0;  // 较快
        calories = met * weightKg * hours;
    }

    // === 填充结果 ===
    result["ok"] = true;
    result["distanceM"] = totalDist;
    // 时长/平均速度/配速/热量这一族全都派生自"逐点时刻"。文件没给时间 (2026-10-27 #134
    //   之后整条留空, 不再编 addSecs(i*5) 节拍) 时它们一律算不出来, 原来把 0 发出去:
    //     * RouteSummaryPanel 的时长格 formatDuration(0) → "0小时0分钟" (看着像真走了 0 分钟)
    //     * TrackDetailPage 的热量行 → "0 kcal"
    //   现在算不出就整键不写, 与上面的 maxSpeed / maxAlt 同一口径; 界面三处读的都是
    //   `stats.xxx || 0`, 缺键与 0 同样落到"不出现/横线", 不会崩。
    if (durationS > 0) result["durationS"] = durationS;
    if (avgSpeed > 0) result["avgSpeed"] = avgSpeed;          // m/s
    if (avgPace > 0) result["avgPace"] = avgPace;             // min/km
    if (calories > 0) result["calorieKcal"] = calories;
    // 最快: 只发 >=30 s 且位移 >=30 m 的窗口里最大的那个 (口径见 TrackMetrics.h).
    //   凑不出一个窗口 (整条太短 / 没有时刻) 就整键不写 —— 界面两处读数
    //   (RouteSummaryPanel / TrackDetailPage) 都是 stats.maxSpeed || 0 后交给
    //   formatSpeed, 0 打 "-", 于是"测不出"读成一道横线, 而不是把一个 GPS 抖动
    //   除以 0.7 s 报成 69 km/h。见 [[no-fake-readout-rule]]。
    if (mt.hasMaxSpeed) result["maxSpeed"] = mt.maxSpeedMs;
    result["elevationGainM"] = gain;
    result["elevationLossM"] = loss;
    // 一个高程都没有时不写 maxAlt/minAlt —— 否则把 0 当成读数发出去
    if (mt.hasAltitude) {
        result["maxAlt"] = mt.maxAltM;
        result["minAlt"] = mt.minAltM;
    }
    // 界面用这一句决定"爬升/下降/最高/最低"四行要不要出现: 全程没有高程时 gain/loss
    //   会是 0, 而 "累计爬升 0 m" 读起来像"这条路是平的", 那是假读数 (见 hasAltitude).
    result["hasAltitude"] = mt.hasAltitude;
    // 2026-10-26「精度到 1 m」: 这条轨迹的精度画像 (无一个点带 ± 时整项不写)
    if (mt.accuracyCount > 0) {
        result["accuracyAvgM"] = mt.accuracyAvgM;
        result["accuracyBestM"] = mt.accuracyBestM;
        result["accuracyWorstM"] = mt.accuracyWorstM;
        result["accuracyPointCount"] = mt.accuracyCount;
    }
    result["weightKg"] = weightKg;
    result["splits"] = splits;              // 每公里分段
    result["restPoints"] = restPoints;      // 休息点
    result["pointCount"] = (int)points.size();
    return result;
}

QVariantMap MapService::getTrackProfile(const QString& trackId) {
    QVariantMap result;
    result["ok"] = false;

    QFile pf(m_storagePath + QString("/track_%1_points.json").arg(trackId));
    if (!pf.open(QIODevice::ReadOnly)) {
        result["error"] = "points file not found";
        return result;
    }
    QJsonDocument pdoc = QJsonDocument::fromJson(pf.readAll());
    pf.close();
    if (!pdoc.isArray()) {
        result["error"] = "not array";
        return result;
    }
    QJsonArray points = pdoc.array();
    if (points.size() < 2) {
        result["error"] = "too few points";
        return result;
    }

    // 剖面三条序列与 getTrackStats / stopTrack 同一份口径 (见 TrackMetrics.h):
    //   * 横轴的累计距离取 mt.distAtPoint —— 曲线末点必须就是"里程"那个数,
    //     原来这里自己再 haversineM 累加一遍, 两处只在大数字上有细微差, 但对账时说不清。
    //   * 速度取 >=30 s 位移窗 (mt.movingSpeedMs), 它的峰值就是 stats.maxSpeed:
    //     画逐段速度的话, 0.7 s 一点的导入文件里曲线是一排抖动尖峰, 峰值标着 19 m/s
    //     而"最快"读数说 2.6 —— 用户看到的正是 A44 报的"最快速度不正确"。
    //     窗口凑不齐的点 (末尾最后 30 s / 全程没有时刻) 画 0, 与逐段速度缺时刻时的
    //     老行为一致。
    const QVector<outdoor::track::Sample> samples = outdoor::track::samplesFromJson(points);
    const outdoor::track::Metrics mt = outdoor::track::compute(samples);

    QVariantList distances;
    QVariantList elevations;
    QVariantList speeds;
    QVariantList timestamps;
    distances.reserve(points.size());
    elevations.reserve(points.size());
    speeds.reserve(points.size());
    timestamps.reserve(points.size());

    for (int i = 0; i < samples.size(); ++i) {
        distances.append(mt.distAtPoint[i]);
        // 没给高程的点填 0 (改前行为): 整条都没有高程时页面按 hasAltitude 把这张图
        //   整块藏掉, 所以这条只影响"个别点缺高程"的线, 不是假读数的主通道.
        elevations.append(std::isfinite(samples[i].alt) ? samples[i].alt : 0.0);
        speeds.append(mt.movingSpeedMs[i] >= 0.0 ? mt.movingSpeedMs[i] : 0.0);
        timestamps.append(mt.tsAtPointMs[i] >= 0
                          ? QDateTime::fromMSecsSinceEpoch(mt.tsAtPointMs[i]).toString(Qt::ISODate)
                          : QString());
    }

    result["ok"] = true;
    result["distances"] = distances;     // m
    result["elevations"] = elevations;   // m
    result["speeds"] = speeds;           // m/s
    result["timestamps"] = timestamps;
    result["pointCount"] = (int)points.size();
    return result;
}

} // namespace outdoor

