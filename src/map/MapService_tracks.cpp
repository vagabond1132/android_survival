/**
 * @file MapService_tracks.cpp
 * @brief MapService::track 相关方法 (2026-09-21 阶段 L5.4 拆分)
 *
 * 从 MapService.cpp 拆出, 包含:
 *   - startTrack / addTrackPoint / stopTrack
 *   - getAllTracks / getTrackById / deleteTrack / getTrackPoints / getTrackElevations
 *   - getFrequencyOptions / getFrequencyLabel / getDefaultFrequency
 *   - importGpx / importKml / importCsv
 *   - exportTrackAsGpx / exportTrackAsKml / exportAllSpeciesAsKml
 */

#include "MapService.h"
#include "../core/Logger.h"
#include "../core/PathService.h"
#include "../core/Result.h"
#include "../core/ServiceErrors.h"
#include "../core/internal/QmlResultBridge.h"

#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QXmlStreamReader>
#include <QXmlStreamWriter>
#include <QUuid>
#include <QDateTime>
#include <QTextStream>
#include <algorithm>

namespace outdoor {

QVariantMap MapService::startTrack(const QString& name, int frequencySeconds) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::startTrack";

    // 2026-10-16: 名称空白 → InvalidArgument, 之前会静默落一个空 track_*.json
    if (name.trimmed().isEmpty()) {
        return toQVariant(Err<QString>(
            ServiceErrorCode::InvalidArgument,
            QStringLiteral("轨迹名称不能为空"), ctx));
    }

    QString id = generateId();
    Track track;
    track.id = id;
    track.name = name;
    track.startTime = QDateTime::currentDateTime();
    track.source = "recorded";

    // 验证频率（2/5/10/20/30）
    int validFreqs[] = {2, 5, 10, 20, 30};
    bool valid = false;
    for (int f : validFreqs) {
        if (f == frequencySeconds) { valid = true; break; }
    }
    if (!valid) frequencySeconds = 5;  // 默认 5 秒
    track.frequency = static_cast<TrackFrequency>(frequencySeconds);

    // 保存初始轨迹
    QJsonObject obj;
    obj["id"] = track.id;
    obj["name"] = track.name;
    obj["startTime"] = track.startTime.toString(Qt::ISODate);
    obj["endTime"] = "";
    obj["source"] = "recorded";
    obj["frequency"] = frequencySeconds;

    QFile file(m_storagePath + QString("/track_%1.json").arg(id));
    if (!file.open(QIODevice::WriteOnly)) {
        const QString err = file.errorString();
        Logger::error(QString("%1: %2").arg(ctx, err));
        return toQVariant(Err<QString>(
            ServiceErrorCode::IoError,
            QStringLiteral("无法创建轨迹文件: %1").arg(err), ctx));
    }
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    file.close();

    emit trackStarted(id);
    Logger::info(QString("Track started: %1 (frequency: %2s)").arg(id).arg(frequencySeconds));
    return toQVariant(Ok(id));
}

// 2026-09-21: 阶段 L3.4 - addTrackPoint 切 Result<bool>
QVariantMap MapService::addTrackPoint(const QString& trackId, double lat, double lon,
                                       double elevation) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::addTrackPoint";

    // 2026-10-16: trackId 必须指向已 startTrack/importGpx 建好的 track_<id>.json,
    //   否则之前会静默写一个孤儿 points 文件, stopTrack 拿不到 track meta,
    //   getTrackStats 返回 "too few points".
    if (!QFileInfo::exists(m_storagePath + QString("/track_%1.json").arg(trackId))) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("轨迹不存在: %1").arg(trackId), ctx));
    }

    QString pointsFile = m_storagePath + QString("/track_%1_points.json").arg(trackId);
    QJsonArray points;
    QFile file(pointsFile);
    if (file.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        file.close();
        if (doc.isArray()) {
            points = doc.array();
        }
    }

    QJsonObject point;
    point["seq"] = points.size();
    point["lat"] = lat;
    point["lon"] = lon;
    point["elevation"] = elevation;
    point["timestamp"] = QDateTime::currentDateTime().toString(Qt::ISODate);
    points.append(point);

    if (!file.open(QIODevice::WriteOnly)) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                      QStringLiteral("无法写入轨迹点文件"), ctx));
    }
    file.write(QJsonDocument(points).toJson(QJsonDocument::Indented));
    file.close();

    emit trackPointAdded(trackId, lat, lon);
    return toQVariant(Ok(true));
}

