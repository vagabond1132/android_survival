/**
 * @file test_track_metrics.cpp
 * @brief outdoor::track 的口径单元测试 (2026-10-29 #168 A44)
 *
 * 钉的是用户报的那一句「导入的两步路数据累计爬升/下降不正确, 最快速度也不正确」。
 * 真文件 2026-10-25 藏龙涧: 12552 点、平均 0.7 s 一点、8505 m, 自述爬升 445 m ——
 *   逐点累加 |Δ高程| 会被 GPS 抖动顶虚, 1 m 逐点死区只剩 20 m,
 *   单段最大速度读出 19.2 m/s (69 km/h)。
 * 新口径: 升降按水平距离 ±60 m 滑动平均 (与采样率无关), 最快速度只认
 *   >=30 s 且首末位移 >=30 m 的窗口 (位移, 不是路径长度)。
 *
 * 每条"不该出现"的断言都配一条"该出现"的反证, 否则函数整个坏掉 (全回 0) 也算通过
 *   —— 见 [[qml-check-zero-result-rule]]。
 */
#include <QtTest>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonObject>

#include <cmath>
#include <functional>
#include <limits>

#include "src/common/TrackMetrics.h"

using namespace outdoor::track;

namespace {

constexpr double kLat = 36.3;
// 赤道上 1° 经线的近似宽度按本地纬度缩一下: 36.3°N ≈ 89.7 km/°
double mPerDegLon() { return 111320.0 * std::cos(kLat * M_PI / 180.0); }

/**
 * 造一条"一路向东"的轨迹:
 *   eastFn(i) = 第 i 点相对首点的向东位移 (m)
 *   altFn(i)  = 第 i 点高程; 返回 NaN = 这一帧没给高程 (整键不写, 与落盘口径一致)
 *   dtMs <= 0 = 文件没给时刻 (整键不写)
 */
QJsonArray buildTrack(int n, const std::function<double(int)>& eastFn,
                      qint64 dtMs, const std::function<double(int)>& altFn)
{
    QJsonArray arr;
    for (int i = 0; i < n; ++i) {
        QJsonObject p;
        p.insert(QStringLiteral("lat"), kLat);
        p.insert(QStringLiteral("lon"), 117.1 + eastFn(i) / mPerDegLon());
        const double alt = altFn(i);
        if (std::isfinite(alt)) p.insert(QStringLiteral("elevation"), alt);
        if (dtMs > 0) {
            p.insert(QStringLiteral("timestamp"),
                     QDateTime::fromMSecsSinceEpoch(1760000000000LL + dtMs * i)
                         .toString(Qt::ISODate));
        }
        arr.append(p);
    }
    return arr;
}

QVector<Sample> samplesOf(const QJsonArray& arr) { return samplesFromJson(arr); }

// 老口径 (逐点累加 |Δ高程|) 在同一批数据上会得到什么 —— 用作反证:
// 新结果小, 是因为抖动被摊掉了, 不是因为函数压根没算.
double rawAbsAltSum(const QVector<Sample>& s)
{
    double v = 0.0;
    for (int i = 1; i < s.size(); ++i) {
        if (std::isfinite(s[i].alt) && std::isfinite(s[i - 1].alt)) {
            v += std::abs(s[i].alt - s[i - 1].alt);
        }
    }
    return v;
}

double seriesMax(const QVector<double>& v)
{
    double m = -std::numeric_limits<double>::infinity();
    for (double x : v) m = std::max(m, x);
    return m;
}

const double kNaN = std::numeric_limits<double>::quiet_NaN();

}  // namespace

class TestTrackMetrics : public QObject {
    Q_OBJECT

private slots:
    // 平地 ±1.5 m 抖动, 0.7 s 一点 (两步路的节拍)。
    //   逐点累加 |Δ高程| = 177 m 爬升 (那条路其实一步没登), 距离窗平滑后必须回到 0。
    void test_flatJitterIsNotReadAsClimb() {
        const QJsonArray pts = buildTrack(60, [](int i) { return 0.84 * i; }, 700,
                                          [](int i) { return 500.0 + ((i % 2) ? 1.5 : -1.5); });
        const QVector<Sample> s = samplesOf(pts);
        const Metrics m = compute(s);

        QVERIFY2(rawAbsAltSum(s) > 150.0,
                 qPrintable(QStringLiteral("反证数据没造出来: 逐点 |Δ| 只有 %1 m")
                                .arg(rawAbsAltSum(s))));
        QVERIFY2(m.gainM < 1.0, qPrintable(QStringLiteral("抖动被读成爬升 %1 m").arg(m.gainM)));
        QVERIFY2(m.lossM < 1.0, qPrintable(QStringLiteral("抖动被读成下降 %1 m").arg(m.lossM)));
        // 最高/最低照样是抖动的两个档, 不是 0
        QCOMPARE(m.maxAltM, 501.5);
        QCOMPARE(m.minAltM, 498.5);
        QVERIFY2(m.hasAltitude, "每点都带高程, hasAltitude 应为 true");
    }

