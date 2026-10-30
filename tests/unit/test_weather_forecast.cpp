/**
 * @file test_weather_forecast.cpp
 * @brief 当前天气预报 (#154 环境条件第 2 源): open-meteo 日预报 → 装备引擎的天气键
 *
 * 全部喂内嵌 fixture, 一次网络都不发。覆盖:
 *   - 键集与 EquipmentService::climateFor() 一致, 一个都不能少 (QML 按字符串取键, 漏键没有编译期约束)
 *   - windSpeed 由 km/h 换算成 m/s
 *   - 日降水走 precipitationBandDaily (与月档阈值不同), 夜间在零下换雪档
 *   - 湿度走 humidityBandFromRh (实测相对湿度, 不绕道降水)
 *   - 海拔修正: 格点 elevation → 路线海拔, 直减率取自 climate_normals.json
 *   - 缺测字段 (uv_index_max 为 null) → 整键不出现, 不给 0 这种假读数
 *   - 空 body / 非 JSON / 缺 daily 段 → 空列表
 *   - 30 分钟内命中磁盘缓存 → 不发请求, 且 ageMinutes 如实说明它多旧
 *   - 坐标非法 → 只报错, 不发请求
 *
 * 规矩: 每条"不含/为空"的断言都配一条正向断言反证, 否则过滤器挂了也是假绿。
 */
#include <QtTest>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QVariantList>
#include <QVariantMap>

#include "src/core/WeatherForecastService.h"
#include "src/equipment/EquipmentService.h"

using namespace outdoor;

namespace {

// 格点海拔 500m 的三天。第 2 天刻意为零下 + 5mm (雪) + uv null (缺测),
// 第 3 天刻意全晴无降水 (0.0 是真读数, 不是缺测)。
const char kFixture[] = R"JSON(
{
  "latitude": 30.67, "longitude": 104.07, "elevation": 500,
  "timezone": "Asia/Shanghai", "timezone_abbreviation": "GMT+8",
  "daily": {
    "time": ["2026-10-28", "2026-10-29", "2026-10-30"],
    "temperature_2m_max": [22.5, -8.0, 30.0],
    "temperature_2m_min": [12.5, -12.0, 20.0],
    "precipitation_sum": [6.0, 5.0, 0.0],
    "wind_speed_10m_max": [36.0, 0.1, 7.2],
    "relative_humidity_2m_mean": [80.0, 30.0, 45.0],
    "precipitation_probability_max": [55, 10, 5],
    "uv_index_max": [7.2, null, 9.0]
  }
}
)JSON";

qint64 nowMs() { return QDateTime::currentMSecsSinceEpoch(); }

/// 不做海拔修正的解析 (routeAltitudeM < 0 = 海拔未知)
QVariantList parsePlain(const QByteArray& body = QByteArray(kFixture)) {
    return WeatherForecastService::parseDailyJson(body, nowMs(), -1.0, 0.0, 0.0);
}

QVariantMap dayAt(const QVariantList& days, int i) {
    return i >= 0 && i < days.size() ? days.at(i).toMap() : QVariantMap();
}

} // namespace

class TestWeatherForecast : public QObject {
    Q_OBJECT

private slots:
    void keySetMatchesClimateFor() {
        // 修了海拔才给 forecastElevationM, 所以这条用 4000m 路线, 把 19 个键一次钉全
        const QVariantList days = WeatherForecastService::parseDailyJson(
            QByteArray(kFixture), nowMs(), 4000.0, -6.5, 0.12);
        QCOMPARE(days.size(), 3);
        const QVariantMap d = dayAt(days, 0);

        static const char* kKeys[] = {
            "tempAvg", "tempMin", "windSpeed", "uvIndex", "precipitation", "humidity",
            "diurnalRange", "season", "isRainySeason", "windLevel", "uvLevel",
            "forecastDate", "fetchedAtMs", "ageMinutes", "forecastElevationM",
            "forecastPrecipMm", "forecastRhPct", "forecastPrecipProbPct", "source",
        };
        for (const char* k : kKeys) {
            QVERIFY2(d.contains(QString::fromLatin1(k)), k);
        }
        QCOMPARE(d.value(QStringLiteral("source")).toString(), QStringLiteral("forecast"));
        QCOMPARE(d.value(QStringLiteral("forecastDate")).toString(), QStringLiteral("2026-10-28"));
        QCOMPARE(d.value(QStringLiteral("forecastElevationM")).toInt(), 4000);
        QCOMPARE(d.value(QStringLiteral("forecastPrecipMm")).toDouble(), 6.0);
        QCOMPARE(d.value(QStringLiteral("forecastRhPct")).toDouble(), 80.0);
        QCOMPARE(d.value(QStringLiteral("forecastPrecipProbPct")).toInt(), 55);
        QCOMPARE(d.value(QStringLiteral("fetchedAtMs")).toLongLong() > 0, true);
        // 季节按气象月: 10 月是秋
        QCOMPARE(d.value(QStringLiteral("season")).toInt(), static_cast<int>(Season::Autumn));
        // tempAvg 是 (max+min)/2 的代理值, diurnalRange 是 max-min
        const QVariantMap plain = dayAt(parsePlain(), 0);
        QCOMPARE(plain.value(QStringLiteral("tempAvg")).toDouble(), 17.5);
        QCOMPARE(plain.value(QStringLiteral("diurnalRange")).toInt(), 10);
        // 晴天 0.0mm 是真读数 (不是缺测), 走 None 档
        const QVariantMap clear = dayAt(parsePlain(), 2);
        QCOMPARE(clear.value(QStringLiteral("precipitation")).toInt(),
                 static_cast<int>(Precipitation::None));
        QCOMPARE(clear.value(QStringLiteral("forecastPrecipMm")).toDouble(), 0.0);
    }