QVariantMap MapService::stopTrack(const QString& trackId) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::stopTrack";

    QString trackFile = m_storagePath + QString("/track_%1.json").arg(trackId);
    QFile file(trackFile);
    if (!file.open(QIODevice::ReadOnly)) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("轨迹文件不存在"), ctx));
    }
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isObject()) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                      QStringLiteral("轨迹文件损坏"), ctx));
    }

    QJsonObject obj = doc.object();
    obj["endTime"] = QDateTime::currentDateTime().toString(Qt::ISODate);

    // 重新计算统计
    QFile pf(m_storagePath + QString("/track_%1_points.json").arg(trackId));
    if (pf.open(QIODevice::ReadOnly)) {
        QJsonDocument pdoc = QJsonDocument::fromJson(pf.readAll());
        pf.close();
        QJsonArray points = pdoc.array();
        obj["pointCount"] = points.size();

        // 计算距离和海拔
        double totalDist = 0;
        double maxAlt = -1e9, minAlt = 1e9;
        double gain = 0, loss = 0;
        QGeoCoordinate prev;
        bool hasPrev = false;
        double prevAlt = 0;

        for (const auto& v : points) {
            QJsonObject p = v.toObject();
            QGeoCoordinate cur(p["lat"].toDouble(), p["lon"].toDouble());
            double alt = p["elevation"].toDouble();

            if (hasPrev) {
                totalDist += prev.distanceTo(cur);
                if (alt > prevAlt) gain += (alt - prevAlt);
                else loss += (prevAlt - alt);
            }

            maxAlt = std::max(maxAlt, alt);
            minAlt = std::min(minAlt, alt);
            prev = cur;
            prevAlt = alt;
            hasPrev = true;
        }

        obj["totalDistanceM"] = totalDist;
        obj["elevationGainM"] = gain;
        obj["elevationLossM"] = loss;
        obj["maxAltitudeM"] = maxAlt;
        obj["minAltitudeM"] = minAlt;
    }

    if (!file.open(QIODevice::WriteOnly)) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                      QStringLiteral("无法写入轨迹文件"), ctx));
    }
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    file.close();

    emit trackStopped(trackId);
    emit dataChanged();
    Logger::info("Track stopped: " + trackId);
    return toQVariant(Ok(true));
}

QVariantList MapService::getAllTracks() const {
    QVariantList list;
    QDir dir(m_storagePath);
    QStringList files = dir.entryList({"track_*.json"}, QDir::Files);
    for (const QString& f : files) {
        if (f.contains("_points")) continue;
        QFile file(m_storagePath + "/" + f);
        if (!file.open(QIODevice::ReadOnly)) continue;
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        file.close();
        if (doc.isObject()) {
            QJsonObject obj = doc.object();
            QVariantMap m;
            m["id"] = obj["id"].toString();
            m["name"] = obj["name"].toString();
            m["startTime"] = obj["startTime"].toString();
            m["endTime"] = obj["endTime"].toString();
            m["source"] = obj["source"].toString();
            m["totalDistanceM"] = obj["totalDistanceM"].toDouble();
            m["elevationGainM"] = obj["elevationGainM"].toDouble();
            m["maxAltitudeM"] = obj["maxAltitudeM"].toDouble();
            m["minAltitudeM"] = obj["minAltitudeM"].toDouble();
            m["pointCount"] = obj["pointCount"].toInt();
            list.append(m);
        }
    }
    return list;
}

