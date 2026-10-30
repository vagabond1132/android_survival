/**
 * @file WeatherForecastService.h
 * @brief 当前天气预报 (open-meteo 日预报) —— 装备推荐"环境条件"三源合流的第 2 源 (#154, 2026-10-28)
 *
 * 三源: 0 手填 / 1 十年实测常态 (climate_normals.json, 走 EquipmentService::climateFor)
 *       / 2 当前天气预报 (本服务). 本轮只做第 2 源的**服务层**, 页面接线是下一轮.
 *
 * 设计:
 *  - 产出的键与 climateFor() **同名同语义**, 装备引擎 (generateList) 不用改就能吃.
 *  - 档位阈值一份都不抄: 降水/湿度/风/紫外线/季节全部走 EquipmentService 的公开静态函数.
 *    日档与月档阈值不同是故意的 (月表存整月累计, 日预报存当天累计), 这里只许用 Daily 那组.
 *  - 直减率与紫外线增量从 EquipmentService 取 (真身在 climate_normals.json), 不在这儿抄常量.
 *  - 铁律「不给假读数」: 字段缺 / 请求失败 / JSON 不认识 → 整键不出现或整行不出现,
 *    绝不填 0、绝不填"刚刚". 旧缓存仍可显示, 但必须带 fetchedAtMs + ageMinutes 说明它多旧.
 *  - 磁盘缓存 30 分钟内直接复用不发请求; 失败/离线**保留旧缓存** (不清盘).
 *
 * 单位: windSpeed 一律 m/s (open-meteo 默认给 km/h, 进门就 /3.6); 温度 ℃; 降水 mm/天;
 *       相对湿度 %; 紫外线是无量纲指数.
 *
 * 网络只走 https, 所以不用改 android/res/xml/network_security_config.xml (那份白名单只管明文 http).
 */

#pragma once

#include <QObject>
#include <QByteArray>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2

class QNetworkAccessManager;
class QNetworkReply;

namespace outdoor {

class EquipmentService;

/**
 * @class WeatherForecastService
 * @brief open-meteo 日预报 → 装备引擎可用的天气读数
 */
class WeatherForecastService : public ServiceBase {
    // 2026-10-28: ServiceBase.h 里"子类不用再写 Q_OBJECT"那句注释是错的 —— 基类的 moc
    //   只替基类自己生成元对象代码, 子类的 signals / Q_INVOKABLE 不写这行全部注册不上
    //   (工程里 15 个 service 都自带, 这里照 MapService.h 的写法).
    Q_OBJECT

public:
    explicit WeatherForecastService(QObject* parent = nullptr);
    ~WeatherForecastService() override;

    /**
     * 海拔/紫外线修正的依据。传空指针 = 没有基线, 那就**不做海拔修正**:
     * 修不出依据时"原样"比"编一个修正量"诚实。
     */
    void setClimateBaseline(const EquipmentService* baseline);

    /**
     * 异步拉取 16 天日预报, 立即返回; 结果走 forecastUpdated / forecastFailed。
     * routeAltitudeM < 0 表示路线海拔未知, 不做海拔修正。
     * 30 分钟内已有同一坐标 + 同一海拔的缓存 → 复用缓存, 不发请求 (仍然 emit forecastUpdated)。
     */
    Q_INVOKABLE void refresh(double lat, double lon, double routeAltitudeM);

    /**
     * 某一天 (dateIso 形如 2026-10-28) 的读数。
     * 引擎侧键: tempAvg tempMin windSpeed uvIndex precipitation humidity
     *            diurnalRange season isRainySeason windLevel uvLevel
     * 来源侧键: forecastDate fetchedAtMs ageMinutes forecastElevationM
     *            forecastPrecipMm forecastRhPct forecastPrecipProbPct source(="forecast")
     * 单个字段缺测 → 该键**不出现** (调用方要按 contains() 判断, 不要 `|| 0` 兜底);
     * 整天取不到 → 返回**空 map** —— 不拿别的日期凑一份"温度 0℃ 风 0 级"的天气。
     */
    Q_INVOKABLE QVariantMap forecastFor(const QString& dateIso) const;

    /// 已缓存的逐日读数 (按日期升序; 每项键集同 forecastFor)
    Q_INVOKABLE QVariantList forecastDays() const;

    /**
     * 纯解析 + 换算, 不发网络、不碰磁盘 —— 单测直接喂 fixture 用。
     * lapseCPerKm / uvPerKm 由调用方给 (服务内部从 EquipmentService 取), 便于单测注入。
     * body 不是合法 JSON、没有 daily 段或一段都用不了 → 返回空列表。
     */
    static QVariantList parseDailyJson(const QByteArray& body,
                                        qint64 fetchedAtMs,
                                        double routeAltitudeM,
                                        double lapseCPerKm,
                                        double uvPerKm);

signals:
    /// 缓存或新数据已可用 (不区分"刚拉到的"和"30 分钟内的", 由 ageMinutes 说明)
    void forecastUpdated();

    /// 拉取失败 (坐标非法 / 网络错误 / HTTP 非 2xx / 数据不认识)。旧读数保持不变。
    void forecastFailed(const QString& reason);

private slots:
    void onForecastReply_();

private:
    /// 缓存文件全路径: AppDataLocation/weather_forecast/<纬度>_<经度>.json
    QString cachePathFor_(double lat, double lon) const;
    QVariantList loadCache_(const QString& path, qint64* fetchedAtMs, double* routeAltitudeM) const;
    void saveCache_(const QString& path, qint64 fetchedAtMs, double routeAltitudeM,
                    const QVariantList& days);
    /// 发请求 (同一格点换海拔重拉: 旧读数是按旧海拔修正过的, 不能当新数用)
    void startRequest_(double lat, double lon, double routeAltitudeM, const QString& path);
    /// 读取时现算 ageMinutes: 缓存放久了, 里面写死的 0 就成了假读数
    static QVariantMap withFreshAge_(const QVariantMap& day);

    QNetworkAccessManager* m_nam = nullptr;
    QNetworkReply* m_reply = nullptr;

    QString m_loadedPath;         ///< 当前 m_days 来自哪个缓存文件 (换坐标就重新加载)
    qint64 m_loadedFetchedAtMs = 0;
    double m_loadedAltitudeM = -1.0;
    QVariantList m_days;          ///< 每行是最终键集 (含 fetchedAtMs)

    QString m_pendingPath;        ///< 本次请求落地到哪个缓存文件
    double m_pendingAltitudeM = -1.0;

    double m_lapseCPerKm = 0.0;   ///< ℃/1000m, setClimateBaseline 注入; 0 = 不修正
    double m_uvPerKm = 0.0;       ///< 每 1000m 紫外线比例增量; 0 = 不修正
};

} // namespace outdoor