    void windSpeedIsMetersPerSecond() {
        const QVariantList days = parsePlain();
        // 36 km/h → 10.0 m/s。忘了 /3.6 的话这里会读到 36, 风档也会从 Strong 跳到 Gale
        const QVariantMap d = dayAt(days, 0);
        QVERIFY(qAbs(d.value(QStringLiteral("windSpeed")).toDouble() - 10.0) < 0.05);
        QCOMPARE(d.value(QStringLiteral("windLevel")).toInt(),
                 static_cast<int>(WindLevel::Strong));
        // 7.2 km/h → 2.0 m/s → 微风 (正向对照: 换算不只在极端值上成立)
        const QVariantMap light = dayAt(days, 2);
        QVERIFY(qAbs(light.value(QStringLiteral("windSpeed")).toDouble() - 2.0) < 0.05);
        QCOMPARE(light.value(QStringLiteral("windLevel")).toInt(),
                 static_cast<int>(WindLevel::Light));
    }

    void precipitationUsesDailyBandNotMonthly() {
        // 6mm/天: 日档是 Moderate (2.5..10), 月档会读成 Light (<30) —— 用这个差口反证走的是 Daily
        const QVariantList days = parsePlain();
        QCOMPARE(dayAt(days, 0).value(QStringLiteral("precipitation")).toInt(),
                 static_cast<int>(Precipitation::Moderate));
        // 同一天在月档里落到 Light, 说明这个键确实没串到另一套阈值上
        QCOMPARE(EquipmentService::precipitationBandMonthly(6.0, 12.5),
                 static_cast<int>(Precipitation::Light));
    }

    void snowBandWhenTempMinBelowMinusOne() {
        const QVariantList days = parsePlain();
        // 5mm + 夜间 -12℃ → SnowModerate (冰爪/雪镜/雪套那批规则只认 snow_*)
        const QVariantMap snow = dayAt(days, 1);
        QCOMPARE(snow.value(QStringLiteral("precipitation")).toInt(),
                 static_cast<int>(Precipitation::SnowModerate));
        // 雪天不算"雨季": isRainySeason 判的是雨档 (1..4)
        QCOMPARE(snow.value(QStringLiteral("isRainySeason")).toBool(), false);
        // 正向对照: 同样 5~6mm 但在零上就是雨档, 且雨季标记为真
        const QVariantMap rain = dayAt(days, 0);
        QCOMPARE(rain.value(QStringLiteral("precipitation")).toInt(),
                 static_cast<int>(Precipitation::Moderate));
        QCOMPARE(rain.value(QStringLiteral("isRainySeason")).toBool(), true);
    }

    void humidityComesFromRelativeHumidity() {
        const QVariantList days = parsePlain();
        QCOMPARE(dayAt(days, 0).value(QStringLiteral("humidity")).toInt(),
                 static_cast<int>(HumidityType::Humid));     // rh 80
        QCOMPARE(dayAt(days, 2).value(QStringLiteral("humidity")).toInt(),
                 static_cast<int>(HumidityType::Moderate));  // rh 45
        QCOMPARE(dayAt(days, 1).value(QStringLiteral("humidity")).toInt(),
                 static_cast<int>(HumidityType::Dry));       // rh 30
    }