// 2026-10-09: 契约统一 - getTrackById 切 Result {ok, value, error}.
//   与 getTrackStats/getTrackProfile/deleteTrack/importXxx 一致, 供 QML 统一判 ok.
QVariantMap MapService::getTrackById(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::getTrackById";

    QFile file(m_storagePath + QString("/track_%1.json").arg(id));
    if (!file.open(QIODevice::ReadOnly)) {
        return toQVariant(Err<QVariantMap>(ServiceErrorCode::NotFound,
                                            QStringLiteral("轨迹不存在"), ctx));
    }
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isObject()) {
        return toQVariant(Err<QVariantMap>(ServiceErrorCode::InvalidArgument,
                                            QStringLiteral("轨迹文件损坏"), ctx));
    }
    return toQVariant(Ok(doc.object().toVariantMap()));
}

// 2026-09-21: 阶段 L3.4 - deleteTrack 切 Result<bool>
QVariantMap MapService::deleteTrack(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::deleteTrack";

    QFile t(m_storagePath + QString("/track_%1.json").arg(id));
    QFile p(m_storagePath + QString("/track_%1_points.json").arg(id));
    bool ok = t.remove() && p.remove();
    if (ok) {
        emit dataChanged();
        return toQVariant(Ok(true));
    }
    return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                  QStringLiteral("轨迹文件删除失败"), ctx));
}

QList<QGeoCoordinate> MapService::getTrackPoints(const QString& trackId) {
    QList<QGeoCoordinate> result;
    QFile file(m_storagePath + QString("/track_%1_points.json").arg(trackId));
    if (!file.open(QIODevice::ReadOnly)) return result;
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isArray()) return result;

    for (const auto& v : doc.array()) {
        QJsonObject p = v.toObject();
        result.append(QGeoCoordinate(p["lat"].toDouble(), p["lon"].toDouble()));
    }
    return result;
}

QVariantList MapService::getTrackElevations(const QString& trackId) {
    QVariantList result;
    QFile file(m_storagePath + QString("/track_%1_points.json").arg(trackId));
    if (!file.open(QIODevice::ReadOnly)) return result;
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isArray()) return result;

    for (const auto& v : doc.array()) {
        QJsonObject p = v.toObject();
        QVariantMap m;
        m["lat"] = p["lat"].toDouble();
        m["lon"] = p["lon"].toDouble();
        m["elevation"] = p["elevation"].toDouble();
        m["timestamp"] = p["timestamp"].toString();
        result.append(m);
    }
    return result;
}

QVariantList MapService::getFrequencyOptions() {
    QVariantList options;
    // 5 个频率选项（用户确认）
    struct FreqOption {
        int seconds;
        QString label;
        QString description;
    };
    FreqOption opts[] = {
        {2, "2 秒", "高精度，耗电大"},
        {5, "5 秒", "推荐平衡"},
        {10, "10 秒", "省电，标准"},
        {20, "20 秒", "长距离省电"},
        {30, "30 秒", "极省电，粗略"}
    };
    for (const auto& opt : opts) {
        QVariantMap m;
        m["seconds"] = opt.seconds;
        m["label"] = opt.label;
        m["description"] = opt.description;
        m["isDefault"] = (opt.seconds == 5);
        options.append(m);
    }
    return options;
}

QString MapService::getFrequencyLabel(int seconds) {
    switch (seconds) {
        case 2: return "2 秒（高精度）";
        case 5: return "5 秒（推荐）";
        case 10: return "10 秒（标准）";
        case 20: return "20 秒（省电）";
        case 30: return "30 秒（粗略）";
        default: return QString::number(seconds) + " 秒";
    }
}

int MapService::getDefaultFrequency() const {
    return 5;
}

