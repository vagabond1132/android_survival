/**
 * @file TrackMetrics.cpp
 * @brief TrackMetrics.h 那三个口径的实现 (见头注释里的实测数字)
 */
#include "TrackMetrics.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonValue>
#include <QString>

#include <algorithm>
#include <cmath>
#include <limits>

namespace outdoor {
namespace track {

namespace {

constexpr double kNaN = std::numeric_limits<double>::quiet_NaN();

bool isNum(double v) { return std::isfinite(v); }

// Haversine 距离 (m)。与 MapService_species.cpp 里那一份同式, 收到这里后两边共用。
double haversineM(double lat1, double lon1, double lat2, double lon2)
{
    constexpr double R = 6371000.0;
    constexpr double deg2rad = M_PI / 180.0;
    const double dLat = (lat2 - lat1) * deg2rad;
    const double dLon = (lon2 - lon1) * deg2rad;
    const double sLat = std::sin(dLat / 2.0);
    const double sLon = std::sin(dLon / 2.0);
    const double a = sLat * sLat
                   + std::cos(lat1 * deg2rad) * std::cos(lat2 * deg2rad) * sLon * sLon;
    return 2.0 * R * std::atan2(std::sqrt(a), std::sqrt(1.0 - a));
}

// 每个起点 a 取"时间跨度刚好够 minMs"的第一个窗口, 速度 = 首末点直线位移 / 跨度。
// 用**位移**而不是窗口内的路径长度: 抖动是按段累加的 (站着不动 0.7 s 一个点,
// 30 s 能"走出"几十米), 位移不会 —— 同一个窗口里抖动互相抵消。代价是急转弯
// (之字道) 那段读得偏保守, 但宁保守不要编出 69 km/h。
// 位移还要 >= minM 才算一个"真的走过"的窗口 (minM=0 表示不设门槛, 静止也照实记 0)。
// 够不着窗口 (后面没有带时刻的点) 该格留 -1 = 未知。
// end 只前进不回退 —— 起点越往后, 需要的终点也越往后, 整趟 O(n)
// (藏龙涧那条有 12552 个点)。outMax 非空时顺手记所有起点里最大的那一个。
void windowSpeeds(const QVector<Sample>& s, qint64 minMs, double minM,
                  QVector<double>& out, double* outMax)
{
    const int n = s.size();
    out.assign(n, -1.0);
    int end = 0;
    double best = 0.0;
    for (int a = 0; a < n; ++a) {
        if (s[a].tsMs < 0) { if (end < a + 1) end = a + 1; continue; }
        if (end < a + 1) end = a + 1;
        while (end < n && (s[end].tsMs < 0 || s[end].tsMs - s[a].tsMs < minMs)) ++end;
        if (end >= n) continue;
        const qint64 dtMs = s[end].tsMs - s[a].tsMs;
        if (dtMs <= 0) continue;
        const double chord = haversineM(s[a].lat, s[a].lon, s[end].lat, s[end].lon);
        const double v = chord / (dtMs / 1000.0);
        out[a] = v;
        if (chord >= minM && v > best) best = v;
    }
    if (outMax) *outMax = best;
}

}  // namespace

QVector<Sample> samplesFromJson(const QJsonArray& points)
{
    QVector<Sample> out;
    out.reserve(points.size());
    for (const QJsonValue& v : points) {
        const QJsonObject p = v.toObject();
        Sample s;
        s.lat = p[QStringLiteral("lat")].toDouble();
        s.lon = p[QStringLiteral("lon")].toDouble();
        // 键不存在 = 那一帧后端没给, 保持 NaN; 读成 0 会把"最低点 0 米"编出来
        if (p.contains(QStringLiteral("elevation"))
            && p[QStringLiteral("elevation")].isDouble()) {
            s.alt = p[QStringLiteral("elevation")].toDouble();
        }
        if (p.contains(QStringLiteral("accuracy"))
            && p[QStringLiteral("accuracy")].isDouble()) {
            s.acc = p[QStringLiteral("accuracy")].toDouble();
        }
        const QString ts = p[QStringLiteral("timestamp")].toString();
        if (!ts.isEmpty()) {
            const QDateTime dt = QDateTime::fromString(ts, Qt::ISODate);
            if (dt.isValid()) s.tsMs = dt.toMSecsSinceEpoch();
        }
        out.append(s);
    }
    return out;
}

Metrics compute(const QVector<Sample>& samples)
{
    Metrics m;
    const int n = samples.size();
    m.distAtPoint.assign(n, 0.0);
    m.speedAtPoint.assign(n, 0.0);
    m.restSpeedMs.assign(n, -1.0);
    m.movingSpeedMs.assign(n, -1.0);
    m.tsAtPointMs.assign(n, -1);
    if (n == 0) return m;

    // === 累计距离 / 单段速度 ===
    double total = 0.0;
    m.tsAtPointMs[0] = samples[0].tsMs;
    for (int i = 1; i < n; ++i) {
        const double seg = haversineM(samples[i - 1].lat, samples[i - 1].lon,
                                      samples[i].lat, samples[i].lon);
        total += seg;
        m.distAtPoint[i] = total;
        m.tsAtPointMs[i] = samples[i].tsMs;
        double v = 0.0;
        if (samples[i - 1].tsMs >= 0 && samples[i].tsMs >= 0) {
            const qint64 dtMs = samples[i].tsMs - samples[i - 1].tsMs;
            if (dtMs > 0) v = seg / (dtMs / 1000.0);
        }
        m.speedAtPoint[i] = v;
    }
    m.distanceM = total;

    // === 最高/最低高程 + 精度画像 ===
    double accSum = 0.0, accBest = kNaN, accWorst = kNaN;
    int accCount = 0;
    for (int i = 0; i < n; ++i) {
        const double alt = samples[i].alt;
        if (isNum(alt)) {
            if (!m.hasAltitude) { m.maxAltM = alt; m.minAltM = alt; m.hasAltitude = true; }
            else { m.maxAltM = std::max(m.maxAltM, alt); m.minAltM = std::min(m.minAltM, alt); }
        }
        const double a = samples[i].acc;
        if (isNum(a) && a > 0) {
            accSum += a;
            ++accCount;
            accBest = std::isnan(accBest) ? a : std::min(accBest, a);
            accWorst = std::isnan(accWorst) ? a : std::max(accWorst, a);
        }
    }
    m.accuracyCount = accCount;
    if (accCount > 0) {
        m.accuracyAvgM = accSum / accCount;
        m.accuracyBestM = accBest;
        m.accuracyWorstM = accWorst;
    }

    // === 升降: 按水平距离 ±60 m 滑动平均后再累加差值 ===
    // 窗口按"米"而不是按"点数"开, 才与采样率无关; 平滑完就不再叠死区 ——
    // 死区的意义是"两次采样之间", 而采样间隔是设备给的, 不是地形给的。
    if (m.hasAltitude) {
        QVector<double> smooth(n, kNaN);
        int lo = 0, hi = -1;
        double sum = 0.0;
        int count = 0;
        for (int i = 0; i < n; ++i) {
            while (hi + 1 < n && m.distAtPoint[hi + 1] - m.distAtPoint[i] <= kAltSmoothWindowM) {
                ++hi;
                if (isNum(samples[hi].alt)) { sum += samples[hi].alt; ++count; }
            }
            while (lo < hi && m.distAtPoint[i] - m.distAtPoint[lo] > kAltSmoothWindowM) {
                if (isNum(samples[lo].alt)) { sum -= samples[lo].alt; --count; }
                ++lo;
            }
            smooth[i] = count > 0 ? sum / count : kNaN;
        }
        double prev = kNaN;
        for (int i = 0; i < n; ++i) {
            if (!isNum(smooth[i])) { prev = kNaN; continue; }  // 整段没高程: 跨缺口不算升降
            if (isNum(prev)) {
                const double d = smooth[i] - prev;
                if (d > 0) m.gainM += d;
                else m.lossM += -d;
            }
            prev = smooth[i];
        }
    }

    // === 最快速度 (>=30 s 且位移 >=30 m 的窗口) + 休息点用的短窗 (>=10 s) ===
    //   两条序列都留在 Metrics 里: movingSpeedMs 的峰值就是 maxSpeedMs, 剖面曲线
    //   画的也是它 —— 曲线与读数必须是同一个数, 否则用户看到的是两处不一致。
    double best = 0.0;
    windowSpeeds(samples, kMinSpeedWindowMs, kMinSpeedWindowM, m.movingSpeedMs, &best);
    if (best > 0.0) {
        m.maxSpeedMs = best;
        m.hasMaxSpeed = true;
    }
    // 站着不动时单段速度会被 GPS 抖动顶到 0.5~1 m/s, 摊到 10 s 窗口就掉回真值。
    windowSpeeds(samples, kRestWindowMs, 0.0, m.restSpeedMs, nullptr);

    return m;
}

}  // namespace track
}  // namespace outdoor
