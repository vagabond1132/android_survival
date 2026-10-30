/**
 * @file WeatherForecastService.cpp
 * @brief open-meteo 日预报拉取 + 缓存 + 装备引擎键换算
 */

#include "WeatherForecastService.h"

#include "Logger.h"
#include "../equipment/EquipmentService.h"

#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <QUrlQuery>
#include <QVariant>
#include <cmath>

namespace outdoor {

namespace {

constexpr char kForecastUrl[] = "https://api.open-meteo.com/v1/forecast";
constexpr char kUserAgent[] = "OutdoorSurvivalApp/1.0 (weather-forecast; Qt)";

// 实测这 7 个字段全部被接受。要的要的是**日累计/日极值**, 小时序列在这里用不上,
// 拉回来只是白耗流量 (野外设备按流量计)。
constexpr char kDailyFields[] =
    "temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max,"
    "relative_humidity_2m_mean,precipitation_probability_max,uv_index_max";

// 8s: 与 ImageFetcherService 同一个教训 —— 域名被墙时 SYN 被静默丢弃,
//   QNetworkAccessManager 默认**没有**超时 → finished 永不触发 → 界面永远转圈。
constexpr int kTransferTimeoutMs = 8000;

// 30 分钟: 预报本身一天更新几次, 反复进出装备页不该每次都打一发请求;
//   再长就开始骗人 (用户会以为"当前天气"真的是当前)。
constexpr qint64 kCacheTtlMs = 30LL * 60LL * 1000LL;

constexpr int kForecastDays = 16;   // open-meteo 上限, 覆盖"一周内出发"的规划窗口

/// 数组第 i 项是不是可用数值 (open-meteo 缺测给 null, 不能当 0 用)
bool numberAt(const QJsonArray& arr, qsizetype i, double* out) {
    if (i >= arr.size()) return false;
    const QJsonValue v = arr.at(i);
    if (!v.isDouble()) return false;   // Null / String / Undefined 都走这里
    *out = v.toDouble();
    return true;
}

double round1(double v) { return std::round(v * 10.0) / 10.0; }

}  // namespace

WeatherForecastService::WeatherForecastService(QObject* parent)
    : ServiceBase("WeatherForecastService", parent),
      m_nam(new QNetworkAccessManager(this)) {
    m_nam->setTransferTimeout(kTransferTimeoutMs);   // 兜底; 真正发请求处还按请求设一次
}

WeatherForecastService::~WeatherForecastService() = default;

void WeatherForecastService::setClimateBaseline(const EquipmentService* baseline) {
    if (!baseline) {
        // 没有基线 = 不做海拔/紫外线修正 (不是"修正量当成 0 也算修正过")。
        // 值抄进成员而不是存指针: ServiceRegistry 里两者的析构顺序不该由本类操心。
        m_lapseCPerKm = 0.0;
        m_uvPerKm = 0.0;
        return;
    }
    m_lapseCPerKm = baseline->lapseRateCPer1000m();
    m_uvPerKm = baseline->uvRatePer1000m();
}

// === 解析 + 换算 (纯函数, 单测直接喂 fixture) ================================
// 键集与 EquipmentService::climateFor() 对齐: 装备引擎吃的是同一批键, 所以
//   - 档位一律调 EquipmentService 的公开静态函数, 这里出现第二个阈值就是债;
//   - 日降水走 precipitationBandDaily (月阈值会把所有雨天判成 None);
//   - 湿度走 humidityBandFromRh (日预报有实测相对湿度, 不必像月表那样绕道降水)。
QVariantList WeatherForecastService::parseDailyJson(const QByteArray& body,
                                                   qint64 fetchedAtMs,
                                                   double routeAltitudeM,
                                                   double lapseCPerKm,
                                                   double uvPerKm) {
    QVariantList out;
    if (body.isEmpty()) return out;

    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(body, &perr);
    if (perr.error != QJsonParseError::NoError || !doc.isObject()) {
        Logger::warn(QString("WeatherForecastService: body is not valid JSON (%1)")
                     .arg(perr.errorString()));
        return out;
    }
    const QJsonObject root = doc.object();
    const QJsonObject daily = root.value("daily").toObject();
    const QJsonArray times = daily.value("time").toArray();
    if (daily.isEmpty() || times.isEmpty()) {
        Logger::warn("WeatherForecastService: response has no daily/time array");
        return out;
    }

    const QJsonArray tMax = daily.value("temperature_2m_max").toArray();
    const QJsonArray tMin = daily.value("temperature_2m_min").toArray();
    const QJsonArray precip = daily.value("precipitation_sum").toArray();
    const QJsonArray wind = daily.value("wind_speed_10m_max").toArray();
    const QJsonArray rh = daily.value("relative_humidity_2m_mean").toArray();
    const QJsonArray prob = daily.value("precipitation_probability_max").toArray();
    const QJsonArray uv = daily.value("uv_index_max").toArray();

    // 海拔修正: open-meteo 的读数属于**格点海拔** (root.elevation), 路线在别的高度要按
    //   直减率换算 —— 与 climateFor 拿代表站海拔做的事一模一样。
    //   格点海拔或路线海拔有一个不知道, 就整批不修正: 算不出修正量时"原样"比"编一个"诚实。
    const QJsonValue elevVal = root.value("elevation");
    const bool corrected = elevVal.isDouble() && routeAltitudeM >= 0.0;
    const double dKm = corrected ? (routeAltitudeM - elevVal.toDouble()) / 1000.0 : 0.0;

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    // 没有拉取时刻 = 不知道这数多旧, 给 -1 让界面明说"新旧未知", 不许装作是刚拉的
    const int ageMinutes = fetchedAtMs > 0
        ? static_cast<int>(qMax<qint64>(0, (nowMs - fetchedAtMs) / 60000))
        : -1;

    for (qsizetype i = 0; i < times.size(); ++i) {
        const QString date = times.at(i).toString();
        const QDate day = QDate::fromString(date, Qt::ISODate);
        if (!day.isValid()) continue;   // 认不出的日期: 整行不要

        double hi = 0.0, lo = 0.0;
        if (!numberAt(tMax, i, &hi) || !numberAt(tMin, i, &lo)) continue;  // 没温度这行没法用

        const double corr = lapseCPerKm * dKm;
        const double tempMin = lo + corr;

        QVariantMap m;
        // 响应里没有 temperature_2m_mean: tempAvg 取 (max+min)/2、diurnalRange 取 max-min,
        //   两者都是**代理值** —— 与月表的 tempAvg(日均温)/diurnalRange(日内摆幅) 同语义。
        m["tempAvg"] = round1((hi + lo) / 2.0 + corr);
        m["tempMin"] = round1(tempMin);
        m["diurnalRange"] = qRound(hi - lo);   // climateFor 给整数, 这里保持同型
        m["season"] = EquipmentService::seasonFromMonth(day.month());

        double windKmh = 0.0;
        if (numberAt(wind, i, &windKmh)) {
            const double ms = windKmh / 3.6;   // open-meteo 给 km/h, 引擎的 windSpeed 是 m/s
            m["windSpeed"] = round1(ms);
            m["windLevel"] = static_cast<int>(EquipmentService::windLevelFromSpeed(static_cast<float>(ms)));
        }

        // 高纬冬季 uv_index_max 会是 null。这时**整键不出现**: 填 0 会被引擎读成"紫外线弱",
        //   防晒规则就此永不触发 —— 那是假读数, 比没有读数更坏。
        double uvRaw = 0.0;
        if (numberAt(uv, i, &uvRaw)) {
            const double uvIdx = qBound(0.0, uvRaw * (1.0 + uvPerKm * dKm), 16.0);
            m["uvIndex"] = round1(uvIdx);
            m["uvLevel"] = static_cast<int>(EquipmentService::uvLevelFromIndex(static_cast<float>(uvIdx)));
        }

        double mm = 0.0;
        if (numberAt(precip, i, &mm)) {
            const int band = EquipmentService::precipitationBandDaily(mm, tempMin);
            m["precipitation"] = band;
            m["forecastPrecipMm"] = round1(mm);
            // 一天的预报定不了"雨季", 这里降级成"这天会下雨": 枚举上 1..4 是雨、5..8 是雪
            //   (见 EquipmentService.h 的 Precipitation 注释), 拿雨档判定就不用再抄一套阈值。
            m["isRainySeason"] = (band >= static_cast<int>(Precipitation::Light)
                               && band <= static_cast<int>(Precipitation::Storm));
        }

        double rhPct = 0.0;
        if (numberAt(rh, i, &rhPct)) {
            m["humidity"] = EquipmentService::humidityBandFromRh(rhPct);
            m["forecastRhPct"] = round1(rhPct);
        }

        double probPct = 0.0;
        if (numberAt(prob, i, &probPct)) {
            m["forecastPrecipProbPct"] = qRound(probPct);
        }

        // 来源说明键: 引擎读不到也无害, 缺它们界面就没法如实交代"这数几点拉的、多旧"
        m["forecastDate"] = date;
        m["fetchedAtMs"] = fetchedAtMs;
        m["ageMinutes"] = ageMinutes;
        if (corrected) m["forecastElevationM"] = qRound(routeAltitudeM);
        m["source"] = QStringLiteral("forecast");

        out.append(m);
    }
    return out;
}

// === QML 侧读取 ==============================================================

QVariantMap WeatherForecastService::forecastFor(const QString& dateIso) const {
    const QString want = dateIso.trimmed();
    if (want.isEmpty()) return {};
    for (const QVariant& v : m_days) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("forecastDate")).toString() == want) {
            return withFreshAge_(m);
        }
    }
    return {};   // 取不到就是空 map, 不拿别的日期凑一份
}