QVariantMap MapService::importGpx(const QString& filePath) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::importGpx";

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        const QString err = file.errorString();
        emit warningTriggered("无法打开文件: " + filePath);
        return toQVariant(Err<QString>(
            ServiceErrorCode::IoError,
            QStringLiteral("无法打开 GPX 文件: %1").arg(err), ctx));
    }

    QXmlStreamReader xml(&file);
    QString trackId;
    QString name;
    QDateTime trackStartTime;
    QDateTime pointTime;
    // 2026-09-15: 修复 - 用栈式解析, 保证 <ele>/<time> 与 <trkpt> 一一对应
    QList<QGeoCoordinate> points;
    QList<double> elevations;
    QList<QDateTime> timestamps;
    // 当前正在读 trkpt (true) 还是 rtept (true) 内的子元素
    bool inTrackPoint = false;
    bool inRoutePoint = false;
    // 临时变量, 收集当前 trkpt 的字段
    QGeoCoordinate currentPoint;
    double currentEle = 0;
    bool hasCurrentEle = false;
    QDateTime currentTime;
    bool hasCurrentTime = false;
    bool hasAnyPoint = false;

    while (!xml.atEnd()) {
        xml.readNext();
        if (xml.isStartElement()) {
            QString nameTag = xml.name().toString();
            if (nameTag == "trk") {
                trackId = generateId();
                name = "导入轨迹";
            } else if (nameTag == "name") {
                // 2026-09-15: 修复 - 移除 trackId.isEmpty() 条件, 让 trk 内部的 name 也生效
                QString txt = xml.readElementText().trimmed();
                if (txt.length() > 0) {
                    name = txt;
                }
            } else if (nameTag == "time" && !inTrackPoint && !inRoutePoint) {
                // 顶层 <time> 作为轨迹默认起始时间
                trackStartTime = QDateTime::fromString(xml.readElementText().trimmed(), Qt::ISODate);
            } else if (nameTag == "trkpt" || nameTag == "rtept") {
                // 准备接收当前点的子元素
                inTrackPoint = (nameTag == "trkpt");
                inRoutePoint = (nameTag == "rtept");
                double lat = xml.attributes().value("lat").toDouble();
                double lon = xml.attributes().value("lon").toDouble();
                currentPoint = QGeoCoordinate(lat, lon);
                currentEle = 0;
                hasCurrentEle = false;
                currentTime = QDateTime();
                hasCurrentTime = false;
            } else if (nameTag == "ele" && (inTrackPoint || inRoutePoint)) {
                currentEle = xml.readElementText().toDouble();
                hasCurrentEle = true;
            } else if (nameTag == "time" && (inTrackPoint || inRoutePoint)) {
                currentTime = QDateTime::fromString(xml.readElementText().trimmed(), Qt::ISODate);
                hasCurrentTime = true;
            }
        } else if (xml.isEndElement()) {
            QString endName = xml.name().toString();
            if (endName == "trkpt" || endName == "rtept") {
                // 一个点结束, 入栈
                points.append(currentPoint);
                elevations.append(hasCurrentEle ? currentEle : 0);
                timestamps.append(hasCurrentTime ? currentTime : QDateTime());
                hasAnyPoint = true;
                if (endName == "trkpt") inTrackPoint = false;
                if (endName == "rtept") inRoutePoint = false;
            }
        }
    }
    file.close();

    if (!hasAnyPoint || points.isEmpty()) {
        emit warningTriggered("GPX 文件无效或无轨迹点");
        return toQVariant(Err<QString>(
            ServiceErrorCode::ParseError,
            QStringLiteral("GPX 文件无效或无轨迹点"), ctx));
    }

    // 起始时间: 优先用顶层 <time>, 其次用第一个有时间的点, 再次用当前时间
    QDateTime startTime = trackStartTime;
    if (!startTime.isValid()) {
        for (int i = 0; i < timestamps.size(); i++) {
            if (timestamps[i].isValid()) { startTime = timestamps[i]; break; }
        }
    }
    if (!startTime.isValid()) {
        startTime = QDateTime::currentDateTime();
    }
    // 填补没有时间的点
    for (int i = 0; i < timestamps.size(); i++) {
        if (!timestamps[i].isValid()) {
            timestamps[i] = startTime.addSecs(i * 5);
        }
    }
    // 结束时间 = 最后一个点的时间
    QDateTime endTime = timestamps.last().isValid() ? timestamps.last() : startTime;

    // 创建轨迹
    Track track;
    track.id = trackId;
    track.name = name;
    track.startTime = startTime;
    track.endTime = endTime;
    track.points = points;
    track.elevations = elevations;
    track.source = "imported";
    track.originalFormat = "gpx";

    // 写入文件
    QString pointsFile = m_storagePath + QString("/track_%1_points.json").arg(trackId);
    QJsonArray pointsArr;
    for (int i = 0; i < points.size(); ++i) {
        QJsonObject p;
        p["seq"] = i;
        p["lat"] = points[i].latitude();
        p["lon"] = points[i].longitude();
        if (i < elevations.size()) {
            p["elevation"] = elevations[i];
        }
        p["timestamp"] = timestamps[i].toString(Qt::ISODate);
        pointsArr.append(p);
    }
    QFile pf(pointsFile);
    if (pf.open(QIODevice::WriteOnly)) {
        pf.write(QJsonDocument(pointsArr).toJson(QJsonDocument::Indented));
        pf.close();
    }

    // 2026-10-16: 之前直接调 stopTrack, 但 track_<id>.json 还没落盘,
    //   stopTrack NotFound 分支返回, 名称/统计永远丢失; 现补上创建 track json 的步骤,
    //   让 stopTrack 正常读到 meta 再计算 distance/elevation gain.
    {
        QJsonObject obj;
        obj["id"] = trackId;
        obj["name"] = name;
        obj["startTime"] = startTime.toString(Qt::ISODate);
        obj["endTime"] = "";
        obj["source"] = "imported";
        obj["originalFormat"] = "gpx";
        obj["frequency"] = 5;
        QFile tf(m_storagePath + QString("/track_%1.json").arg(trackId));
        if (tf.open(QIODevice::WriteOnly)) {
            tf.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
            tf.close();
        }
    }

    // 停止轨迹（计算统计）
    stopTrack(trackId);

    // 更新名称
    QFile tf(m_storagePath + QString("/track_%1.json").arg(trackId));
    if (tf.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(tf.readAll());
        tf.close();
        QJsonObject obj = doc.object();
        obj["name"] = name;
        obj["source"] = "imported";
        obj["originalFormat"] = "gpx";
        if (tf.open(QIODevice::WriteOnly)) {
            tf.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
            tf.close();
        }
    }

    emit trackImported(trackId, points.size());
    emit dataChanged();
    Logger::info(QString("GPX imported: %1 points, name='%2'").arg(points.size()).arg(name));
    return toQVariant(Ok(trackId));
}

