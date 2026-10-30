/**
 * @file TrackMetrics.h
 * @brief 轨迹统计的唯一定口径 (距离 / 累计爬升下降 / 最高最低 / 最快 / 精度画像)
 *
 * 2026-10-29 #168 (A44): 原来同一套数字有两份写法 —— stopTrack 逐点累加 |Δ高程|
 * (GPS 抖一下就记一次爬升, 列表与"爬升"排序用它), getTrackStats 用 1 m 死区
 * (概要面板与详情页用它)。两份都不是对的, 而且对同一条轨迹给两个答案:
 *   实测两步路 2026-10-25 藏龙涧 (12552 点, 平均 0.7 s 一点) ——
 *     文件自述 爬升 445 m / 下降 529 m / 平均 0.68 m/s,
 *     死区口径   爬升 20 m / 下降 12 m (0.7 s 里高度差本来就 <1 m, 全被死区吃掉),
 *     最快       19.2 m/s = 69 km/h (一个 GPS 抖动除以 0.7 s)。
 * 收成一个函数, 三个口径一起换:
 *   * 升降: 按**水平距离**开 ±60 m 滑动平均, 再累加平滑曲线的差 —— 与采样率无关。
 *     逐点死区的错在于它的意义是"两次采样之间", 而采样间隔是设备给的, 不是地形给的。
 *   * 最快速度: 只认**时间跨度 >= 30 s 且首末位移 >= 30 m** 的窗口, 速度按窗口的
 *     首末直线位移 / 时间跨度算 (路径长度会把抖动一段段累加进去, 位移不会),
 *     取所有窗口里最大的那个。单段抖动不再能当速度。达不到这个跨度 (整条太短 /
 *     没有时刻) 就是测不出, 返回 hasMaxSpeed=false, 界面整格不出现
 *     —— 见 [[no-fake-readout-rule]]。
 *     逐点的同一条窗口序列 (movingSpeedMs) 一并给出, 剖面曲线用它: 曲线画逐段速度
 *     时峰值标着 19 m/s 而"最快"读数说 2.6, 看着像又一处算错 —— 同一条序列
 *     才有得对账。
 *   * 两步路导出的 KML 在 <Document><ExtendedData> 里写了自己算的
 *     ElevationGain/ElevationLoss —— 那是它 App 里显示的数, 用户拿它对账,
 *     所以有就优先用它, 没有才用上面的平滑值。这条优先级写在调用方 (见 .cpp 注释)。
 */
#ifndef OUTDOOR_TRACKMETRICS_H
#define OUTDOOR_TRACKMETRICS_H

#include <QJsonArray>
#include <QVector>
#include <QtGlobal>

namespace outdoor {
namespace track {

// 升降平滑窗口的半径 (水平距离, m)
constexpr double kAltSmoothWindowM = 60.0;
// 最快速度的最小窗口: 时间跨度 >= 30 s, 且这段位移 >= 30 m (才算真走过的一段)
constexpr qint64 kMinSpeedWindowMs = 30000;
constexpr double kMinSpeedWindowM = 30.0;
// 休息点判定用的窗口 (10 s), 不设位移门槛 —— 静止的读数就是要接近 0
constexpr qint64 kRestWindowMs = 10000;

/**
 * @struct Sample
 * @brief 一个轨迹采样点。alt/acc 为 NaN = 那一帧没给 (不拿 0 充数);
 *        tsMs = -1 = 没给时刻。
 */
struct Sample {
    double lat = 0.0;
    double lon = 0.0;
    double alt = qQNaN();
    double acc = qQNaN();
    qint64 tsMs = -1;
};

/**
 * @struct Metrics
 * @brief 一条轨迹的全部汇总读数 + 逐点数组 (分段配速/休息点由调用方在其上继续算)
 */
struct Metrics {
    double distanceM = 0.0;
    double gainM = 0.0;
    double lossM = 0.0;
    double maxAltM = 0.0;
    double minAltM = 0.0;
    bool hasAltitude = false;
    double maxSpeedMs = 0.0;
    bool hasMaxSpeed = false;
    double accuracyAvgM = 0.0;
    double accuracyBestM = 0.0;
    double accuracyWorstM = 0.0;
    int accuracyCount = 0;
    QVector<double> distAtPoint;      // 到该点的累计距离 (m), 与输入等长
    QVector<double> speedAtPoint;     // 单段速度 (m/s), 没有时刻的段是 0
    QVector<double> restSpeedMs;      // 该点起手的 >=10 s 短窗位移速度 (休息点判定), 凑不齐窗口 -1
    QVector<double> movingSpeedMs;    // 该点起手的 >=30 s/30 m 窗位移速度; 峰值 == maxSpeedMs
    QVector<qint64> tsAtPointMs;      // 原样带出的时刻 (ms), -1 = 未知
};

/**
 * @brief 把 track_<id>_points.json 的数组读成 Sample 列表
 * @param points 落盘的点数组 (键: lat/lon/elevation/accuracy/timestamp)
 * @return 与 points 等长的样本列表
 *
 * elevation/accuracy 键缺失或非数字 → NaN; timestamp 解析不出来 → -1。
 */
QVector<Sample> samplesFromJson(const QJsonArray& points);

/**
 * @brief 按上面的三个口径汇总一条轨迹
 * @param samples samplesFromJson() 的产物
 * @return 汇总读数
 */
Metrics compute(const QVector<Sample>& samples);

}  // namespace track
}  // namespace outdoor

#endif  // OUTDOOR_TRACKMETRICS_H