    void altitudeCorrectionUsesGridElevation() {
        const QVariantList plain = parsePlain();
        const QVariantList ridge = WeatherForecastService::parseDailyJson(
            QByteArray(kFixture), nowMs(), 4000.0, -6.5, 0.12);
        const QVariantMap p = dayAt(plain, 0);
        const QVariantMap r = dayAt(ridge, 0);

        // 格点 500m → 路线 4000m: 3.5km × -6.5℃/km = -22.75℃
        // 先在局部变量里算好: 这个断言原来括号多写了一层, 而且同一段表达式
        // 在断言和消息里各抄一遍, 抄错一次就是一处编译不过的括号数差
        const double plainAvg = p.value(QStringLiteral("tempAvg")).toDouble();
        const double ridgeAvg = r.value(QStringLiteral("tempAvg")).toDouble();
        QVERIFY2(qAbs((plainAvg - ridgeAvg) - 22.75) < 0.2,
                 qPrintable(QStringLiteral("均温差 %1, 期望 22.75").arg(plainAvg - ridgeAvg)));
        QVERIFY2(qAbs(r.value(QStringLiteral("tempMin")).toDouble()
                      - (12.5 - 22.75)) < 0.2,
                 qPrintable(QStringLiteral("路线夜间 %1").arg(r.value(QStringLiteral("tempMin")).toDouble())));
        // 摆幅是同一格点内的 max-min, 海拔修正两边同消 → 不该跟着变
        QCOMPARE(r.value(QStringLiteral("diurnalRange")).toInt(),
                 p.value(QStringLiteral("diurnalRange")).toInt());
        // 紫外线按 +12%/1000m 上浮: 7.2 × 1.42 = 10.2
        QVERIFY2(qAbs(r.value(QStringLiteral("uvIndex")).toDouble() - 10.2) < 0.15,
                 qPrintable(QStringLiteral("修正后 UV %1, 期望 10.2")
                                .arg(r.value(QStringLiteral("uvIndex")).toDouble())));
        // 温度修正影响雨/雪判定: 成都平原的雨在 4000m 落到雪档 (与 climateFor 同行为)
        QCOMPARE(r.value(QStringLiteral("precipitation")).toInt(),
                 static_cast<int>(Precipitation::SnowModerate));
        // 反向对照: 没修正时既没有 forecastElevationM, 也不该有
        QVERIFY(!p.contains(QStringLiteral("forecastElevationM")));
        QVERIFY(r.contains(QStringLiteral("forecastElevationM")));
    }

    void missingUvDropsWholeKey() {
        const QVariantList days = parsePlain();
        const QVariantMap d = dayAt(days, 1);   // uv_index_max 是 null
        QVERIFY2(!d.contains(QStringLiteral("uvIndex")), "uv 缺测不能填 0 (填 0 会被读成紫外线弱)");
        QVERIFY2(!d.contains(QStringLiteral("uvLevel")), "uvLevel 要跟着 uvIndex 一起缺席");
        // 但同一份响应里其它天的 uv 必须照常给出来 —— 证明不是整批被丢了
        const QVariantMap ok = dayAt(days, 0);
        QVERIFY(ok.contains(QStringLiteral("uvIndex")));
        QVERIFY(qAbs(ok.value(QStringLiteral("uvIndex")).toDouble() - 7.2) < 0.05);
        QCOMPARE(ok.value(QStringLiteral("uvLevel")).toInt(), static_cast<int>(UVLevel::Strong));
    }

    void unusableBodyYieldsNoRows() {
        QCOMPARE(parsePlain(QByteArray()).size(), 0);                 // 空 body
        QCOMPARE(parsePlain("not json at all").size(), 0);            // 非 JSON
        QCOMPARE(parsePlain("{}").size(), 0);                         // 整个没有 daily 段
        QCOMPARE(parsePlain(R"({"elevation":500,"daily":{}})").size(), 0);
        QCOMPARE(parsePlain(R"({"daily":{"time":[]}})").size(), 0);   // 有段但一行都没有
        // 正向对照: 同一调用方式喂真 fixture 就有行, 证明上面那些红不是"函数永远返回空"
        QCOMPARE(parsePlain().size(), 3);
    }