QVariantMap MapService::importKml(const QString& filePath) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::importKml";

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        emit warningTriggered("无法打开文件");
        return toQVariant(Err<QString>(
            ServiceErrorCode::IoError,
            QStringLiteral("无法打开 KML 文件: %1").arg(filePath), ctx));
    }

    QXmlStreamReader xml(&file);
    QString trackId;
    QString name = "KML 导入";
    QDateTime trackStartTime;
    QDateTime pointTime;
    QList<QGeoCoordinate> points;
    QList<double> elevations;
    QList<QDateTime> timestamps;
    // 2026-09-15: 修复 - KML 通常结构: <Placemark><name>轨迹名</name><LineString><coordinates>...
    // <TimeSpan><begin>...</begin></TimeSpan> 是时间
    bool inPlacemark = false;
    bool inLineString = false;
    bool inTimeSpan = false;
    QGeoCoordinate currentPoint;
    // 2026-09-21: 删 unused 警告. 之前 currentEle/hasCurrentEle/currentTime/
    //   hasCurrentTime/hasAnyPoint 是计划做 per-point 跟踪时声明的, 后来改用
    //   elevations/timestamps 列表追加, 这 4 个 var 再也没读过. 编译 -Werror 模式下
    //   会变成 error, 先清理掉. hasAnyPoint 与下方 points.isEmpty() 重复, 一并删.

    while (!xml.atEnd()) {
        xml.readNext();
        if (xml.isStartElement()) {
            QString nameTag = xml.name().toString();
            if (nameTag == "Placemark") {
                inPlacemark = true;
            } else if (nameTag == "name" && inPlacemark) {
                // 2026-09-15: 修复 - 读 Placemark 内的 <name>
                QString txt = xml.readElementText().trimmed();
                if (txt.length() > 0) name = txt;
            } else if (nameTag == "TimeSpan") {
                inTimeSpan = true;
            } else if (nameTag == "begin" && inTimeSpan) {
                trackStartTime = QDateTime::fromString(xml.readElementText().trimmed(), Qt::ISODate);
            } else if (nameTag == "LineString") {
                inLineString = true;
            } else if (nameTag == "coordinates" && inLineString) {
                QString text = xml.readElementText();
                // KML 坐标是 "lon,lat,alt" 用空格分隔多个点; 但 alt 字段可能没有 (lon,lat)
                QStringList coords = text.split(QRegularExpression("[\\s]+"), Qt::SkipEmptyParts);
                for (const QString& c : coords) {
                    QStringList parts = c.split(',');
                    if (parts.size() >= 2) {
                        double lon = parts[0].toDouble();
                        double lat = parts[1].toDouble();
                        double alt = parts.size() >= 3 ? parts[2].toDouble() : 0;
                        points.append(QGeoCoordinate(lat, lon));
                        elevations.append(alt);
                        timestamps.append(QDateTime());  // KML 默认无逐点时间
                    }
                }
            } else if (nameTag == "Point" && inPlacemark) {
                // 单点 Placemark: 解析 <coordinates>
                // (不进入 LineString 路径)
            }
        } else if (xml.isEndElement()) {
            QString endName = xml.name().toString();
            if (endName == "Placemark") inPlacemark = false;
            else if (endName == "TimeSpan") inTimeSpan = false;
            else if (endName == "LineString") inLineString = false;
        }
    }
    file.close();

    if (points.isEmpty()) {
        emit warningTriggered("KML 无轨迹点");
        return toQVariant(Err<QString>(
            ServiceErrorCode::ParseError,
            QStringLiteral("KML 无轨迹点"), ctx));
    }

    // 起始时间: 优先用 <TimeSpan><begin>, 否则用当前时间
    QDateTime startTime = trackStartTime;
    if (!startTime.isValid()) {
        startTime = QDateTime::currentDateTime();
    }
    // 填补无时间点
    for (int i = 0; i < timestamps.size(); i++) {
        if (!timestamps[i].isValid()) {
            timestamps[i] = startTime.addSecs(i * 5);
        }
    }
    QDateTime endTime = timestamps.last().isValid() ? timestamps.last() : startTime;

    trackId = generateId();
    QString pointsFile = m_storagePath + QString("/track_%1_points.json").arg(trackId);
    QJsonArray pointsArr;
    for (int i = 0; i < points.size(); ++i) {
        QJsonObject p;
        p["seq"] = i;
        p["lat"] = points[i].latitude();
        p["lon"] = points[i].longitude();
        p["elevation"] = i < elevations.size() ? elevations[i] : 0;
        p["timestamp"] = timestamps[i].toString(Qt::ISODate);
        pointsArr.append(p);
    }
    QFile pf(pointsFile);
    if (pf.open(QIODevice::WriteOnly)) {
        pf.write(QJsonDocument(pointsArr).toJson(QJsonDocument::Indented));
        pf.close();
    }

    stopTrack(trackId);

    QFile tf(m_storagePath + QString("/track_%1.json").arg(trackId));
    if (tf.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(tf.readAll());
        tf.close();
        QJsonObject obj = doc.object();
        obj["name"] = name;
        obj["source"] = "imported";
        obj["originalFormat"] = "kml";
        if (tf.open(QIODevice::WriteOnly)) {
            tf.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
            tf.close();
        }
    }

    emit trackImported(trackId, points.size());
    emit dataChanged();
    Logger::info(QString("KML imported: %1 points, name='%2'").arg(points.size()).arg(name));
    return toQVariant(Ok(trackId));
}

