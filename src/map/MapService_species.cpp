/**
 * @file MapService_species.cpp
 * @brief MapService::species + 通用 stats + 轨迹分析 (2026-09-21 阶段 L5.4 拆分)
 *
 * 从 MapService.cpp 拆出, 包含:
 *   - addSpeciesLocation / getSpeciesLocations / getSpeciesLocationsInBounds
 *   - getStats / getAltitudeStats / cleanupOldData
 *   - getTrackStats / getTrackProfile (P1 轨迹详细分析)
 *   - haversineM 匿名 namespace 帮手 (被 getTrackStats 用)
 *
 * 注: formatDistance/formatDuration/formatElevation + generateId + recomputeTrackStats
 *     在 MapService.cpp (core) 定义.
 */

#include "MapService.h"
#include "../core/Logger.h"
#include "../core/Result.h"
#include "../core/ServiceErrors.h"
#include "../core/internal/QmlResultBridge.h"

#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDateTime>
#include <cmath>
#include <algorithm>

namespace outdoor {

QVariantMap MapService::addSpeciesLocation(const QString& speciesId,
                                              const QString& speciesName,
                                              const QString& category,
                                              double lat, double lon,
                                              double altitude,
                                              const QString& note) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::addSpeciesLocation";

    qint64 id = QDateTime::currentMSecsSinceEpoch();
    QJsonObject obj;
    obj["id"] = QString::number(id);
    obj["speciesId"] = speciesId;
    obj["speciesName"] = speciesName;
    obj["speciesCategory"] = category;
    obj["lat"] = lat;
    obj["lon"] = lon;
    obj["altitude"] = altitude;
    obj["note"] = note;
    obj["takenAt"] = QDateTime::currentDateTime().toString(Qt::ISODate);
    // 2026-09-15: 写 dangerLevel 字段 - 暂时固定 0, MapPage 端用 speciesId 反查
    // (后续如需在此处查询, 通过 ServiceRegistry 拿 SpeciesService)
    obj["dangerLevel"] = 0;

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
    // Haversine 距离 (m), 已有 QGeoCoordinate.distanceTo 但不导出
    inline double haversineM(double lat1, double lon1, double lat2, double lon2) {
        constexpr double R = 6371000.0;  // 地球半径 m
        constexpr double deg2rad = M_PI / 180.0;
        double dLat = (lat2 - lat1) * deg2rad;
        double dLon = (lon2 - lon1) * deg2rad;
        double a = std::sin(dLat/2) * std::sin(dLat/2)
                 + std::cos(lat1*deg2rad) * std::cos(lat2*deg2rad)
                 * std::sin(dLon/2) * std::sin(dLon/2);
        return 2 * R * std::atan2(std::sqrt(a), std::sqrt(1-a));
    }
}