QVariantList WeatherForecastService::forecastDays() const {
    QVariantList out;
    out.reserve(m_days.size());
    for (const QVariant& v : m_days) {
        out.append(withFreshAge_(v.toMap()));
    }
    return out;
}

QVariantMap WeatherForecastService::withFreshAge_(const QVariantMap& day) {
    QVariantMap m = day;
    const qint64 fetched = day.value(QStringLiteral("fetchedAtMs")).toLongLong();
    // fetchedAtMs 丢了就是"不知道这数哪来的", 宁可给一个显眼的 -1 也不装作是刚拉的
    m["ageMinutes"] = fetched > 0
        ? static_cast<int>(qMax<qint64>(0, (QDateTime::currentMSecsSinceEpoch() - fetched) / 60000))
        : -1;
    return m;
}

// === 刷新 (异步) =============================================================

void WeatherForecastService::refresh(double lat, double lon, double routeAltitudeM) {
    if (!(lat >= -90.0 && lat <= 90.0) || !(lon >= -180.0 && lon <= 180.0)) {
        Logger::warn(QString("WeatherForecastService: invalid coords lat=%1 lon=%2").arg(lat).arg(lon));
        emit forecastFailed(QStringLiteral("路线坐标无效，取不了天气预报"));
        return;
    }

    const QString path = cachePathFor_(lat, lon);
    if (m_loadedPath != path) {
        m_loadedFetchedAtMs = 0;
        m_loadedAltitudeM = -1.0;
        m_days = loadCache_(path, &m_loadedFetchedAtMs, &m_loadedAltitudeM);
        m_loadedPath = path;
    }

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    const bool fresh = !m_days.isEmpty()
                       && m_loadedFetchedAtMs > 0
                       && nowMs - m_loadedFetchedAtMs <= kCacheTtlMs;
    // 缓存里的温度是按**当初那个路线海拔**修正过的; 换海拔 (同一条路线从谷底挪到垭口)
    //   还复用, 给出的就是一批错 20℃ 的读数 —— 所以海拔不同就重拉。
    const bool sameAltitude = std::abs(m_loadedAltitudeM - routeAltitudeM) < 1.0;
    if (fresh && sameAltitude) {
        Logger::info(QString("WeatherForecastService: cache hit (%1 min old), %2 days")
                     .arg((nowMs - m_loadedFetchedAtMs) / 60000).arg(m_days.size()));
        emit forecastUpdated();
        return;
    }

    startRequest_(lat, lon, routeAltitudeM, path);
}