QVariantMap MapService::importCsv(const QString& filePath) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::importCsv";

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        emit warningTriggered("无法打开文件");
        return toQVariant(Err<QString>(
            ServiceErrorCode::IoError,
            QStringLiteral("无法打开 CSV 文件: %1").arg(filePath), ctx));
    }

    QList<QGeoCoordinate> points;
    QList<double> elevations;
    bool firstLine = true;
    int latCol = -1, lonCol = -1, altCol = -1;

    QTextStream in(&file);
    while (!in.atEnd()) {
        QString line = in.readLine();
        QStringList parts = line.split(',');

        if (firstLine) {
            // 解析表头
            for (int i = 0; i < parts.size(); ++i) {
                QString h = parts[i].trimmed().toLower();
                if (h == "lat" || h == "latitude") latCol = i;
                else if (h == "lon" || h == "lng" || h == "longitude") lonCol = i;
                else if (h == "alt" || h == "altitude" || h == "ele") altCol = i;
            }
            firstLine = false;
            if (latCol < 0 || lonCol < 0) {
                emit warningTriggered("CSV 缺少 lat/lon 列");
                return toQVariant(Err<QString>(
                    ServiceErrorCode::ParseError,
                    QStringLiteral("CSV 缺少 lat/lon 列"), ctx));
            }
            continue;
        }

        if (parts.size() > std::max(latCol, lonCol)) {
            double lat = parts[latCol].toDouble();
            double lon = parts[lonCol].toDouble();
            double alt = (altCol >= 0 && altCol < parts.size())
                          ? parts[altCol].toDouble() : 0;
            points.append(QGeoCoordinate(lat, lon));
            elevations.append(alt);
        }
    }
    file.close();

    if (points.isEmpty()) {
        emit warningTriggered("CSV 无有效数据");
        return toQVariant(Err<QString>(
            ServiceErrorCode::ParseError,
            QStringLiteral("CSV 无有效数据"), ctx));
    }

    QString trackId = generateId();
    QString pointsFile = m_storagePath + QString("/track_%1_points.json").arg(trackId);
    QJsonArray pointsArr;
    for (int i = 0; i < points.size(); ++i) {
        QJsonObject p;
        p["seq"] = i;
        p["lat"] = points[i].latitude();
        p["lon"] = points[i].longitude();
        p["elevation"] = i < elevations.size() ? elevations[i] : 0;
        p["timestamp"] = QDateTime::currentDateTime().toString(Qt::ISODate);
        pointsArr.append(p);
    }
    QFile pf(pointsFile);
    if (pf.open(QIODevice::WriteOnly)) {
        pf.write(QJsonDocument(pointsArr).toJson(QJsonDocument::Indented));
        pf.close();
    }

    stopTrack(trackId);

    QFile tf(m_storagePath + QString("/track_%1.json").arg(trackId));
    if (tf.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(tf.readAll());
        tf.close();
        QJsonObject obj = doc.object();
        obj["name"] = "CSV 导入";
        obj["source"] = "imported";
        obj["originalFormat"] = "csv";
        if (tf.open(QIODevice::WriteOnly)) {
            tf.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
            tf.close();
        }
    }

    emit trackImported(trackId, points.size());
    emit dataChanged();
    Logger::info(QString("CSV imported: %1 points").arg(points.size()));
    return toQVariant(Ok(trackId));
}