    // 真爬升不能被平滑吃掉: 点间隔 (100 m) 比窗口 (±60 m) 宽时, 平滑等于原值。
    void test_realClimbSurvivesSmoothing() {
        const QJsonArray pts = buildTrack(21, [](int i) { return 100.0 * i; }, 10000,
                                          [](int i) { return 500.0 + 20.0 * i; });
        const Metrics m = compute(samplesOf(pts));
        QVERIFY2(std::abs(m.gainM - 400.0) < 1e-6,
                 qPrintable(QStringLiteral("400 m 的坡算成 %1 m").arg(m.gainM)));
        QVERIFY2(m.lossM < 1e-6, qPrintable(QStringLiteral("一路向上却有 %1 m 下降").arg(m.lossM)));
    }

    // 与采样率无关: 同一条 400 m 的坡, 10 m 一点 (带 ±3 m 抖动) 与 100 m 一点
    //   (干净) 都要读回 400 m 左右。老的两写法在这里分开: 逐点累加给出 1200 m,
    //   1 m 死区给出 800 m (每条都是 4 m/8 m 的台阶, 只有奇数步过门槛)。
    void test_gainIsSamplingRateIndependent() {
        const QJsonArray coarse = buildTrack(21, [](int i) { return 100.0 * i; }, 10000,
                                             [](int i) { return 500.0 + 20.0 * i; });
        const QJsonArray dense = buildTrack(201, [](int i) { return 10.0 * i; }, 1000,
                                            [](int i) {
                                                return 500.0 + 2.0 * i
                                                       + ((i % 2) ? 3.0 : -3.0);
                                            });
        const QVector<Sample> denseSamples = samplesOf(dense);
        const Metrics coarseM = compute(samplesOf(coarse));
        const Metrics denseM = compute(denseSamples);

        QVERIFY2(rawAbsAltSum(denseSamples) > 800.0,
                 qPrintable(QStringLiteral("反证: 逐点累加只给 %1 m, 抖动没造出来")
                                .arg(rawAbsAltSum(denseSamples))));
        QVERIFY2(std::abs(denseM.gainM - 400.0) < 20.0,
                 qPrintable(QStringLiteral("密采 400 m 的坡读成 %1 m").arg(denseM.gainM)));
        QVERIFY2(std::abs(coarseM.gainM - denseM.gainM) < 20.0,
                 qPrintable(QStringLiteral("同一座山, 疏密两种采样差 %1 m")
                                .arg(std::abs(coarseM.gainM - denseM.gainM))));
    }

    // 中间一段没有高程: 不许把缺的读成 0 米再跨过去算出 800 m 下降。
    void test_altitudeGapDoesNotFabricateDrop() {
        const QJsonArray pts = buildTrack(30, [](int i) { return 100.0 * i; }, 5000,
                                          [](int i) {
                                              if (i >= 10 && i < 20) return kNaN;
                                              return (i < 10) ? 100.0 : 900.0;
                                          });
        const Metrics m = compute(samplesOf(pts));
        QVERIFY2(m.hasAltitude, "前后两段都有高程, hasAltitude 应为 true");
        QCOMPARE(m.maxAltM, 900.0);
        QCOMPARE(m.minAltM, 100.0);
        // 跨缺口的 800 m 不算爬升也不算下降 (没有配对的差), 整条读 0 —— 这是"不编"
        QVERIFY2(m.gainM < 1e-6, qPrintable(QStringLiteral("跨高程缺口编出 %1 m 爬升").arg(m.gainM)));
        QVERIFY2(m.lossM < 1e-6, qPrintable(QStringLiteral("跨高程缺口编出 %1 m 下降").arg(m.lossM)));
        // 反证: 轨迹本身照样被算进去了, 不是整条没跑
        QVERIFY2(m.distanceM > 2800.0 && m.distanceM < 3000.0,
                 qPrintable(QStringLiteral("距离=%1").arg(m.distanceM)));
    }