QVariantMap MapService::getTrackStats(const QString& trackId, double weightKg) {
    QVariantMap result;
    result["ok"] = false;
    result["error"] = "";

    if (trackId.isEmpty()) {
        result["error"] = "empty trackId";
        return result;
    }

    // 加载点
    QFile pf(m_storagePath + QString("/track_%1_points.json").arg(trackId));
    if (!pf.open(QIODevice::ReadOnly)) {
        result["error"] = "track points file not found";
        return result;
    }
    QJsonDocument pdoc = QJsonDocument::fromJson(pf.readAll());
    pf.close();
    if (!pdoc.isArray()) {
        result["error"] = "points not array";
        return result;
    }
    QJsonArray points = pdoc.array();
    if (points.size() < 2) {
        result["error"] = "too few points";
        return result;
    }

    // 加载 track meta
    QDateTime startTime, endTime;
    {
        QFile tf(m_storagePath + QString("/track_%1.json").arg(trackId));
        if (tf.open(QIODevice::ReadOnly)) {
            QJsonObject obj = QJsonDocument::fromJson(tf.readAll()).object();
            startTime = QDateTime::fromString(obj["startTime"].toString(), Qt::ISODate);
            endTime = QDateTime::fromString(obj["endTime"].toString(), Qt::ISODate);
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

    // 第一遍: 距离/海拔/速度
    double totalDist = 0;
    double gain = 0, loss = 0;
    double maxAlt = -1e9, minAlt = 1e9;
    double maxSpeed = 0;
    QVector<double> distAtPoint;  // 累计距离 (m)
    QVector<double> speedAtPoint; // 速度 (m/s)
    QVector<QDateTime> tsAtPoint;
    QVector<QGeoCoordinate> coords;

    distAtPoint.reserve(points.size());
    speedAtPoint.reserve(points.size());
    tsAtPoint.reserve(points.size());
    coords.reserve(points.size());

    double prevAlt = 0;
    bool hasPrev = false;
    for (int i = 0; i < points.size(); ++i) {
        QJsonObject p = points[i].toObject();
        double lat = p["lat"].toDouble();
        double lon = p["lon"].toDouble();
        double alt = p["elevation"].toDouble();
        QDateTime ts = QDateTime::fromString(p["timestamp"].toString(), Qt::ISODate);

        QGeoCoordinate c(lat, lon);
        coords.append(c);
        tsAtPoint.append(ts);

        if (hasPrev) {
            double segDist = haversineM(
                coords[i-1].latitude(), coords[i-1].longitude(), lat, lon);
            totalDist += segDist;
            distAtPoint.append(totalDist);

            // 海拔增减 (用滑动平均抗 GPS 抖动, 简单 1m 阈值)
            double dAlt = alt - prevAlt;
            if (dAlt > 1.0) gain += dAlt;
            else if (dAlt < -1.0) loss += -dAlt;

            // 速度 = 段距离 / 段时间 (m/s)
            double speed = 0;
            if (tsAtPoint[i-1].isValid() && ts.isValid()) {
                qint64 dtMs = tsAtPoint[i-1].msecsTo(ts);
                if (dtMs > 0) {
                    speed = segDist / (dtMs / 1000.0);
                }
            }
            speedAtPoint.append(speed);
            if (speed > maxSpeed) maxSpeed = speed;
        } else {
            distAtPoint.append(0);
            speedAtPoint.append(0);
        }
        maxAlt = std::max(maxAlt, alt);
        minAlt = std::min(minAlt, alt);
        prevAlt = alt;
        hasPrev = true;
    }

    // 时长
    qint64 durationS = 0;
    if (startTime.isValid() && endTime.isValid()) {
        durationS = startTime.secsTo(endTime);
    }
    if (durationS <= 0 && points.size() > 1) {
        if (tsAtPoint.first().isValid() && tsAtPoint.last().isValid()) {
            durationS = tsAtPoint.first().secsTo(tsAtPoint.last());
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
    QVariantList splits;
    if (totalDist >= 1000.0) {
        int numSplits = int(totalDist / 1000.0);
        for (int km = 1; km <= numSplits; ++km) {
            double targetDist = km * 1000.0;
            // 找累积距离 >= targetDist 的最小索引
            int endIdx = -1;
            for (int i = 0; i < distAtPoint.size(); ++i) {
                if (distAtPoint[i] >= targetDist) { endIdx = i; break; }
            }
            if (endIdx < 0) endIdx = distAtPoint.size() - 1;
            int startIdx = -1;
            double prevTarget = (km - 1) * 1000.0;
            for (int i = 0; i < distAtPoint.size(); ++i) {
                if (distAtPoint[i] >= prevTarget) { startIdx = i; break; }
            }
            if (startIdx < 0) startIdx = 0;
            if (endIdx > startIdx && tsAtPoint[startIdx].isValid() && tsAtPoint[endIdx].isValid()) {
                qint64 segSec = tsAtPoint[startIdx].secsTo(tsAtPoint[endIdx]);
                double segKm = (distAtPoint[endIdx] - distAtPoint[startIdx]) / 1000.0;
                double segPace = (segKm > 0) ? (segSec / 60.0) / segKm : 0;
                QVariantMap split;
                split["km"] = km;
                split["distanceKm"] = segKm;
                split["durationS"] = segSec;
                split["avgPace"] = segPace;
                splits.append(split);
            }
        }
    }

    // === 休息点检测 (速度 < 0.3 m/s 持续 >= 3 分钟) ===
    QVariantList restPoints;
    int restStart = -1;
    for (int i = 1; i < speedAtPoint.size(); ++i) {
        if (speedAtPoint[i] < 0.3) {
            if (restStart < 0) restStart = i;
        } else {
            if (restStart >= 0) {
                int endIdx = i - 1;
                if (tsAtPoint[restStart].isValid() && tsAtPoint[endIdx].isValid()) {
                    qint64 restSec = tsAtPoint[restStart].secsTo(tsAtPoint[endIdx]);
                    if (restSec >= 180) {  // >= 3 分钟
                        QVariantMap rest;
                        rest["lat"] = coords[(restStart+endIdx)/2].latitude();
                        rest["lon"] = coords[(restStart+endIdx)/2].longitude();
                        rest["durationS"] = restSec;
                        rest["startIdx"] = restStart;
                        rest["endIdx"] = endIdx;
                        restPoints.append(rest);
                    }
                }
                restStart = -1;
            }
        }
    }
    // 尾部休息
    if (restStart >= 0 && restStart < speedAtPoint.size() - 1) {
        int endIdx = speedAtPoint.size() - 1;
        if (tsAtPoint[restStart].isValid() && tsAtPoint[endIdx].isValid()) {
            qint64 restSec = tsAtPoint[restStart].secsTo(tsAtPoint[endIdx]);
            if (restSec >= 180) {
                QVariantMap rest;
                rest["lat"] = coords[(restStart+endIdx)/2].latitude();
                rest["lon"] = coords[(restStart+endIdx)/2].longitude();
                rest["durationS"] = restSec;
                rest["startIdx"] = restStart;
                rest["endIdx"] = endIdx;
                restPoints.append(rest);
            }
        }
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
    result["durationS"] = durationS;
    result["avgSpeed"] = avgSpeed;          // m/s
    result["maxSpeed"] = maxSpeed;          // m/s
    result["avgPace"] = avgPace;            // min/km
    result["elevationGainM"] = gain;
    result["elevationLossM"] = loss;
    result["maxAlt"] = maxAlt;
    result["minAlt"] = minAlt;
    result["calorieKcal"] = calories;
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

    QVariantList distances;
    QVariantList elevations;
    QVariantList speeds;
    QVariantList timestamps;

    double cumDist = 0;
    bool hasPrev = false;
    QGeoCoordinate prev;
    QDateTime prevTs;

    for (int i = 0; i < points.size(); ++i) {
        QJsonObject p = points[i].toObject();
        double lat = p["lat"].toDouble();
        double lon = p["lon"].toDouble();
        double alt = p["elevation"].toDouble();
        QDateTime ts = QDateTime::fromString(p["timestamp"].toString(), Qt::ISODate);
        QGeoCoordinate c(lat, lon);

        if (hasPrev) {
            cumDist += haversineM(prev.latitude(), prev.longitude(), lat, lon);
            double speed = 0;
            if (prevTs.isValid() && ts.isValid()) {
                qint64 dtMs = prevTs.msecsTo(ts);
                if (dtMs > 0) speed = cumDist - distances.last().toDouble() > 0
                                    ? (cumDist - distances.last().toDouble()) / (dtMs/1000.0)
                                    : 0;
            }
            speeds.append(speed);
        } else {
            speeds.append(0);
        }
        distances.append(cumDist);
        elevations.append(alt);
        timestamps.append(ts.toString(Qt::ISODate));
        prev = c;
        prevTs = ts;
        hasPrev = true;
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