// 2026-09-21: 阶段 L3.4 - exportTrackAsGpx 切 Result<bool>
QVariantMap MapService::exportTrackAsGpx(const QString& trackId, const QString& filePath) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::exportTrackAsGpx";

    auto r = getTrackById(trackId);  // 2026-10-09: 契约切 Result, 先判 ok 再解包
    if (!r.value("ok").toBool()) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("轨迹不存在"), ctx));
    }
    auto track = r.value("value").toMap();

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                      QStringLiteral("无法打开输出文件"), ctx));
    }

    QXmlStreamWriter xml(&file);
    xml.setAutoFormatting(true);
    xml.writeStartDocument();
    xml.writeStartElement("gpx");
    xml.writeAttribute("version", "1.1");
    xml.writeAttribute("creator", "OutdoorSurvival 0.0.1");
    xml.writeAttribute("xmlns", "http://www.topografix.com/GPX/1/1");

    xml.writeStartElement("trk");
    xml.writeTextElement("name", track["name"].toString());
    xml.writeTextElement("time", track["startTime"].toString());

    xml.writeStartElement("trkseg");
    auto points = getTrackElevations(trackId);
    for (const auto& v : points) {
        auto m = v.toMap();
        xml.writeStartElement("trkpt");
        xml.writeAttribute("lat", QString::number(m["lat"].toDouble()));
        xml.writeAttribute("lon", QString::number(m["lon"].toDouble()));
        xml.writeTextElement("ele", QString::number(m["elevation"].toDouble()));
        xml.writeTextElement("time", m["timestamp"].toString());
        xml.writeEndElement();
    }
    xml.writeEndElement(); // trkseg
    xml.writeEndElement(); // trk
    xml.writeEndElement(); // gpx
    xml.writeEndDocument();
    file.close();
    return toQVariant(Ok(true));
}