void WeatherForecastService::startRequest_(double lat, double lon, double routeAltitudeM,
                                          const QString& path) {
    QUrl url(QString::fromLatin1(kForecastUrl));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("latitude"), QString::number(lat, 'f', 3));
    q.addQueryItem(QStringLiteral("longitude"), QString::number(lon, 'f', 3));
    q.addQueryItem(QStringLiteral("daily"), QString::fromLatin1(kDailyFields));
    // 日期按北京时间切: 否则 UTC 跨日会把"今天"的读数挂到昨天的日期上
    q.addQueryItem(QStringLiteral("timezone"), QStringLiteral("Asia/Shanghai"));
    q.addQueryItem(QStringLiteral("forecast_days"), QString::number(kForecastDays));
    url.setQuery(q);

    QNetworkRequest req{url};
    req.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kUserAgent));
    // Qt 6.7: 按请求设超时 (manager 那份默认值只是兜底, 这里显式设一次不靠它)
    req.setTransferTimeout(kTransferTimeoutMs);

    if (m_reply) {
        QNetworkReply* stale = m_reply;
        m_reply = nullptr;    // 先摘指针: abort() 同步触发 finished, 槽里据"不是当前请求"丢弃
        stale->abort();
        stale->deleteLater();
    }

    m_pendingPath = path;
    m_pendingAltitudeM = routeAltitudeM;

    m_reply = m_nam->get(req);
    connect(m_reply, &QNetworkReply::finished, this, &WeatherForecastService::onForecastReply_);
    Logger::info(QString("WeatherForecastService: request lat=%1 lon=%2 alt=%3")
                 .arg(lat).arg(lon).arg(routeAltitudeM));
}