    // 一个点向东跳 3 m 又回来 (GPS 抖动): 逐段速度读到 4.5 m/s, 窗口把它摊回 1.6。
    void test_maxSpeedIgnoresSinglePointJitter() {
        const QJsonArray pts = buildTrack(100, [](int i) {
                                             return 1.5 * i + ((i == 50) ? 3.0 : 0.0);
                                         }, 1000, [](int) { return 500.0; });
        const Metrics m = compute(samplesOf(pts));

        QVERIFY2(seriesMax(m.speedAtPoint) > 4.0,
                 qPrintable(QStringLiteral("反证: 抖动没进数据, 逐段最大只有 %1")
                                .arg(seriesMax(m.speedAtPoint))));
        QVERIFY2(m.hasMaxSpeed, "100 s 的连续采样应该有可测的最快速度");
        QVERIFY2(m.maxSpeedMs < 2.5,
                 qPrintable(QStringLiteral("单点抖动被当成最快: %1 m/s").arg(m.maxSpeedMs)));
        QVERIFY2(m.maxSpeedMs > 1.2,
                 qPrintable(QStringLiteral("真步速 1.5 m/s 却只读出 %1").arg(m.maxSpeedMs)));
        QVERIFY2(m.distanceM > 150.0 && m.distanceM < 154.0,
                 qPrintable(QStringLiteral("距离=%1").arg(m.distanceM)));
    }

    // 全程没有时刻: 速度整类测不出 —— 键不写 (hasMaxSpeed=false), 不许编节拍。
    void test_noTimestampsMeansNoSpeedReadout() {
        const QJsonArray pts = buildTrack(40, [](int i) { return 2.0 * i; }, -1,
                                          [](int) { return 500.0; });
        const Metrics m = compute(samplesOf(pts));
        QVERIFY2(!m.hasMaxSpeed, "没有时刻却报出最快速度");
        QCOMPARE(m.maxSpeedMs, 0.0);
        for (double v : m.movingSpeedMs) QCOMPARE(v, -1.0);
        for (double v : m.restSpeedMs) QCOMPARE(v, -1.0);
        for (double v : m.speedAtPoint) QCOMPARE(v, 0.0);
        // 反证: 距离/升降照样算得出来, 不是整条没跑
        QVERIFY2(m.distanceM > 75.0, qPrintable(QStringLiteral("距离=%1").arg(m.distanceM)));
        QCOMPARE(m.tsAtPointMs.at(0), qint64(-1));
    }

    // 站着不动 + ±2.5 m 抖动: 单段速度 5 m/s, 10 s 窗口必须掉回 ~0 (休息点判定的依据)。
    void test_stationaryReadsAsRestNotSpeed() {
        const QJsonArray pts = buildTrack(60, [](int i) {
                                             return ((i % 2) ? 2.5 : -2.5);
                                         }, 1000, [](int) { return 500.0; });
        const Metrics m = compute(samplesOf(pts));

        QVERIFY2(seriesMax(m.speedAtPoint) > 4.0,
                 qPrintable(QStringLiteral("反证: 静止抖动没造出来, 逐段最大 %1")
                                .arg(seriesMax(m.speedAtPoint))));
        QVERIFY2(seriesMax(m.restSpeedMs) < 0.3,
                 qPrintable(QStringLiteral("站着不动的 10 s 窗口读出 %1 m/s")
                                .arg(seriesMax(m.restSpeedMs))));
        // 全程没走过 30 m, 所以"最快"这一格就该空着, 而不是把抖动报成速度
        QVERIFY2(!m.hasMaxSpeed, "原地抖动却报出了最快速度");
    }

    // 剖面曲线的峰值必须就是 maxSpeed: 两个数不一致时用户看到的正是"最快速度不正确"。
    void test_curveSeriesPeakEqualsMaxSpeed() {
        const QJsonArray pts = buildTrack(60, [](int i) {
                                             return (i < 30) ? 1.0 * i
                                                             : 29.0 + 3.0 * (i - 29);
                                         }, 1000, [](int) { return 500.0; });
        const Metrics m = compute(samplesOf(pts));
        QVERIFY2(m.hasMaxSpeed, "这段变速走应有可测的最快速度");
        const double peak = seriesMax(m.movingSpeedMs);
        QVERIFY2(peak > 0.0, qPrintable(QStringLiteral("反证: 曲线序列全空, peak=%1").arg(peak)));
        QCOMPARE(m.maxSpeedMs, peak);
    }