QVariantMap MapService::exportTrackAsKml(const QString& trackId, const QString& filePath) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::exportTrackAsKml";

    auto r = getTrackById(trackId);  // 2026-10-09: 契约切 Result, 先判 ok 再解包
    if (!r.value("ok").toBool()) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("轨迹不存在"), ctx));
    }
    auto track = r.value("value").toMap();

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                      QStringLiteral("无法打开输出文件"), ctx));
    }

    QXmlStreamWriter xml(&file);
    xml.setAutoFormatting(true);
    xml.writeStartDocument();
    xml.writeStartElement("kml");
    xml.writeAttribute("xmlns", "http://www.opengis.net/kml/2.2");

    xml.writeStartElement("Document");
    xml.writeTextElement("name", track["name"].toString());

    xml.writeStartElement("Placemark");
    xml.writeTextElement("name", track["name"].toString());
    xml.writeStartElement("LineString");
    xml.writeTextElement("tessellate", "1");

    QString coords;
    auto points = getTrackElevations(trackId);
    for (const auto& v : points) {
        auto m = v.toMap();
        coords += QString("%1,%2,%3 ").arg(m["lon"].toDouble(), 0, 'f', 6)
                                      .arg(m["lat"].toDouble(), 0, 'f', 6)
                                      .arg(m["elevation"].toDouble(), 0, 'f', 1);
    }
    xml.writeTextElement("coordinates", coords.trimmed());
    xml.writeEndElement(); // LineString
    xml.writeEndElement(); // Placemark
    xml.writeEndElement(); // Document
    xml.writeEndElement(); // kml
    xml.writeEndDocument();
    file.close();
    return toQVariant(Ok(true));
}

QVariantMap MapService::exportAllSpeciesAsKml(const QString& filePath) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::exportAllSpeciesAsKml";

    auto locations = getSpeciesLocations();
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                      QStringLiteral("无法打开输出文件"), ctx));
    }

    QXmlStreamWriter xml(&file);
    xml.setAutoFormatting(true);
    xml.writeStartDocument();
    xml.writeStartElement("kml");
    xml.writeAttribute("xmlns", "http://www.opengis.net/kml/2.2");

    xml.writeStartElement("Document");
    xml.writeTextElement("name", "OutdoorSurvival Species");

    for (const auto& v : locations) {
        auto m = v.toMap();
        xml.writeStartElement("Placemark");
        xml.writeTextElement("name", m["speciesName"].toString());
        xml.writeTextElement("description", m["note"].toString());

        xml.writeStartElement("Point");
        QString coord = QString("%1,%2,%3").arg(m["lon"].toDouble(), 0, 'f', 6)
                                            .arg(m["lat"].toDouble(), 0, 'f', 6)
                                            .arg(m["altitude"].toDouble(), 0, 'f', 1);
        xml.writeTextElement("coordinates", coord);
        xml.writeEndElement(); // Point
        xml.writeEndElement(); // Placemark
    }

    xml.writeEndElement(); // Document
    xml.writeEndElement(); // kml
    xml.writeEndDocument();
    file.close();
    return toQVariant(Ok(true));
}


} // namespace outdoor
