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
#include "../common/SettingsStore.h"  // 2026-10-29: 采样档位持久化 (track/frequencySec)
#include "../common/TrackMetrics.h"   // 2026-10-29 #168: 轨迹统计唯一定口径
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
#include <QJsonValue>
#include <QXmlStreamReader>
#include <QXmlStreamWriter>
#include <QUuid>
#include <QDateTime>
#include <QRegularExpression>  // 2026-10-27 #134: importKml 拆 gx:coord / coordinates 用
#include <QTextStream>
#include <algorithm>
#include <cmath>  // 2026-10-26: addTrackPoint 用 std::isfinite 挡 NaN 哨兵
#include <limits>  // 2026-10-26: quiet_NaN 表示"这一帧没有高程", 不用 0 充数

namespace {

// 2026-10-27 #134: 导入器共用的坐标门 (GPX / KML / CSV 三处原来是三份手抄的判据,
//   CSV 那份压根没写). 越界或 (0,0) 哨兵点一旦进轨迹, 统计里的距离会被一条到几内亚湾
//   的往返拉爆, 而线上看着只是"线出屏了". 单轴为 0 仍是合法坐标 (赤道/本初子午线),
//   只有成对为 0 才按"没填"拒掉 —— 与 QML 侧 MapPage._validCoord 同一口径.
bool coordSane(double lat, double lon) {
    return std::isfinite(lat) && std::isfinite(lon)
            && lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0
            && !(lat == 0.0 && lon == 0.0);
}

// 2026-10-27 #134: stopTrack 把 endTime 写成"停止的这一刻", 对导入的旧文件是假读数.
//   这里按文件里的真实末刻回填, 文件没给就留空串 —— 宁可不显示, 也不让列表把
//   "刚刚"当成一条 2024 年轨迹的结束时间 (见 [[no-fake-readout-rule]]).
void patchImportedEndTime(const QString& storagePath, const QString& trackId,
                          const QDateTime& endTime) {
    QFile tf(storagePath + QString("/track_%1.json").arg(trackId));
    if (!tf.open(QIODevice::ReadOnly)) return;
    QJsonObject obj = QJsonDocument::fromJson(tf.readAll()).object();
    tf.close();
    obj["endTime"] = endTime.isValid() ? endTime.toString(Qt::ISODate) : QString();
    if (tf.open(QIODevice::WriteOnly)) {
        tf.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        tf.close();
    }
}

}  // namespace

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

    // 验证频率（5/10/15/30，与 getFrequencyOptions 同套）
    int validFreqs[] = {5, 10, 15, 30};
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
// 2026-10-26「轨迹/标注点精度到 1 m」: 补 accuracy 形参并把每点精度落盘.
//   原来点里只有 seq/lat/lon/elevation/timestamp —— 一条轨迹事后完全看不出
//   "这一排点是 3 m 的卫星点还是 60 m 的网络点", 于是统计里那个总距离既可能是真的
//   徒步距离, 也可能全是抖动堆出来的. 没有每点 ±, 任何"精度"都无从谈起.
//   elevation/accuracy 传 NaN/<=0 = 未知, **整键不写** —— 写 0 会被读成"海平面 0 米"
//   /"精度完美 0 米" (见 [[no-fake-readout-rule]]).
QVariantMap MapService::addTrackPoint(const QString& trackId, double lat, double lon,
                                       double elevation, double accuracy) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::addTrackPoint";

    // 2026-10-16: trackId 必须指向已 startTrack/importGpx 建好的 track_<id>.json,
    //   否则之前会静默写一个孤儿 points 文件, stopTrack 拿不到 track meta,
    //   getTrackStats 返回 "too few points".
    if (!QFileInfo::exists(m_storagePath + QString("/track_%1.json").arg(trackId))) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("轨迹不存在: %1").arg(trackId), ctx));
    }
    // 2026-10-26: 采样点必须自证是有效坐标. RecordTab 现在每个采样周期直接落盘,
    //   无权限时 EmergencyService 的 currentLatitude 是 0 —— 不过这道门就会攒一条
    //   "落在几内亚湾的济南徒步轨迹" (标注那边早就为同一个坑写了守卫, 见 MapPage).
    if (!std::isfinite(lat) || !std::isfinite(lon)
            || lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0
            || (lat == 0.0 && lon == 0.0)) {
        return toQVariant(Err<bool>(ServiceErrorCode::InvalidArgument,
                                      QStringLiteral("采样点坐标无效"), ctx));
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
    if (std::isfinite(elevation)) point["elevation"] = elevation;
    if (std::isfinite(accuracy) && accuracy > 0) point["accuracy"] = accuracy;
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
    //   口径只有一处: outdoor::track::compute() (见 TrackMetrics.h 头注释里的对账
    //   实测)。这里再加上"文件自述优先": 两步路的 KML 在 <Document> 属性表里写了
    //   它自己算的爬升/下降, importKml 抓成 declaredElevation*M 存进 meta, 有就用它
    //   —— 用户是拿那个数对账的。自录轨迹没有这两个键, 走算出来的平滑值。
    QFile pf(m_storagePath + QString("/track_%1_points.json").arg(trackId));
    if (pf.open(QIODevice::ReadOnly)) {
        QJsonDocument pdoc = QJsonDocument::fromJson(pf.readAll());
        pf.close();
        const QJsonArray points = pdoc.array();
        obj["pointCount"] = points.size();

        const outdoor::track::Metrics mt =
            outdoor::track::compute(outdoor::track::samplesFromJson(points));

        auto declared = [&obj](const QString& key, double fallback) {
            const QJsonValue v = obj.value(key);
            return (v.isDouble() && v.toDouble() >= 0.0) ? v.toDouble() : fallback;
        };

        obj["totalDistanceM"] = mt.distanceM;
        obj["elevationGainM"] = declared(QStringLiteral("declaredElevationGainM"), mt.gainM);
        obj["elevationLossM"] = declared(QStringLiteral("declaredElevationLossM"), mt.lossM);
        if (mt.hasAltitude) {
            obj["maxAltitudeM"] = mt.maxAltM;
            obj["minAltitudeM"] = mt.minAltM;
        } else {
            // 一个高程都没有时不要把 0 写出去 —— 那会被读成"这条轨迹全在海平面"
            obj.remove("maxAltitudeM");
            obj.remove("minAltitudeM");
        }
        if (mt.accuracyCount > 0) {
            obj["accuracyAvgM"] = mt.accuracyAvgM;
            obj["accuracyBestM"] = mt.accuracyBestM;
            obj["accuracyWorstM"] = mt.accuracyWorstM;
            obj["accuracyPointCount"] = mt.accuracyCount;
        } else {
            obj.remove("accuracyAvgM");
            obj.remove("accuracyBestM");
            obj.remove("accuracyWorstM");
            obj.remove("accuracyPointCount");
        }
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
            // 2026-10-26: stopTrack 现在在"一个高程都没有"时不写这两个键.
            //   这里必须跟着判存在, 否则 .toDouble() 把缺键读成 0, 列表上就是一行
            //   "最高 0 m / 最低 0 m" 的假数 (见 [[no-fake-readout-rule]]).
            if (obj.contains("maxAltitudeM")) m["maxAltitudeM"] = obj["maxAltitudeM"].toDouble();
            if (obj.contains("minAltitudeM")) m["minAltitudeM"] = obj["minAltitudeM"].toDouble();
            if (obj.contains("accuracyAvgM")) {
                m["accuracyAvgM"] = obj["accuracyAvgM"].toDouble();
                m["accuracyBestM"] = obj["accuracyBestM"].toDouble();
                m["accuracyWorstM"] = obj["accuracyWorstM"].toDouble();
                m["accuracyPointCount"] = obj["accuracyPointCount"].toInt();
            }
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
    // 2026-10-28 用户定档: 5 / 10 / 15 / 30 秒. 原来那五档 (2/5/10/20/30) 里
    //   "2 秒"在野外是"耗电一小时就没电", "20 秒"和 15/30 挤在一起没有区分度;
    //   四档一排 chip 在抽屉里也刚好放得下 (原五档在 fsSm 下把行挤到换行).
    struct FreqOption {
        int seconds;
        QString label;
        QString description;
    };
    FreqOption opts[] = {
        {5, "5 秒", "推荐平衡"},
        {10, "10 秒", "标准，省电"},
        {15, "15 秒", "长距离省电"},
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
        case 5: return "5 秒（推荐）";
        case 10: return "10 秒（标准）";
        case 15: return "15 秒（省电）";
        case 30: return "30 秒（粗略）";
        default: return QString::number(seconds) + " 秒";
    }
}

int MapService::getDefaultFrequency() const {
    // 2026-10-29: 这一条不再恒返 5 —— 用户选过的档位落 QSettings, 重启后读回.
    //   照 ui/nightMode (CommonOptions::setNightMode) 那一套: 写只在 setter, 读在这里.
    //   落盘值不可认 (旧版本残留 / 手改过配置) 就回 5, 不拿脏值当档位用.
    const int saved = outdoor::SettingsStore::getInt(QStringLiteral("track/frequencySec"), 5);
    return (saved == 5 || saved == 10 || saved == 15 || saved == 30) ? saved : 5;
}

void MapService::setFrequencySeconds(int seconds) {
    // 只认 getFrequencyOptions 那一套四档: 写进设置里的值必须是引擎也认的档,
    //   否则下次启动读回来是一个"界面高亮着一个 startTrack 会拒收的数".
    if (seconds != 5 && seconds != 10 && seconds != 15 && seconds != 30) {
        Logger::warn(QString("setFrequencySeconds: %1 不是合法档位, 不写设置").arg(seconds));
        return;
    }
    outdoor::SettingsStore::setValue(QStringLiteral("track/frequencySec"), seconds);
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

    // 2026-10-27 #134: GPX 的 <time> 按规范是 UTC (带 Z 或 ±偏移). QDateTime::fromString
    //   配 Qt::ISODate 认这个 Z, 但回来的是 UTC 口径; 而本 App 落盘写的是不带 Z 的
    //   墙钟串 (addTrackPoint 用 currentDateTime), 读方一律按本地解. 不转就整条 GPX
    //   轨迹的时刻比真墙钟差 8 小时 (和 KML 同一个坑).
    auto parseUtc = [](const QString& raw) {
        QDateTime t = QDateTime::fromString(raw.trimmed(), Qt::ISODate);
        return t.isValid() ? t.toLocalTime() : QDateTime();
    };

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
                trackStartTime = parseUtc(xml.readElementText());
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
                currentTime = parseUtc(xml.readElementText());
                hasCurrentTime = currentTime.isValid();
            }
        } else if (xml.isEndElement()) {
            QString endName = xml.name().toString();
            if (endName == "trkpt" || endName == "rtept") {
                // 一个点结束, 入栈
                points.append(currentPoint);
                // 没有 <ele> 就存 NaN, 落盘时整键不写. 原来缺高程填 0, stopTrack
                // 会把这条读成"最低点 0 米"并把落差顶高一截 (同 [[no-fake-readout-rule]]).
                elevations.append(hasCurrentEle ? currentEle
                                                : std::numeric_limits<double>::quiet_NaN());
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

    // 起始时间: 顶层 <time>, 其次第一个带时间的点. 都没有就留 invalid ——
    //   原来这里回落 currentDateTime(), 于是导入一条 2024 年的 GPX, 列表写的
    //   "开始时间"是"这一刻", stopTrack 再用 now 收尾, 时长算成两年多.
    QDateTime startTime = trackStartTime;
    QDateTime endTime;
    for (int i = 0; i < timestamps.size(); i++) {
        if (!timestamps[i].isValid()) continue;
        if (!startTime.isValid()) startTime = timestamps[i];
        endTime = timestamps[i];
    }
    // 没有逐点时刻就整条留空, 不再 addSecs(i*5) 编一条 5 秒等距节拍 ——
    //   getTrackStats 的速度就是段距离/段时刻差, 假节拍会把散步读成 8 km/h.
    //   缺键的点在统计里按"无速度"处理, 这是诚实的空白而不是编出来的数字.

    // 写入文件
    QString pointsFile = m_storagePath + QString("/track_%1_points.json").arg(trackId);
    QJsonArray pointsArr;
    int droppedBadCoord = 0;
    int seq = 0;
    for (int i = 0; i < points.size(); ++i) {
        // 坐标门见文件头的 coordSane()
        const double lat = points[i].latitude();
        const double lon = points[i].longitude();
        if (!coordSane(lat, lon)) {
            ++droppedBadCoord;
            continue;
        }
        QJsonObject p;
        p["seq"] = seq++;
        p["lat"] = lat;
        p["lon"] = lon;
        if (i < elevations.size() && std::isfinite(elevations[i])) {
            p["elevation"] = elevations[i];
        }
        if (timestamps[i].isValid()) {
            p["timestamp"] = timestamps[i].toString(Qt::ISODate);
        }
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
        obj["startTime"] = startTime.isValid() ? startTime.toString(Qt::ISODate) : QString();
        obj["endTime"] = QString();
        obj["source"] = "imported";
        obj["originalFormat"] = "gpx";
        QFile tf(m_storagePath + QString("/track_%1.json").arg(trackId));
        if (tf.open(QIODevice::WriteOnly)) {
            tf.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
            tf.close();
        }
    }

    // 停止轨迹（计算统计）
    stopTrack(trackId);
    // stopTrack 写的 endTime 是"停止的这一刻", 对导入的旧文件是假读数 → 按文件里的
    //   末刻回填, 文件没给时刻就留空.
    patchImportedEndTime(m_storagePath, trackId, endTime);

    emit trackImported(trackId, points.size() - droppedBadCoord);
    emit dataChanged();
    Logger::info(QString("GPX imported: %1 points, name='%2', dropped=%3, timed=%4")
                 .arg(points.size() - droppedBadCoord).arg(name)
                 .arg(droppedBadCoord).arg(endTime.isValid() ? 1 : 0));
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

    // 2026-10-27 #134 整体重写.
    //   旧解析只认 <Placemark><LineString><coordinates>, 而两步路
    //   (<Document id="TbuluKmlVersion2">) 的轨迹放在
    //   <Folder id="TbuluTrackFolder"><Placemark><gx:Track> 里: 先写完全部
    //   <gx:coord> ("lon lat alt" 空格分隔), 再写完全部 <when>. 手头 9 个两步路
    //   真机导出文件的 <LineString> 数量全是 0 —— 于是每一步路的 KML 都从下面那个
    //   points.isEmpty() 口子退回「KML 无轨迹点」, 轨迹根本进不了图 (#120 的一条真因).
    //   LineString 那条路保留, Google Earth / 奥维交互式地图导的是这种.
    //
    //   三种口径同时修掉:
    //     * 名称: <Document><name> 才是轨迹标题; 「轨迹片段1」是 Placemark 名,
    //       原来每个 Placemark 的 <name> 都会覆盖 name, 最后一个读到的往往是
    //       某个标注点, 列表里就变成用户看不懂的随机地名.
    //     * 时刻: 原来无时间就 addSecs(i*5) 编一条 5 秒等距节拍. 而 getTrackStats
    //       的速度 = 段距离 / 段时刻差, 于是 15.6 km / 7.2 h 的徒步被读成
    //       "平均 8 km/h" (文件自己写的 SportAvgSpeed 是 0.5 m/s 量级).
    //       现在用文件里的 <when>, 缺了就整点缺键, 不编.
    //     * <when> 是 UTC ("…T07:54:59Z"), fromString 回来仍是 UTC; 落盘写的
    //       ISO 串不带 Z, 读方按本地时间解 → 每条轨迹的时刻都差 8 小时, 必须
    //       toLocalTime 后再写 (addTrackPoint 录的是本地墙钟, 两边要能比).
    struct KmlPoint {
        double lat = 0.0;
        double lon = 0.0;
        double alt = 0.0;
        bool hasAlt = false;
        QDateTime ts;                 // invalid = 文件没给这一帧的时刻
    };

    QList<KmlPoint> points;
    int waypointCount = 0;   // 标注点 (<Point> 的 Placemark): 照片/文字, 本 App 不落盘
    int droppedBadCoord = 0; // 越界或 (0,0) 哨兵, 不写进轨迹

    QString docName;          // <Document><name> = 轨迹标题
    QString segmentName;      // 第一个真带点的轨迹 Placemark 的 <name>
    QString placemarkName;    // 当前 Placemark 的 <name>
    bool fromGxTrack = false;      // 点来自 gx:Track (两步路) 还是 LineString (Google Earth/奥维)
    QDateTime timeSpanBegin;  // <TimeSpan><begin> (Google Earth 风格)
    qint64 beginMs = 0;       // Document <ExtendedData> 的 BeginTime (毫秒 epoch)
    qint64 endMs = 0;
    // 两步路在同一个属性表里写了自己算的爬升/下降 (藏龙涧那条: 445.0 / 529.0).
    // NaN = 文件没给. 这两个数是用户在它 App 里看到的读数, 入库后由 stopTrack /
    // getTrackStats 优先采用 —— 见 TrackMetrics.h 头注释里的对账实测.
    double declaredGain = std::numeric_limits<double>::quiet_NaN();
    double declaredLoss = std::numeric_limits<double>::quiet_NaN();

    bool inDocument = false;
    bool inFolder = false;
    bool inPlacemark = false;
    bool inExtendedData = false;
    bool inLineString = false;
    bool inTimeSpan = false;
    bool inTrack = false;
    QString dataKey;                  // 当前 <Data name="..."> 的 name
    QList<KmlPoint> trackCoords;      // 当前 gx:Track 内的 <gx:coord>
    QList<QDateTime> trackTimes;      // 当前 gx:Track 内的 <when>

    // gx:Track 结束 = 一个片段结束. coord 与 when 是两条平行列表, 按下标配对;
    // when 少于 coord 时多出来的点没有时刻 (不编节拍).
    auto flushSegment = [&]() {
        for (int i = 0; i < trackCoords.size(); ++i) {
            KmlPoint p = trackCoords[i];
            if (i < trackTimes.size()) p.ts = trackTimes[i];
            points.append(p);
        }
        if (!trackCoords.isEmpty()) {
            fromGxTrack = true;
            if (segmentName.isEmpty()) segmentName = placemarkName;
        }
        trackCoords.clear();
        trackTimes.clear();
    };

    QXmlStreamReader xml(&file);
    while (!xml.atEnd()) {
        xml.readNext();
        if (xml.hasError()) break;   // 尾部标签不规整也照已读到的点入库
        if (xml.isStartElement()) {
            const QString nameTag = xml.name().toString();
            if (nameTag == "Document") {
                inDocument = true;
            } else if (nameTag == "Folder") {
                inFolder = true;
            } else if (nameTag == "Placemark") {
                inPlacemark = true;
                placemarkName.clear();
            } else if (nameTag == "name") {
                // 两步路把标题写成 <name><![CDATA[2026-10-25 藏龙涧-…]]>, 后面
                // <Folder><name>轨迹</name> 和每个 Placemark 的 <name> 都不是标题,
                // 所以按容器分层收: Document 直属的第一个非空 name 收作 docName,
                // Placemark 内的只留作片段名. 两者谁当轨迹名按线是哪来的分 (见下面).
                const QString txt = xml.readElementText().trimmed();
                if (!txt.isEmpty()) {
                    if (inPlacemark) {
                        if (placemarkName.isEmpty()) placemarkName = txt;
                    } else if (!inFolder && inDocument && docName.isEmpty()) {
                        docName = txt;
                    }
                }
            } else if (nameTag == "ExtendedData") {
                inExtendedData = true;
            } else if (nameTag == "Data" && inExtendedData) {
                dataKey = xml.attributes().value("name").toString();
            } else if (nameTag == "value" && inExtendedData
                       && !inPlacemark && !inTrack) {
                // 只收 Document 层那份属性表. Placemark/gx:Track 里同名标签装的是
                // 标注点照片信息和 GxTrackExtendedData (每点 speed,hr 一大串),
                // 读它们既没用又要多吃几百 KB.
                const QString txt = xml.readElementText().trimmed();
                if (dataKey == "BeginTime") beginMs = txt.toLongLong();
                else if (dataKey == "EndTime") endMs = txt.toLongLong();
                else if (dataKey == "ElevationGain" || dataKey == "ElevationLoss") {
                    bool ok = false;
                    const double v = txt.toDouble(&ok);
                    // 非数字或负数当"没给": 留 NaN, 让下游回落到自己算的平滑值
                    if (ok && v >= 0.0) {
                        if (dataKey == "ElevationGain") declaredGain = v;
                        else declaredLoss = v;
                    }
                }
            } else if (nameTag == "TimeSpan") {
                inTimeSpan = true;
            } else if (nameTag == "begin" && inTimeSpan) {
                timeSpanBegin = QDateTime::fromString(xml.readElementText().trimmed(), Qt::ISODate);
                if (timeSpanBegin.isValid()) timeSpanBegin = timeSpanBegin.toLocalTime();
            } else if (nameTag == "LineString") {
                inLineString = true;
            } else if (nameTag == "Track") {
                // <gx:Track> 的本地名就是 "Track" (前缀 gx 不在 name() 里)
                inTrack = true;
                trackCoords.clear();
                trackTimes.clear();
            } else if (nameTag == "coord" && inTrack) {
                const QStringList parts = xml.readElementText().trimmed()
                    .split(QRegularExpression("[\\s]+"), Qt::SkipEmptyParts);
                if (parts.size() >= 2) {
                    KmlPoint p;
                    p.lon = parts[0].toDouble();
                    p.lat = parts[1].toDouble();
                    if (parts.size() >= 3) {
                        p.alt = parts[2].toDouble();
                        p.hasAlt = true;
                    }
                    trackCoords.append(p);
                }
            } else if (nameTag == "when" && inTrack) {
                QDateTime t = QDateTime::fromString(xml.readElementText().trimmed(), Qt::ISODate);
                if (t.isValid()) t = t.toLocalTime();
                trackTimes.append(t);
            } else if (nameTag == "Point" && inPlacemark && !inTrack) {
                // 标注点 (起点/终点/拍照点). 本 App 的轨迹模型只有一条线, 没有
                // 途经点字段, 所以这里只计数, 落盘后在日志里点名丢了多少个.
                ++waypointCount;
            } else if (nameTag == "coordinates" && inLineString) {
                const QString text = xml.readElementText();
                // KML 坐标是 "lon,lat,alt" 用空格分隔多个点; 但 alt 字段可能没有 (lon,lat)
                const QStringList coords = text.split(QRegularExpression("[\\s]+"), Qt::SkipEmptyParts);
                for (const QString& c : coords) {
                    const QStringList parts = c.split(',');
                    if (parts.size() < 2) continue;
                    KmlPoint p;
                    p.lon = parts[0].toDouble();
                    p.lat = parts[1].toDouble();
                    if (parts.size() >= 3) {
                        p.alt = parts[2].toDouble();
                        p.hasAlt = true;
                    }
                    p.ts = timeSpanBegin;
                    points.append(p);
                    // <name> 排在 <LineString> 前面, 此刻 placemarkName 已经是这条线的名字
                    if (segmentName.isEmpty()) segmentName = placemarkName;
                }
            }
        } else if (xml.isEndElement()) {
            const QString endName = xml.name().toString();
            if (endName == "Document") inDocument = false;
            else if (endName == "Folder") inFolder = false;
            else if (endName == "Placemark") {
                // 2026-10-27: 原来这里漏了未闭合片段. 现在 gx:Track 自己收尾, Placemark
                // 结束只清当前名字.
                inPlacemark = false;
                placemarkName.clear();
            }
            else if (endName == "ExtendedData") { inExtendedData = false; dataKey.clear(); }
            else if (endName == "TimeSpan") inTimeSpan = false;
            else if (endName == "LineString") inLineString = false;
            else if (endName == "Track" && inTrack) {
                flushSegment();
                inTrack = false;
            }
        }
    }
    file.close();
    if (inTrack) flushSegment();   // 文件被截断时, 已读到的片段别丢

    // 坐标自检: 与 addTrackPoint 同一道门, 见 coordSane()
    QList<KmlPoint> sane;
    sane.reserve(points.size());
    for (const KmlPoint& p : points) {
        if (coordSane(p.lat, p.lon)) sane.append(p);
        else ++droppedBadCoord;
    }
    points = sane;

    if (points.isEmpty()) {
        emit warningTriggered("KML 无轨迹点");
        return toQVariant(Err<QString>(
            ServiceErrorCode::ParseError,
            QStringLiteral("KML 里没有可用的轨迹点 (既没有 gx:Track, 也没有 LineString)"),
            ctx));
    }

    // 名称按线的来源分: 两步路的 Placemark 一律叫「轨迹片段1」, 真标题在
    // <Document><name>; Google Earth/奥维的 Document 名是"我的地点"这类容器名,
    // 标题在带线的那个 Placemark 上.
    QString name;
    if (fromGxTrack && !docName.isEmpty()) name = docName;
    else if (!segmentName.isEmpty()) name = segmentName;
    else name = docName;
    if (name.isEmpty()) name = QStringLiteral("KML 导入");

    // 起止时间优先用逐点 <when> (它才是这条线真正走过的时间), 其次用两步路属性表
    // 里的 BeginTime/EndTime 毫秒, 最后留空 —— 空串会被 getTrackStats 回落到
    // 首末点时间, 而"导入的这一刻"写进 startTime 会读成一次 0 秒的徒步.
    QDateTime firstTs, lastTs;
    for (const KmlPoint& p : points) {
        if (!p.ts.isValid()) continue;
        if (!firstTs.isValid()) firstTs = p.ts;
        lastTs = p.ts;
    }
    QDateTime startTime = firstTs;
    if (!startTime.isValid() && beginMs > 0) startTime = QDateTime::fromMSecsSinceEpoch(beginMs);
    if (!startTime.isValid()) startTime = timeSpanBegin;
    QDateTime endTime = lastTs;
    if (!endTime.isValid() && endMs > 0) endTime = QDateTime::fromMSecsSinceEpoch(endMs);

    const QString trackId = generateId();
    QString pointsFile = m_storagePath + QString("/track_%1_points.json").arg(trackId);
    QJsonArray pointsArr;
    for (int i = 0; i < points.size(); ++i) {
        const KmlPoint& p = points[i];
        QJsonObject obj;
        obj["seq"] = i;
        obj["lat"] = p.lat;
        obj["lon"] = p.lon;
        // 没给高程就整键不写: 写 0 会被 stopTrack 读成"最低点 0 米", 还把
        // elevationLoss 顶高一截 (见 [[no-fake-readout-rule]]).
        if (p.hasAlt) obj["elevation"] = p.alt;
        if (p.ts.isValid()) obj["timestamp"] = p.ts.toString(Qt::ISODate);
        pointsArr.append(obj);
    }
    QFile pf(pointsFile);
    if (pf.open(QIODevice::WriteOnly)) {
        pf.write(QJsonDocument(pointsArr).toJson(QJsonDocument::Indented));
        pf.close();
    }

    // 2026-10-27: 原来这里先 stopTrack(trackId) 再去开 track_<id>.json 改名称 ——
    //   那个文件此刻还不存在 (只有 _points.json), stopTrack 走 NotFound 直接返回,
    //   距离/爬升/最高最低一个都没算, 名称那次 open 也失败, 于是导入成功的轨迹
    //   在列表里既没有名字也没有统计. 顺序改成: 先落 meta → stopTrack 汇总 →
    //   只回填 stopTrack 会覆盖掉的 endTime (它写的是"停止的这一刻").
    {
        QJsonObject obj;
        obj["id"] = trackId;
        obj["name"] = name;
        obj["startTime"] = startTime.isValid() ? startTime.toString(Qt::ISODate) : QString();
        obj["endTime"] = QString();
        obj["source"] = "imported";
        obj["originalFormat"] = "kml";
        // 文件自述的升降: 只在这一步抓下来, 后面两处读数 (列表/排序 与 概要面板)
        // 都按"有自述用自述, 没有用平滑口径"的优先级取 —— 见 stopTrack.
        if (std::isfinite(declaredGain)) obj["declaredElevationGainM"] = declaredGain;
        if (std::isfinite(declaredLoss)) obj["declaredElevationLossM"] = declaredLoss;
        QFile tf(m_storagePath + QString("/track_%1.json").arg(trackId));
        if (tf.open(QIODevice::WriteOnly)) {
            tf.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
            tf.close();
        }
    }

    stopTrack(trackId);
    // stopTrack 写的是"停止的这一刻", 导入的旧文件要按文件里的末刻回填
    //   (文件既无 <when> 又无 EndTime 属性时留空, 不让人读成"刚走完").
    patchImportedEndTime(m_storagePath, trackId, endTime);

    emit trackImported(trackId, points.size());
    emit dataChanged();
    Logger::info(QString("KML imported: %1 points, name='%2', waypoints=%3, dropped=%4")
                 .arg(points.size()).arg(name).arg(waypointCount).arg(droppedBadCoord));
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

    struct CsvPoint {
        double lat = 0.0;
        double lon = 0.0;
        double alt = 0.0;
        bool hasAlt = false;
        QDateTime ts;                  // invalid = 这一行没给时刻
    };
    QList<CsvPoint> points;
    bool firstLine = true;
    int latCol = -1, lonCol = -1, altCol = -1, timeCol = -1;

    // 2026-10-27 #134: 表头里的 time 列此前被完全忽略, 而每一点落的却是
    //   currentDateTime() —— 导入一条两年前的 CSV, 逐点时刻全是"这一刻",
    //   getTrackStats 按时刻差算速度就全是 0. 现在按 GPX/KML 同一口径读:
    //   文件带 UTC 串 (…Z) 就转成本地墙钟, 没这一列就整点缺键, 不编.
    auto parseUtc = [](const QString& raw) {
        QDateTime t = QDateTime::fromString(raw.trimmed(), Qt::ISODate);
        return t.isValid() ? t.toLocalTime() : QDateTime();
    };

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
                else if (h == "alt" || h == "altitude" || h == "ele" || h == "elevation") altCol = i;
                else if (h == "time" || h == "timestamp" || h == "datetime") timeCol = i;
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

        if (parts.size() <= std::max(latCol, lonCol)) continue;
        CsvPoint p;
        p.lat = parts[latCol].toDouble();
        p.lon = parts[lonCol].toDouble();
        if (altCol >= 0 && altCol < parts.size() && !parts[altCol].trimmed().isEmpty()) {
            p.alt = parts[altCol].toDouble();
            p.hasAlt = true;
        }
        if (timeCol >= 0 && timeCol < parts.size()) p.ts = parseUtc(parts[timeCol]);
        points.append(p);
    }
    file.close();

    int droppedBadCoord = 0;
    QList<CsvPoint> sane;
    sane.reserve(points.size());
    for (const CsvPoint& p : points) {
        if (coordSane(p.lat, p.lon)) sane.append(p);
        else ++droppedBadCoord;
    }
    points = sane;

    if (points.isEmpty()) {
        emit warningTriggered("CSV 无有效数据");
        return toQVariant(Err<QString>(
            ServiceErrorCode::ParseError,
            QStringLiteral("CSV 里没有可用的轨迹点"), ctx));
    }

    QDateTime firstTs, lastTs;
    for (const CsvPoint& p : points) {
        if (!p.ts.isValid()) continue;
        if (!firstTs.isValid()) firstTs = p.ts;
        lastTs = p.ts;
    }

    QString trackId = generateId();
    QString pointsFile = m_storagePath + QString("/track_%1_points.json").arg(trackId);
    QJsonArray pointsArr;
    for (int i = 0; i < points.size(); ++i) {
        const CsvPoint& p = points[i];
        QJsonObject obj;
        obj["seq"] = i;
        obj["lat"] = p.lat;
        obj["lon"] = p.lon;
        // 没有高程列 / 那一格空着 → 整键不写, 写 0 会被 stopTrack 读成"最低点 0 米"
        if (p.hasAlt) obj["elevation"] = p.alt;
        if (p.ts.isValid()) obj["timestamp"] = p.ts.toString(Qt::ISODate);
        pointsArr.append(obj);
    }
    QFile pf(pointsFile);
    if (pf.open(QIODevice::WriteOnly)) {
        pf.write(QJsonDocument(pointsArr).toJson(QJsonDocument::Indented));
        pf.close();
    }

    // 2026-10-27 #134: 和 importGpx/importKml 同一处顺序缺陷 —— 原来先 stopTrack
    //   再去开 track_<id>.json 补名称, 而那个文件此刻还不存在 (只写了 _points.json),
    //   stopTrack 走 NotFound 直接返回: 距离/爬升一个没算, 名称/source 也没落盘,
    //   导入"成功"的 CSV 轨迹在列表里是一行没有统计的空白.
    {
        QJsonObject obj;
        obj["id"] = trackId;
        obj["name"] = "CSV 导入";
        obj["startTime"] = firstTs.isValid() ? firstTs.toString(Qt::ISODate) : QString();
        obj["endTime"] = QString();
        obj["source"] = "imported";
        obj["originalFormat"] = "csv";
        QFile tf(m_storagePath + QString("/track_%1.json").arg(trackId));
        if (tf.open(QIODevice::WriteOnly)) {
            tf.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
            tf.close();
        }
    }

    stopTrack(trackId);
    patchImportedEndTime(m_storagePath, trackId, lastTs);

    emit trackImported(trackId, points.size());
    emit dataChanged();
    Logger::info(QString("CSV imported: %1 points, dropped=%2, timed=%3")
                 .arg(points.size()).arg(droppedBadCoord).arg(lastTs.isValid() ? 1 : 0));
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
    // creator 必须跟着 APP_VERSION 走。2026-10-26 之前这里写死 "OutdoorSurvival 0.0.1",
    // 于是 0.0.2 导出的 GPX 自称 0.0.1 —— 导出文件是会被拿去别的数据工具里对账的产物,
    // 版本号写错等于给那份数据签了个错的时间戳。
    xml.writeAttribute("creator", "OutdoorSurvival " APP_VERSION);
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