void WeatherForecastService::onForecastReply_() {
    QNetworkReply* reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();
    if (reply != m_reply) return;   // 被新一次 refresh 取代, 不参与结论
    m_reply = nullptr;

    const int httpStatus =
        reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray body = reply->readAll();
    const bool netOk = (reply->error() == QNetworkReply::NoError);

    // 英文细节 (Qt 的 errorString / 状态码) 只进日志, 给用户的 reason 一律中文
    Logger::info(QString("WeatherForecastService: reply ok=%1 http=%2 err=%3 bytes=%4")
                 .arg(netOk ? "1" : "0").arg(httpStatus)
                 .arg(reply->errorString()).arg(body.size()));

    // 失败三条路都不动 m_days 也不动磁盘: 离线时旧读数还能显示, 靠 ageMinutes 说明它多旧
    if (!netOk) {
        emit forecastFailed(QStringLiteral("天气预报获取失败，可能没有网络"));
        return;
    }
    if (httpStatus >= 400) {
        emit forecastFailed(QStringLiteral("天气预报服务暂时不可用"));
        return;
    }

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    const QVariantList days = parseDailyJson(body, nowMs, m_pendingAltitudeM,
                                             m_lapseCPerKm, m_uvPerKm);
    if (days.isEmpty()) {
        emit forecastFailed(QStringLiteral("天气预报返回的数据读不懂"));
        return;
    }

    m_days = days;
    m_loadedFetchedAtMs = nowMs;
    m_loadedAltitudeM = m_pendingAltitudeM;
    saveCache_(m_pendingPath, nowMs, m_pendingAltitudeM, days);

    Logger::info(QString("WeatherForecastService: %1 days cached").arg(days.size()));
    emit forecastUpdated();
}

// === 磁盘缓存 ================================================================

QString WeatherForecastService::cachePathFor_(double lat, double lon) const {
    // 两位小数 ≈1km, 而 open-meteo 的格点本身就有 10km 量级 —— 再细则同一条路线
    //   反复刷新会各写一份文件, 30 分钟 TTL 也就白设了。
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    const QString name = QString("%1_%2.json")
        .arg(lat, 0, 'f', 2).arg(lon, 0, 'f', 2);
    return base + "/weather_forecast/" + name;
}

QVariantList WeatherForecastService::loadCache_(const QString& path, qint64* fetchedAtMs,
                                                double* routeAltitudeM) const {
    QVariantList out;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        return out;   // 首次使用/被清理: 不是错误, 只是没缓存
    }
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        Logger::warn(QString("WeatherForecastService: cache %1 is broken JSON (%2)")
                     .arg(path, err.errorString()));
        return out;
    }
    const QJsonObject root = doc.object();
    const qint64 stamp = static_cast<qint64>(root.value(QStringLiteral("fetchedAtMs")).toDouble());
    // 没有时间戳就当没有这份缓存: "当前天气"却不知道是哪一刻拉的, 那是假读数
    if (stamp <= 0) {
        Logger::warn(QString("WeatherForecastService: cache %1 has no fetchedAtMs").arg(path));
        return out;
    }
    const QJsonArray days = root.value(QStringLiteral("days")).toArray();
    for (const QJsonValue& v : days) {
        QVariantMap m = v.toVariant().toMap();
        if (m.value(QStringLiteral("forecastDate")).toString().isEmpty()) continue;
        // 根上的 fetchedAtMs 是唯一权威时刻 (整批一起拉的), 逐行的按它覆盖一遍:
        // 行里那个 0 是"刚拉到时"写进去的, 放久了不覆盖就成了假新鲜
        m.insert(QStringLiteral("fetchedAtMs"), static_cast<qlonglong>(stamp));
        out.append(m);
    }
    if (out.isEmpty()) return out;

    *fetchedAtMs = stamp;
    *routeAltitudeM = root.value(QStringLiteral("routeAltitudeM")).toDouble(-1.0);
    return out;
}

void WeatherForecastService::saveCache_(const QString& path, qint64 fetchedAtMs,
                                        double routeAltitudeM, const QVariantList& days) {
    QDir().mkpath(QFileInfo(path).absolutePath());

    QJsonObject root;
    root["fetchedAtMs"] = static_cast<double>(fetchedAtMs);
    root["routeAltitudeM"] = routeAltitudeM;
    QJsonArray arr;
    for (const QVariant& v : days) arr.append(QJsonValue::fromVariant(v));
    root["days"] = arr;

    // QSaveFile: 写完才改名. 裸 QFile 写一半被系统杀了 (低内存/更新), 下次读到截断 JSON,
    //   整份缓存作废 → 离线时连旧读数都没有。
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly)) {
        Logger::warn(QString("WeatherForecastService: cannot open cache for write: %1 (%2)")
                     .arg(path, f.errorString()));
        return;
    }
    f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    if (!f.commit()) {
        Logger::warn(QString("WeatherForecastService: cache commit failed: %1").arg(path));
    }
}

} // namespace outdoor