    void rowWithoutTemperatureIsDropped() {
        // 温度是这一行的地基 (tempAvg/tempMin/雨雪判定全靠它), 缺了整行不出现;
        // 其余字段缺了只删自己那个键。
        const QByteArray body = R"JSON(
          {"elevation": 500,
           "daily": {"time": ["2026-11-01", "2026-11-02"],
                     "temperature_2m_max": [20.0, null],
                     "temperature_2m_min": [10.0, null]}}
        )JSON";
        const QVariantList days =
            WeatherForecastService::parseDailyJson(body, nowMs(), -1.0, 0.0, 0.0);
        QCOMPARE(days.size(), 1);
        const QVariantMap d = dayAt(days, 0);
        QVERIFY2(!d.contains(QStringLiteral("precipitation")), "降水缺测不能填 0 档");
        QVERIFY2(!d.contains(QStringLiteral("isRainySeason")), "雨季标记由降水档派生, 一起缺席");
        QVERIFY2(!d.contains(QStringLiteral("windSpeed")), "风缺测同理");
        // 正向对照: 留下来的键仍然如实给出
        QVERIFY(d.contains(QStringLiteral("tempAvg")));
        QCOMPARE(d.value(QStringLiteral("season")).toInt(), static_cast<int>(Season::Autumn));
    }

    void staleReadoutSaysHowOldItIs() {
        const qint64 t = nowMs();
        const QVariantList old = WeatherForecastService::parseDailyJson(
            QByteArray(kFixture), t - 30LL * 60LL * 1000LL, -1.0, 0.0, 0.0);
        const QVariantMap d = dayAt(old, 0);
        QCOMPARE(d.value(QStringLiteral("fetchedAtMs")).toLongLong(), t - 30LL * 60LL * 1000LL);
        QVERIFY2(d.value(QStringLiteral("ageMinutes")).toInt() >= 29
                 && d.value(QStringLiteral("ageMinutes")).toInt() <= 30,
                 "半小时前拉的读数不能报 0 分钟");
        // 正向对照: 刚拉的那次确实该是 0 分钟, 否则上面那条红不出问题
        QCOMPARE(dayAt(parsePlain(), 0).value(QStringLiteral("ageMinutes")).toInt(), 0);
    }

    void cacheHitWithinTtlNeedsNoNetwork() {
        // 这条只验"命中缓存不发请求 + ageMinutes 现算", 请求路径一律不在单测里碰网络
        const double lat = 31.23, lon = 121.47;
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                            + QStringLiteral("/weather_forecast");
        const QString path = dir + QStringLiteral("/%1_%2.json")
                                 .arg(lat, 0, 'f', 2).arg(lon, 0, 'f', 2);
        QVERIFY2(QDir().mkpath(dir) || QDir(dir).exists(), qPrintable(dir));
        QFile::remove(path);   // 上一轮残留会让"首次"这条测不准

        QJsonObject row;
        row["forecastDate"] = QStringLiteral("2026-10-28");
        row["tempAvg"] = 20.0;
        row["source"] = QStringLiteral("forecast");
        row["ageMinutes"] = 0;   // 存盘时是 0; 读回来要按根上的 fetchedAtMs 现算, 不然就是假新鲜
        QJsonObject root;
        root["fetchedAtMs"] = static_cast<double>(nowMs() - 5LL * 60LL * 1000LL);
        root["routeAltitudeM"] = -1.0;
        root["days"] = QJsonArray{row};

        QFile f(path);
        QVERIFY2(f.open(QIODevice::WriteOnly), qPrintable(f.errorString()));
        f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
        f.close();

        WeatherForecastService svc;
        QSignalSpy updated(&svc, &WeatherForecastService::forecastUpdated);
        QSignalSpy failed(&svc, &WeatherForecastService::forecastFailed);
        svc.refresh(lat, lon, -1.0);
        QCOMPARE(updated.count(), 1);
        QCOMPARE(failed.count(), 0);

        const QVariantMap d = svc.forecastFor(QStringLiteral("2026-10-28"));
        QVERIFY(!d.isEmpty());
        QCOMPARE(d.value(QStringLiteral("tempAvg")).toDouble(), 20.0);
        QCOMPARE(d.value(QStringLiteral("ageMinutes")).toInt(), 5);
        QVERIFY2(d.value(QStringLiteral("fetchedAtMs")).toLongLong() > 0,
                 "行内的 fetchedAtMs 由根上的时刻补齐, 界面才说得清这数多旧");
        QCOMPARE(svc.forecastDays().size(), 1);
        // 正向对照上面那条"非空": 日期不在缓存里就得是空 map, 不拿别的日期凑
        QVERIFY(svc.forecastFor(QStringLiteral("2099-01-01")).isEmpty());
        QVERIFY(svc.forecastFor(QString()).isEmpty());

        QFile::remove(path);
    }

    void invalidCoordsFailWithoutRequest() {
        WeatherForecastService svc;
        QSignalSpy updated(&svc, &WeatherForecastService::forecastUpdated);
        QSignalSpy failed(&svc, &WeatherForecastService::forecastFailed);
        svc.refresh(123.0, 0.0, 500.0);      // 纬度越界
        svc.refresh(30.0, 200.0, 500.0);     // 经度越界
        QCOMPARE(updated.count(), 0);
        QCOMPARE(failed.count(), 2);
        // 工程规矩: 给用户的文案中文, 英文细节只进日志
        const QString reason = failed.at(0).at(0).toString();
        QVERIFY2(!reason.contains(QRegularExpression(QStringLiteral("[A-Za-z]"))),
                 qPrintable(reason));
        QVERIFY(svc.forecastDays().isEmpty());
    }
};

QTEST_MAIN(TestWeatherForecast)
#include "test_weather_forecast.moc"