    // 缺键 / 非数字: 保持"未知", 不拿 0 充数。
    void test_missingOrBrokenKeysStayUnknown() {
        QJsonArray pts;
        QJsonObject a;
        a.insert(QStringLiteral("lat"), 36.3);
        a.insert(QStringLiteral("lon"), 117.1);
        a.insert(QStringLiteral("elevation"), QStringLiteral("abc"));  // 不是数字
        a.insert(QStringLiteral("accuracy"), -5.0);                     // 非正精度
        a.insert(QStringLiteral("timestamp"), QStringLiteral("not-a-time"));
        pts.append(a);
        QJsonObject b;
        b.insert(QStringLiteral("lat"), 36.3);
        b.insert(QStringLiteral("lon"), 117.1001);
        pts.append(b);   // 高程/精度/时刻全无

        const QVector<Sample> s = samplesOf(pts);
        QCOMPARE(s.size(), 2);
        QVERIFY(std::isnan(s[0].alt));
        QVERIFY(std::isnan(s[1].alt));
        // 精度非正 (-5) 由解析端照实留着, 挡住它的是汇总那一步: compute() 只认 > 0 的 ±,
        //   所以下面 accuracyCount == 0 才是这条的门 —— 别在解析层再加一道平白守卫。
        QCOMPARE(s[0].acc, -5.0);
        QCOMPARE(s[0].tsMs, qint64(-1));
        QCOMPARE(s[1].tsMs, qint64(-1));

        const Metrics m = compute(s);
        QVERIFY2(!m.hasAltitude, "一个高程都没有却报了 hasAltitude");
        QCOMPARE(m.gainM, 0.0);
        QCOMPARE(m.lossM, 0.0);
        QCOMPARE(m.accuracyCount, 0);
        QVERIFY2(m.distanceM > 0.0,
                 qPrintable(QStringLiteral("反证: 距离也没算 =%1").arg(m.distanceM)));
    }

    // 精度画像: 只汇总真的带了正数 ± 的点 (与改前的 stopTrack 同一判据)。
    void test_accuracyProfileIgnoresNonPositive() {
        const double accs[5] = { 4.0, 12.0, 0.0, 6.0, kNaN };
        QJsonArray pts;
        for (int i = 0; i < 5; ++i) {
            QJsonObject p;
            p.insert(QStringLiteral("lat"), 36.3);
            p.insert(QStringLiteral("lon"), 117.1 + 0.0001 * i);
            if (i == 2) p.insert(QStringLiteral("accuracy"), 0.0);
            else if (i == 4) { /* 整键不写 */ }
            else p.insert(QStringLiteral("accuracy"), accs[i]);
            pts.append(p);
        }
        const Metrics m = compute(samplesOf(pts));
        QCOMPARE(m.accuracyCount, 3);
        QCOMPARE(m.accuracyBestM, 4.0);
        QCOMPARE(m.accuracyWorstM, 12.0);
        QVERIFY2(std::abs(m.accuracyAvgM - (4.0 + 12.0 + 6.0) / 3.0) < 1e-9,
                 qPrintable(QStringLiteral("平均精度=%1").arg(m.accuracyAvgM)));
    }

    // 逐点累计距离: 单调、末点等于总距离 (分段配速与剖面曲线的横轴都靠它对齐)。
    void test_cumulativeDistanceMatchesTotal() {
        const QJsonArray pts = buildTrack(25, [](int i) { return 40.0 * i; }, 2000,
                                          [](int) { return 500.0; });
        const Metrics m = compute(samplesOf(pts));
        QCOMPARE(m.distAtPoint.size(), 25);
        QCOMPARE(m.distAtPoint.at(0), 0.0);
        for (int i = 1; i < m.distAtPoint.size(); ++i) {
            QVERIFY2(m.distAtPoint[i] > m.distAtPoint[i - 1],
                     qPrintable(QStringLiteral("累计距离在第 %1 点没有递增").arg(i)));
        }
        QVERIFY2(std::abs(m.distAtPoint.last() - m.distanceM) < 1e-9,
                 qPrintable(QStringLiteral("末点 %1 vs 总距离 %2")
                                .arg(m.distAtPoint.last()).arg(m.distanceM)));
        // 时刻序列原样带出: 每步 2 s
        QVERIFY2(m.tsAtPointMs.last() - m.tsAtPointMs.first() == 24 * 2000,
                 qPrintable(QStringLiteral("时刻序列没对齐: %1 → %2")
                                .arg(m.tsAtPointMs.first()).arg(m.tsAtPointMs.last())));
    }

    void test_emptyTrackIsSafe() {
        const Metrics m = compute(samplesFromJson(QJsonArray()));
        QCOMPARE(m.distanceM, 0.0);
        QCOMPARE(m.gainM, 0.0);
        QCOMPARE(m.lossM, 0.0);
        QVERIFY(!m.hasAltitude);
        QVERIFY(!m.hasMaxSpeed);
        QVERIFY(m.distAtPoint.isEmpty());
        // 单点轨迹: 没有段, 也就没有速度
        const Metrics one = compute(samplesFromJson(
            buildTrack(1, [](int) { return 0.0; }, 1000, [](int) { return 500.0; })));
        QCOMPARE(one.distanceM, 0.0);
        QVERIFY(!one.hasMaxSpeed);
        QVERIFY2(one.hasAltitude, "单点也带着高程");
        QCOMPARE(one.maxAltM, 500.0);
    }
};

QTEST_GUILESS_MAIN(TestTrackMetrics)
#include "test_track_metrics.moc"
