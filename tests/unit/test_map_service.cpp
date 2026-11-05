/**
 * @file test_map_service.cpp
 * @brief map/MapService 单元测试 (45 个 Q_INVOKABLE, 此前 0 覆盖)
 *
 * MapService 用 JSON 文件存储 (PathService::mapDir()), 不走 SQLite。
 * 测试通过 QStandardPaths::setTestModeEnabled 把 AppDataLocation 指向临时目录。
 *
 * 覆盖:
 *   - 海拔 5 段分级边界 (L0-L4) + 名称/颜色/区间
 *   - 记录频率选项 (5/10/15/30) 与档位持久化 (QSettings: track/frequencySec)
 *   - 轨迹生命周期 start → addPoint → stop → get → delete
 *     (0.0.9 真机补: 删除要点名发 trackDeleted, 地图页靠它摘掉已画的线)
 *   - 轨迹统计与海拔曲线
 *   - GPX 导入 / 导出回环, CSV 导入 (表头列名兼容)
 *   - 2026-10-27 #134 KML 导入: 两步路的 <gx:Track> (coord/when 两条平行列表按下标
 *     配对、名称取 <Document><name>、缺 when 不编节拍) 与 Google Earth/奥维的
 *     <LineString> 两条路, 外加 (0,0) 哨兵点拦截
 *   - 2026-10-27 #134 GPX/CSV 导入的"文件没给就留空": 无 <time>/无 time 列时
 *     startTime/endTime/逐点 timestamp 一律空, 缺高程那一格不写 0, 但距离/点数
 *     照常算出来 (顺序缺陷: 先 stopTrack 再落 meta 会让统计整体丢失)
 *   - 物种位置写入 + 矩形范围查询
 *   - 2026-10-26「精度到 1 m」: 采样点/标注点的坐标门 (NaN / 越界 / (0,0)),
 *     高程与 ± 精度未知时那一键整条不写, getTrackStats 的高程/精度汇总口径
 *   - 物种位置删除 deleteSpeciesLocation: 非法 id 拦截 / NotFound / 删完列表与
 *     speciesCount 同步回落 (2026-10-23 #113)
 *   - Result 契约 {ok, value, error} 与 NotFound / IoError 分支
 *   - getTrackPoints 的返回值在真 QML 引擎里可读 (2026-10-22 任务 #82)
 */
#include <QtTest>
#include <QCoreApplication>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QFile>
#include <QGeoCoordinate>
#include <QDateTime>            // 2026-10-27 #134: 核对 KML <when> 落成的逐点时刻
#include <QJsonArray>           // 2026-10-27 #134: 直接读落盘的 points.json 分得清"0 米"和"没测到"
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlExpression>
#include <cmath>              // std::isnan
#include <limits>             // 2026-10-26「精度到 1 m」: quiet_NaN 是"未知"的哨兵

#include "src/core/PathService.h"
#include "src/core/ServiceErrors.h"
#include "src/common/SettingsStore.h"  // 2026-10-29: 采样档位落 QSettings (track/frequencySec)
#include "src/map/MapService.h"
#include "fixtures/MapTestFixtures.h"

using namespace outdoor;

// "未知"的传法: NaN, 不是 -1 也不是 0 (见 MapService.h 里这两个形参的注释).
static const double kNaN = std::numeric_limits<double>::quiet_NaN();

class TestMapService : public QObject {
    Q_OBJECT

private:
    QTemporaryDir* m_tmpDir = nullptr;
    MapService* m_svc = nullptr;

    static bool isOk(const QVariantMap& r) { return r.value(QLatin1String("ok")).toBool(); }

    // QmlResultBridge 把 error 塞成 QVariant(ServiceError) 而非 QVariantMap
    static ServiceError errOf2(const QVariantMap& r) {
        const QVariant ev = r.value(QLatin1String("error"));
        if (ev.canConvert<ServiceError>()) return ev.value<ServiceError>();
        return {};
    }
    static QString errOf(const QVariantMap& r) {
        return ServiceError::codeToString(errOf2(r).code);
    }
    static QString errText(const QVariantMap& r) {
        const ServiceError e = errOf2(r);
        return QStringLiteral("code=%1 msg=%2").arg(ServiceError::codeToString(e.code), e.message);
    }

private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
        QCoreApplication::setOrganizationName(QStringLiteral("OutdoorTest"));
        QCoreApplication::setApplicationName(QStringLiteral("MapServiceTest"));
        m_tmpDir = new QTemporaryDir();
        QVERIFY(m_tmpDir->isValid());
        // 2026-10-29: 采样档位现在落 QSettings 了 —— 上一次跑到一半崩在这里就会把
        //   15/30 留在配置里, 下面那句"默认是 5"于是变成随机失败. 开局清一次.
        outdoor::SettingsStore::remove(QStringLiteral("track/frequencySec"));

        m_svc = new MapService();
        QVERIFY(m_svc->initialize());
        QVERIFY(QFileInfo::exists(PathService::mapDir()));
    }

    void cleanupTestCase() {
        delete m_svc;
        delete m_tmpDir;
    }

    // ===== 海拔分级 (5 段 L0-L4, 与 MapService::getAltitudeLevel 一致) =====
    void test_altitudeLevelBoundaries() {
        QCOMPARE(MapService::getAltitudeLevel(0.0), AltitudeLevel::L0);
        QCOMPARE(MapService::getAltitudeLevel(499.9), AltitudeLevel::L0);
        QCOMPARE(MapService::getAltitudeLevel(500.0), AltitudeLevel::L1);
        QCOMPARE(MapService::getAltitudeLevel(1499.9), AltitudeLevel::L1);
        QCOMPARE(MapService::getAltitudeLevel(1500.0), AltitudeLevel::L2);
        QCOMPARE(MapService::getAltitudeLevel(2500.0), AltitudeLevel::L3);
        QCOMPARE(MapService::getAltitudeLevel(3500.0), AltitudeLevel::L4);
        // 2026-10-21 (#18 C3): 原来这里写死 8848 → L4 "封顶", 是 MapService 自己那份
        //   5 段枚举的行为. 统一到 src/common/AltitudeLevel.h 的 7 段后, 与装备侧同读法:
        QCOMPARE(MapService::getAltitudeLevel(4500.0), AltitudeLevel::L5);
        QCOMPARE(MapService::getAltitudeLevel(5500.0), AltitudeLevel::L6);
        QCOMPARE(MapService::getAltitudeLevel(8848.0), AltitudeLevel::L6);
    }

    void test_altitudeLevelMetadata() {
        QCOMPARE(MapService::getAltitudeLevelName(AltitudeLevel::L0), QStringLiteral("低海拔"));
        QCOMPARE(MapService::getAltitudeLevelName(AltitudeLevel::L4), QStringLiteral("极高海拔"));
        // 颜色不在服务层 (C3 删掉了两个服务各自的 getAltitudeLevelColor):
        //   界面按 level 取 CommonOptions::altitudeColor, 单测在 test_common_options 里锁.
        QCOMPARE(MapService::getAltitudeLevelMin(AltitudeLevel::L1), 500.0);
        QCOMPARE(MapService::getAltitudeLevelMax(AltitudeLevel::L1), 1500.0);
    }

    // ===== 记录频率 (关键决策: 5/10/15/30 秒, 2026-10-28 #156 用户改档) =====
    void test_frequencyOptions() {
        const QVariantList opts = m_svc->getFrequencyOptions();
        QCOMPARE(opts.size(), 4);
        QStringList values;
        int defaults = 0;
        for (const QVariant& v : opts) {
            const QVariantMap m = v.toMap();
            // MapService::getFrequencyOptions 用 seconds/label/description/isDefault
            values << QString::number(m.value("seconds").toInt());
            QVERIFY(!m.value("label").toString().isEmpty());
            QVERIFY(!m.value("description").toString().isEmpty());
            if (m.value("isDefault").toBool()) ++defaults;
        }
        QCOMPARE(defaults, 1);  // 必须有且只有一个默认档
        // 外层括号不是风格: 大括号里的逗号会被预处理器当宏参数分隔, 不加就报
        // "QCOMPARE passed 5 arguments, but takes just 2"
        QCOMPARE(values, (QStringList{"5", "10", "15", "30"}));
        QVERIFY(!values.contains("2"));    // 旧档位已删: 2 秒耗电大
        QVERIFY(!values.contains("20"));
        for (int sec : {5, 10, 15, 30}) {
            QVERIFY2(!m_svc->getFrequencyLabel(sec).isEmpty(),
                     qPrintable(QStringLiteral("频率 %1 无标签").arg(sec)));
        }
        QCOMPARE(m_svc->getDefaultFrequency(), 5);
    }

    // ===== 采样档位持久化 (2026-10-29) =====
    // 「记录」Tab 的档位落在页面临时属性上时, 每次进页都回 5; 现在写进 QSettings,
    // 这条用例证明"选过就记得"以及"非法值污染不了设置"。
    void test_frequencyPersistence() {
        QCOMPARE(m_svc->getDefaultFrequency(), 5);        // initTestCase 刚清过
        m_svc->setFrequencySeconds(15);
        QCOMPARE(m_svc->getDefaultFrequency(), 15);       // 立刻读得回来 (不用重开进程)
        m_svc->setFrequencySeconds(2);                    // 旧档位已从清单里删掉
        QCOMPARE(m_svc->getDefaultFrequency(), 15);       // 非法值不覆盖已存档位
        m_svc->setFrequencySeconds(30);
        QCOMPARE(m_svc->getDefaultFrequency(), 30);
    }

    // ===== 格式化 helper =====
    void test_formatHelpers() {
        QVERIFY(m_svc->formatDistance(950).contains(QStringLiteral("m")));
        QVERIFY(m_svc->formatDistance(2500).contains(QStringLiteral("km")));
        // MapService::formatDuration 用中文 "N小时M分钟", 无冒号
        const QString dur = m_svc->formatDuration(3661);
        QVERIFY2(dur.contains(QStringLiteral("小时")) && dur.contains(QStringLiteral("分钟")),
                 qPrintable(dur));
        QVERIFY(!m_svc->formatElevation(1545).isEmpty());
    }

    // ===== 轨迹生命周期 =====
    void test_trackLifecycle() {
        const QVariantMap start = m_svc->startTrack(QStringLiteral("测试轨迹"), 10);
        QVERIFY2(isOk(start), qPrintable(errText(start)));
        const QString id = start.value(QLatin1String("value")).toString();
        QVERIFY(!id.isEmpty());

        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.250, 117.100, 150)));
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.252, 117.102, 650)));
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.254, 117.104, 1545)));

        const QList<QGeoCoordinate> pts = m_svc->getTrackPoints(id);
        QCOMPARE(pts.size(), 3);
        QCOMPARE(m_svc->getTrackElevations(id).size(), 3);

        const QVariantMap got = m_svc->getTrackById(id);
        QVERIFY2(isOk(got), qPrintable(errText(got)));
        QCOMPARE(got.value("value").toMap().value("name").toString(),
                 QStringLiteral("测试轨迹"));

        QVERIFY(isOk(m_svc->stopTrack(id)));

        const QVariantMap del = m_svc->deleteTrack(id);
        QVERIFY2(isOk(del), qPrintable(errText(del)));
        QVERIFY(!isOk(m_svc->getTrackById(id)));
    }

    // 0.0.9 真机 (删轨迹留幽灵选择): 删除只发了粗粒度的 dataChanged, 而 MapPage 拿它只刷
    //   物种标注, 于是地图上的画线与「已选 N」继续列着已经不存在的轨迹。修法是补一条点名
    //   到 id 的 trackDeleted —— 这里钉住"发了一次、带的就是被删的那条"。
    void test_deleteTrackEmitsTrackDeleted() {
        const QVariantMap start = m_svc->startTrack(QStringLiteral("信号轨迹"), 10);
        QVERIFY2(isOk(start), qPrintable(errText(start)));
        const QString id = start.value(QLatin1String("value")).toString();
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.250, 117.100, 150)));
        QVERIFY(isOk(m_svc->stopTrack(id)));

        QSignalSpy deletedSpy(m_svc, &MapService::trackDeleted);
        QVERIFY(deletedSpy.isValid());
        QVERIFY(isOk(m_svc->deleteTrack(id)));
        QCOMPARE(deletedSpy.count(), 1);
        QCOMPARE(deletedSpy.at(0).at(0).toString(), id);
    }

    void test_startTrackRejectsBlankName() {
        const QVariantMap r = m_svc->startTrack(QString());
        QVERIFY(!isOk(r));
    }

    void test_addTrackPointOnMissingTrackFails() {
        const QVariantMap r = m_svc->addTrackPoint(
            QStringLiteral("no_such_track"), 36.0, 117.0, 100);
        QVERIFY(!isOk(r));
    }

    // ===== 精度到 1 m (2026-10-26 批次) =====
    // 三条断言对着三个曾经真出过的假读数:
    //   ① 无权限/无读数时 (0,0) 与 NaN 坐标会被写成"落在几内亚湾的济南轨迹";
    //   ② 高程/精度未知写 0 → 界面读成"海平面 0 米 / 精度 0 米";
    //   ③ 统计把"没有这个键"读成 0 → 一条纯 2D 轨迹显示四个海拔读数.
    void test_trackPointRejectsInvalidCoordinates() {
        const QVariantMap start = m_svc->startTrack(QStringLiteral("坐标门测试"), 10);
        QVERIFY2(isOk(start), qPrintable(errText(start)));
        const QString id = start.value(QLatin1String("value")).toString();

        // NaN / 越界 / (0,0) 三类. (0,0) 是"无 GPS 时 currentLatitude 的默认值",
        // 不是合法坐标 —— 几内亚湾那个点就是这么攒出来的.
        for (const QVariantList bad : {QVariantList{kNaN, 117.0},
                                       QVariantList{36.0, kNaN},
                                       QVariantList{95.0, 117.0},
                                       QVariantList{36.0, 200.0},
                                       QVariantList{0.0, 0.0}}) {
            const QVariantMap r = m_svc->addTrackPoint(
                id, bad[0].toDouble(), bad[1].toDouble(), 100.0, 3.0);
            QVERIFY2(!isOk(r),
                     qPrintable(QStringLiteral("(%1,%2) 竟被收进轨迹")
                                    .arg(bad[0].toString(), bad[1].toString())));
            QCOMPARE(errOf(r), QStringLiteral("InvalidArgument"));
        }
        // 正向配对: 门只拦坏点, 好点照样进得去 (否则"全被拒"也能骗过上面对每条的断言)
        QVERIFY2(isOk(m_svc->addTrackPoint(id, 36.250, 117.100, 100.0, 3.0)),
                 "合法采样点不应被坐标门拦下");
        QCOMPARE(m_svc->getTrackPoints(id).size(), 1);
        QVERIFY(isOk(m_svc->deleteTrack(id)));
    }

    void test_trackStatsAccuracyAggregation() {
        const QVariantMap start = m_svc->startTrack(QStringLiteral("精度汇总"), 10);
        QVERIFY2(isOk(start), qPrintable(errText(start)));
        const QString id = start.value(QLatin1String("value")).toString();

        // 三个点都带 ±, 但中间那个精度未知 → 只有两个进汇总, 不拿 0 凑 third
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.250, 117.100, 150.0, 2.0)));
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.252, 117.102, 650.0, kNaN)));
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.254, 117.104, 1545.0, 6.0)));
        const QVariantMap s = m_svc->getTrackStats(id);
        QVERIFY2(isOk(s), qPrintable(QStringLiteral("统计失败: %1").arg(errText(s))));
        QCOMPARE(s.value("accuracyPointCount").toInt(), 2);
        QCOMPARE(s.value("accuracyAvgM").toDouble(), 4.0);
        QCOMPARE(s.value("accuracyBestM").toDouble(), 2.0);
        QCOMPARE(s.value("accuracyWorstM").toDouble(), 6.0);
        // 带高程 → hasAltitude 为真, 且真的写了最高/最低两个键
        QVERIFY2(s.value("hasAltitude").toBool(), "这条轨迹每个点都有高程, hasAltitude 应为 true");
        QVERIFY(s.contains("maxAlt"));
        QVERIFY(s.contains("minAlt"));

        QVERIFY(isOk(m_svc->deleteTrack(id)));
    }

    // 全程没有精度、也没有高程的一条轨迹: 这些键必须整条不出现, 界面据此不画格子.
    void test_trackStatsOmitsUnknownAltitudeAndAccuracy() {
        const QVariantMap start = m_svc->startTrack(QStringLiteral("纯 2D 轨迹"), 10);
        QVERIFY2(isOk(start), qPrintable(errText(start)));
        const QString id = start.value(QLatin1String("value")).toString();

        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.250, 117.100, kNaN, kNaN)));
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.252, 117.102, kNaN, kNaN)));
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.254, 117.104, kNaN, kNaN)));
        const QVariantMap s = m_svc->getTrackStats(id);
        QVERIFY2(isOk(s), qPrintable(errText(s)));
        // "不含"断言必须配一条"含": 否则 getTrackStats 整个坏掉也算通过
        QVERIFY2(s.contains("distanceM"), qPrintable(QStringLiteral("返回=%1").arg(errText(s))));
        QVERIFY2(s.value("hasAltitude").toBool() == false, "无高程轨迹不应报 hasAltitude");
        QVERIFY(!s.contains("maxAlt"));
        QVERIFY(!s.contains("minAlt"));
        QVERIFY(!s.contains("accuracyAvgM"));
        QVERIFY(!s.contains("accuracyBestM"));
        QVERIFY(!s.contains("accuracyWorstM"));
        QVERIFY(!s.contains("accuracyPointCount"));

        QVERIFY(isOk(m_svc->deleteTrack(id)));
    }

    // ===== QML 侧可读性 (2026-10-22 任务 #82) =====
    // MapPage.addOrToggleTrack 拿到 getTrackPoints 的返回值后直接写 pts[i].latitude,
    // 而它的 C++ 类型是 QList<QGeoCoordinate>, 不是 QVariantList —— 这条转换链以前
    // 只在 C++ 里测过, QML 侧从没验证过. 转换不认它就是空数组, 现象正好是
    // "轨迹 Tab 选了线, 地图什么都不画". 用真的 QQmlEngine 过一遍.
    void test_trackPointsReadableFromQml() {
        const QString id = m_svc->startTrack(QStringLiteral("QML可见轨迹"), 5)
                             .value(QLatin1String("value")).toString();
        QVERIFY(!id.isEmpty());
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.250, 117.100, 150)));
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.252, 117.102, 650)));
        QVERIFY(isOk(m_svc->stopTrack(id)));

        QQmlEngine engine;
        engine.rootContext()->setContextProperty(QStringLiteral("svc"), m_svc);
        engine.rootContext()->setContextProperty(QStringLiteral("tid"), id);
        // 通道自检: QQmlEngine::evaluate 走 JS 全局对象, 看不见 setContextProperty
        //   (首版就踩了, 得到 ReferenceError). 挂在 rootContext 上要用 QQmlExpression,
        //   并且先跑一条 1+1 证明这条通道本身是通的.
        {
            QQmlExpression probe(engine.rootContext(), nullptr, QStringLiteral("<unit-test>"));
            probe.setExpression(QStringLiteral("1 + 1"));
            const QVariant two = probe.evaluate();
            QVERIFY2(!probe.hasError(), "QML 表达式通道没打通");
            QCOMPARE(two.toInt(), 2);
        }

        // 表达式自己把失败原因写成字符串, 断言信息就能指出"是哪一步没读到".
        QQmlExpression expr(engine.rootContext(), nullptr, QStringLiteral("<unit-test>"));
        expr.setExpression(QStringLiteral(
            "(function () {"
            "  var p = svc.getTrackPoints(tid);"
            "  if (!p) return 'notAList';"
            "  if (p.length !== 2) return 'len=' + p.length;"
            "  if (typeof p[0].latitude !== 'number') return 'noLatitude:' + typeof p[0].latitude;"
            "  return p[0].latitude.toFixed(3) + '/' + p[0].longitude.toFixed(3)"
            "       + '/' + p[1].latitude.toFixed(3);"
            "})()"));
        const QVariant got = expr.evaluate();
        QVERIFY2(!expr.hasError(),
                 qPrintable(QStringLiteral("QML 侧调用报错: %1").arg(expr.error().description())));
        QCOMPARE(got.toString(), QStringLiteral("36.250/117.100/36.252"));
    }

    // ===== 统计 =====
    void test_trackStatsAndProfile() {
        const QString id = m_svc->startTrack(QStringLiteral("统计轨迹"), 5)
                             .value("value").toString();
        QVERIFY(!id.isEmpty());
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.250, 117.100, 150)));
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.252, 117.102, 650)));
        QVERIFY(isOk(m_svc->addTrackPoint(id, 36.254, 117.104, 1545)));
        QVERIFY(isOk(m_svc->stopTrack(id)));

        // getTrackStats 返回扁平 {ok, distanceM, ...}, 不是标准 Result<T> 三段式
        const QVariantMap stats = m_svc->getTrackStats(id, 65.0);
        QVERIFY2(stats.value("ok").toBool(),
                 qPrintable(stats.value("error").toString()));
        QVERIFY2(stats.value("distanceM").toDouble() > 0, "距离应为正");
        // 150 → 650 → 1545: 累计爬升 1395m
        QCOMPARE(stats.value("elevationGainM").toDouble(), 1395.0);

        const QVariantMap profile = m_svc->getTrackProfile(id);
        QVERIFY2(profile.value("ok").toBool(),
                 qPrintable(profile.value("error").toString()));
    }

    // ===== GPX 导入 / 导出回环 =====
    void test_gpxImportAndExportRoundTrip() {
        const QString in = m_tmpDir->path() + "/fixture.gpx";
        QFile f(in);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(testfix::gpxFixture());
        f.close();

        const QVariantMap imp = m_svc->importGpx(in);
        QVERIFY2(isOk(imp), qPrintable(errText(imp)));
        const QString id = imp.value("value").toString();
        QVERIFY(!id.isEmpty());

        QCOMPARE(m_svc->getTrackPoints(id).size(), 3);
        const QVariantMap track = m_svc->getTrackById(id).value("value").toMap();
        QVERIFY2(track.value("name").toString().contains(QStringLiteral("泰山测试线")),
                 qPrintable(track.value("name").toString()));

        const QString out = m_tmpDir->path() + "/exported.gpx";
        QVERIFY2(isOk(m_svc->exportTrackAsGpx(id, out)), "GPX 导出失败");
        QVERIFY(QFileInfo::exists(out));

        // 导出的文件再导入, 点数应保持一致
        const QVariantMap re = m_svc->importGpx(out);
        QVERIFY2(isOk(re), "导出后再导入失败 (GPX 不自洽)");
        QCOMPARE(m_svc->getTrackPoints(re.value("value").toString()).size(), 3);

        // 2026-10-29 #168 的正向配对: 带 <time> 的文件 (08:00 → 10:00) 必须把派生那族
        //   写出来 —— test_gpxImportWithoutTimesStaysUnknown 断言的是"没时刻就整键不写",
        //   这里钉住"有时刻就还在", 否则两条一起也能骗过"整键不写"。
        const QVariantMap s = m_svc->getTrackStats(id);
        QVERIFY2(s.value("ok").toBool(), qPrintable(errText(s)));
        QCOMPARE(s.value("durationS").toLongLong(), qint64(7200));
        QVERIFY2(s.contains("avgSpeed") && s.value("avgSpeed").toDouble() > 0.0,
                 "带时刻的 GPX 没算出平均速度");
        QVERIFY2(s.contains("calorieKcal"), "带时刻的 GPX 没算出热量");
        QVERIFY2(s.contains("maxSpeed"), "08:00→09:00 位移 286 m, 最快窗口该凑得出来");
    }

    // 2026-10-27 #134: 不带 <time> 的 GPX 导进来, 时间就整条留空.
    //   老代码三处造假: startTime 回落 currentDateTime() (导入 2024 年的文件写成
    //   "这一刻")、逐点 addSecs(i*5) 编节拍 (getTrackStats 的速度 = 段距离/段时刻差,
    //   于是散步读成 8 km/h)、缺 <ele> 填 0 ("最低点 0 米"). 另外 (0,0) 哨兵点会被
    //   算进距离, 拉出一条到几内亚湾的往返.
    void test_gpxImportWithoutTimesStaysUnknown() {
        const QString in = m_tmpDir->path() + "/no_time.gpx";
        QFile f(in);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(testfix::gpxNoTimeFixture());
        f.close();

        const QVariantMap imp = m_svc->importGpx(in);
        QVERIFY2(isOk(imp), qPrintable(errText(imp)));
        const QString id = imp.value("value").toString();
        QVERIFY(!id.isEmpty());

        // 4 个 <trkpt> 里那个 (0,0) 不许进轨迹
        QCOMPARE(m_svc->getTrackPoints(id).size(), 3);

        const QVariantMap track = m_svc->getTrackById(id).value("value").toMap();
        QVERIFY2(track.value("startTime").toString().isEmpty(),
                 qPrintable(QStringLiteral("文件没给时刻, startTime 却被填成 %1")
                            .arg(track.value("startTime").toString())));
        // stopTrack 会把 endTime 写成"停止的这一刻", 导入必须把它按文件口径改回空
        QVERIFY2(track.value("endTime").toString().isEmpty(),
                 qPrintable(QStringLiteral("endTime 是导入那一下的假读数: %1")
                            .arg(track.value("endTime").toString())));
        QVERIFY2(!track.contains("maxAltitudeM") || track.value("maxAltitudeM").toDouble() > 0.0,
                 "一个高程都没有时不许写出 0 米的最高点");

        const QVariantList els = m_svc->getTrackElevations(id);
        QCOMPARE(els.size(), 3);
        for (const QVariant& v : els) {
            QVERIFY2(v.toMap().value("timestamp").toString().isEmpty(),
                     "没有 <time> 的 GPX 被编出了逐点时刻");
        }

        // getTrackElevations 对缺键给的是 0.0, 分不出"0 米"和"没测到" → 直接看落盘
        QFile pf(PathService::mapDir() + QStringLiteral("/track_%1_points.json").arg(id));
        QVERIFY(pf.open(QIODevice::ReadOnly));
        const QJsonArray arr = QJsonDocument::fromJson(pf.readAll()).array();
        pf.close();
        QCOMPARE(arr.size(), 3);
        QVERIFY2(arr.at(0).toObject().contains("elevation"), "带 <ele> 的点反而没落高程");
        QVERIFY2(!arr.at(1).toObject().contains("elevation"),
                 "缺 <ele> 的点被填了 0 —— 会读成\"最低点 0 米\"");
        QVERIFY2(arr.at(2).toObject().contains("elevation"), "带 <ele> 的点反而没落高程");

        // 2026-10-29 #168: 派生自时刻的那一族 (时长/平均速度/配速/热量/最快) 在没有时刻时
        //   整键不写。之前发的是 0, RouteSummaryPanel 于是把时长格写成 "0小时0分钟"。
        //   "不含"照例配一条"含": distanceM 必须还在, 否则整个返回坏掉也算通过。
        const QVariantMap s = m_svc->getTrackStats(id);
        QVERIFY2(s.value("ok").toBool(), qPrintable(errText(s)));
        QVERIFY2(s.contains("distanceM"), qPrintable(QStringLiteral("返回=%1").arg(errText(s))));
        QVERIFY(!s.contains("durationS"));
        QVERIFY(!s.contains("avgSpeed"));
        QVERIFY(!s.contains("avgPace"));
        QVERIFY(!s.contains("calorieKcal"));
        QVERIFY(!s.contains("maxSpeed"));

        QVERIFY(isOk(m_svc->deleteTrack(id)));
    }

    void test_importGpxMissingFileReturnsIoError() {
        const QVariantMap r = m_svc->importGpx(m_tmpDir->path() + "/absent.gpx");
        QVERIFY(!isOk(r));
        QCOMPARE(errOf(r), QStringLiteral("IoError"));
    }

    // 2026-10-27 #134: 两步路 (2bulu) 真机导出的 KML.
    //   回归的是"导入进去但什么都看不见"这一整串: 轨迹在 <gx:Track> 里而不是
    //   <LineString>, 于是老解析一个点都读不到 → 直接回「KML 无轨迹点」;
    //   侥幸有线时, 名称又会被最后一个 Placemark 的 <name> 顶掉, 时刻被编成
    //   5 秒等距节拍, 统计因为 stopTrack 跑在 track_*.json 落盘之前而整体丢失.
    void test_kmlTbuluGxTrackImport() {
        const QString in = m_tmpDir->path() + "/tbulu.kml";
        QFile f(in);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(testfix::kmlTbuluFixture());
        f.close();

        const QVariantMap imp = m_svc->importKml(in);
        QVERIFY2(isOk(imp), qPrintable(errText(imp)));
        const QString id = imp.value("value").toString();
        QVERIFY(!id.isEmpty());

        // 6 个 <gx:coord> 才是轨迹点; 标注点那两个 <Point> 不能混进来
        const QList<QGeoCoordinate> pts = m_svc->getTrackPoints(id);
        QCOMPARE(pts.size(), 6);
        QVERIFY(qAbs(pts.at(0).latitude() - 36.561245) < 1e-9);
        QVERIFY(qAbs(pts.at(0).longitude() - 117.3067133) < 1e-9);

        const QVariantMap track = m_svc->getTrackById(id).value("value").toMap();
        // 标题来自 <Document><name>; 「轨迹片段1」和标注点「村委会」都不许顶上去
        const QString name = track.value("name").toString();
        QVERIFY2(name.contains(QStringLiteral("空心山")), qPrintable(name));
        QVERIFY2(!name.contains(QStringLiteral("片段")), qPrintable(name));
        QVERIFY2(!name.contains(QStringLiteral("村委会")), qPrintable(name));
        QCOMPARE(track.value("source").toString(), QStringLiteral("imported"));
        QCOMPARE(track.value("originalFormat").toString(), QStringLiteral("kml"));
        // 统计: stopTrack 必须在这个文件已落盘之后才跑, 否则这些键一个都没有
        QCOMPARE(track.value("pointCount").toInt(), 6);
        QVERIFY2(track.value("totalDistanceM").toDouble() > 0.0, "距离没算出来");
        QVERIFY2(!track.value("endTime").toString().isEmpty(), "endTime 没回填");

        // 逐点时刻用文件里的 <when>: 第 1→2 点的真实间隔是 55 秒.
        //   老代码对"没有时间的点"编 addSecs(i*5), 这里会是 5 秒; 而 getTrackStats
        //   的速度 = 段距离 / 段时刻差, 节拍一编, 配速读数就整条是假的.
        const QVariantList els = m_svc->getTrackElevations(id);
        QCOMPARE(els.size(), 6);
        const QDateTime t0 = QDateTime::fromString(
            els.at(0).toMap().value("timestamp").toString(), Qt::ISODate);
        const QDateTime t1 = QDateTime::fromString(
            els.at(1).toMap().value("timestamp").toString(), Qt::ISODate);
        QVERIFY2(t0.isValid() && t1.isValid(), "<when> 没落进轨迹点");
        QCOMPARE(t0.secsTo(t1), qint64(55));
        // <when> 比 <gx:coord> 少一个: 第 6 点就该没有时刻, 不许用节拍补
        QVERIFY(els.at(5).toMap().value("timestamp").toString().isEmpty());

        // 2026-10-29 #168 (A44): 两步路在 <Document><ExtendedData> 里写了自己算的
        //   爬升/下降 (真文件里这一条是 720.47 / 719.33)。用户在它 App 里看到的就是
        //   这两个数, 我们的读数必须跟着它, 而不是拿 6 个采样点自己算出另一个数。
        //   (数值照抄真文件, 尾巴上是 720.4700000000003 这种浮点噪声, 所以带容差比)
        const auto near = [](double a, double b) { return qAbs(a - b) < 1e-6; };
        QVERIFY2(near(track.value("declaredElevationGainM").toDouble(), 720.47),
                 qPrintable(QStringLiteral("自述爬升没落进 meta: %1")
                                .arg(track.value("declaredElevationGainM").toDouble())));
        QVERIFY2(near(track.value("declaredElevationLossM").toDouble(), 719.33),
                 qPrintable(QStringLiteral("自述下降没落进 meta: %1")
                                .arg(track.value("declaredElevationLossM").toDouble())));
        QVERIFY2(near(track.value("elevationGainM").toDouble(), 720.47),
                 qPrintable(QStringLiteral("列表用的爬升不是自述值: %1 —— 这 6 个点自己算只有 5.7 m")
                                .arg(track.value("elevationGainM").toDouble())));
        QVERIFY2(near(track.value("elevationLossM").toDouble(), 719.33),
                 qPrintable(QStringLiteral("列表用的下降不是自述值: %1")
                                .arg(track.value("elevationLossM").toDouble())));
        // 概要面板/详情页 (getTrackStats) 与列表 (getAllTracks→meta) 是两处读数,
        //   原来一个用 1 m 死区、一个用逐点累加, 同一条线给两个答案 —— 现在两处
        //   都必须等于文件自述的那个。
        const QVariantMap stats = m_svc->getTrackStats(id, 65.0);
        QVERIFY2(stats.value("ok").toBool(),
                 qPrintable(stats.value("error").toString()));
        QVERIFY2(near(stats.value("elevationGainM").toDouble(), 720.47),
                 qPrintable(QStringLiteral("面板爬升=%1").arg(stats.value("elevationGainM").toDouble())));
        QVERIFY2(near(stats.value("elevationLossM").toDouble(), 719.33),
                 qPrintable(QStringLiteral("面板下降=%1").arg(stats.value("elevationLossM").toDouble())));
    }

    void test_kmlLineStringImportStillWorks() {
        // Google Earth / 奥维那份保留: 线在 <LineString><coordinates> 里
        const QString in = m_tmpDir->path() + "/line_string.kml";
        QFile f(in);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(testfix::kmlLineStringFixture());
        f.close();

        const QVariantMap imp = m_svc->importKml(in);
        QVERIFY2(isOk(imp), qPrintable(errText(imp)));
        const QString id = imp.value("value").toString();

        // 4 组坐标里 (0,0,0) 是缺数据哨兵, 不能画到几内亚湾去
        QCOMPARE(m_svc->getTrackPoints(id).size(), 3);
        const QVariantMap track = m_svc->getTrackById(id).value("value").toMap();
        // 这类文件 <Document><name> 是容器名"我的地点", 标题在带线的 Placemark 上
        QVERIFY2(track.value("name").toString().contains(QStringLiteral("奥维测试线")),
                 qPrintable(track.value("name").toString()));

        // 2026-10-29 #168 的另一半: 没有自述升降的文件就走算出来的口径。
        //   三点各隔 ~286 m (比 ±60 m 平滑窗口宽), 所以爬升就是两段高程差之和
        //   500 + 895 = 1395, 一条都没有的自述键不许凭空出现。
        QVERIFY2(!track.contains("declaredElevationGainM"),
                 "这份 KML 没有 <Data name=\"ElevationGain\">, meta 里却冒出了自述键");
        QCOMPARE(track.value("elevationGainM").toDouble(), 1395.0);
        QCOMPARE(track.value("elevationLossM").toDouble(), 0.0);
    }

    void test_importKmlMissingFileReturnsIoError() {
        const QVariantMap r = m_svc->importKml(m_tmpDir->path() + "/absent.kml");
        QVERIFY(!isOk(r));
        QCOMPARE(errOf(r), QStringLiteral("IoError"));
    }

    void test_importKmlWithoutAnyLineReturnsParseError() {
        const QString in = m_tmpDir->path() + "/empty.kml";
        QFile f(in);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("<?xml version=\"1.0\"?><kml xmlns=\"http://www.opengis.net/kml/2.2\">"
                "<Document><Placemark><name>只是一个点</name></Placemark></Document></kml>");
        f.close();
        const QVariantMap r = m_svc->importKml(in);
        QVERIFY(!isOk(r));
        QCOMPARE(errOf(r), QStringLiteral("ParseError"));
    }

    void test_importCsvHeaderAliases() {
        const QString csv = m_tmpDir->path() + "/track.csv";
        QFile f(csv);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("latitude,longitude,elevation,time\n"
                "36.250,117.100,150,2026-10-01T08:00:00Z\n"
                "36.252,117.102,650,2026-10-01T09:00:00Z\n"
                "36.254,117.104,1545,2026-10-10T10:00:00Z\n");
        f.close();

        const QVariantMap r = m_svc->importCsv(csv);
        QVERIFY2(isOk(r), qPrintable(errText(r)));
        const QString id = r.value("value").toString();
        QCOMPARE(m_svc->getTrackPoints(id).size(), 3);

        // 2026-10-27 #134: 表头里的 time 列以前被整列忽略, 每点落的却是
        //   currentDateTime() —— 三条同时刻, getTrackStats 的速度全成 0.
        const QVariantList els = m_svc->getTrackElevations(id);
        QCOMPARE(els.size(), 3);
        const QDateTime t0 = QDateTime::fromString(
            els.at(0).toMap().value("timestamp").toString(), Qt::ISODate);
        const QDateTime t2 = QDateTime::fromString(
            els.at(2).toMap().value("timestamp").toString(), Qt::ISODate);
        QVERIFY2(t0.isValid() && t2.isValid(), "CSV 的 time 列没落进轨迹点");
        // 首行 10-01T08:00Z → 末行 10-10T10:00Z: 9 天再多 2 小时 (跨了两天各自的时刻),
        //   不是整 9 天 —— 断言按字面时间差算, 别按"看起来像 9 天"写.
        QCOMPARE(t0.secsTo(t2), qint64(9 * 24 * 3600 + 2 * 3600));
        // 有 alt 列就落高程 (这一列的表头别名见 importCsv)
        QVERIFY(els.at(0).toMap().value("elevation").toDouble() > 0.0);

        // 顺序缺陷: 老代码先 stopTrack 再写 track_<id>.json —— 那文件当时还不存在,
        //   stopTrack 走 NotFound 直接返回, 于是名称/统计整体没落盘.
        const QVariantMap track = m_svc->getTrackById(id).value("value").toMap();
        QCOMPARE(track.value("source").toString(), QStringLiteral("imported"));
        QCOMPARE(track.value("originalFormat").toString(), QStringLiteral("csv"));
        QCOMPARE(track.value("pointCount").toInt(), 3);
        QVERIFY2(track.value("totalDistanceM").toDouble() > 0.0, "CSV 导入没算出距离");
        QCOMPARE(track.value("startTime").toString(), t0.toString(Qt::ISODate));
        QCOMPARE(track.value("endTime").toString(), t2.toString(Qt::ISODate));
    }

    // 2026-10-27 #134: 没有时间列的 CSV —— 时刻整条留空, 不填"导入的这一刻";
    //   (0,0) 行不进轨迹; 缺高程的那一格不写 0.
    void test_importCsvWithoutTimeLeavesTimesUnknown() {
        const QString csv = m_tmpDir->path() + "/no_time.csv";
        QFile f(csv);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("lat,lon,alt\n"
                "36.300,117.200,420\n"
                "36.302,117.202,\n"
                "0,0,0\n"
                "36.304,117.204,980\n");
        f.close();

        const QVariantMap r = m_svc->importCsv(csv);
        QVERIFY2(isOk(r), qPrintable(errText(r)));
        const QString id = r.value("value").toString();
        QCOMPARE(m_svc->getTrackPoints(id).size(), 3);

        const QVariantMap track = m_svc->getTrackById(id).value("value").toMap();
        QVERIFY2(track.value("startTime").toString().isEmpty(), "无时间列却填了起始时间");
        QVERIFY2(track.value("endTime").toString().isEmpty(), "无时间列却填了结束时间");
        QCOMPARE(track.value("pointCount").toInt(), 3);
        QVERIFY2(track.value("totalDistanceM").toDouble() > 0.0, "无时间列也应该算得出距离");

        QFile pf(PathService::mapDir() + QStringLiteral("/track_%1_points.json").arg(id));
        QVERIFY(pf.open(QIODevice::ReadOnly));
        const QJsonArray arr = QJsonDocument::fromJson(pf.readAll()).array();
        pf.close();
        QCOMPARE(arr.size(), 3);
        QVERIFY(!arr.at(0).toObject().contains("timestamp"));
        QVERIFY(!arr.at(1).toObject().contains("elevation"));
        QVERIFY(arr.at(2).toObject().contains("elevation"));
    }

    void test_importCsvWithoutColumnsFails() {
        const QString csv = m_tmpDir->path() + "/bad.csv";
        QFile f(csv);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("foo,bar\n1,2\n");
        f.close();
        const QVariantMap r = m_svc->importCsv(csv);
        QVERIFY(!isOk(r));
        QCOMPARE(errOf(r), QStringLiteral("ParseError"));
    }

    // ===== 物种位置 =====
    // 2026-10-23 #113: deleteSpeciesLocation (物种详情页「地图上的记录」单条删除入口).
    // 本槽刻意排在 test_speciesLocationWriteAndBoundsQuery **之前** —— QtTest 按声明
    // 顺序跑槽, 此时存储目录里保证没有 species_*.json, "删完列表为空 / speciesCount
    // 归 0" 这两组断言才立得住. 全程只 add 一条也是刻意的: id = currentMSecsSinceEpoch,
    // 同一毫秒连调两次会撞 id、后一条静默覆写前一条的文件, 列表条数就数不对了.
    void test_speciesLocationDeleteAndIdValidation() {
        QVERIFY2(m_svc->getSpeciesLocations().isEmpty(), "前置: 物种位置应为空");

        // "不在"断言全部和"在"断言配对着写 —— 空表上 !hasId 是白跑的, 本仓库单测的判读规矩.
        auto hasId = [this](const QString& want) {
            for (const QVariant& v : m_svc->getSpeciesLocations()) {
                if (v.toMap().value(QLatin1String("id")).toString() == want) return true;
            }
            return false;
        };

        QVERIFY(isOk(m_svc->addSpeciesLocation(
            QStringLiteral("plant_del"), QStringLiteral("待删标注"),
            QStringLiteral("plant"), 36.25, 117.10, 150,
            QStringLiteral("删除链路样本"))));
        const QVariantList added = m_svc->getSpeciesLocations();
        QCOMPARE(added.size(), 1);  // "在"锚点: 下面每条"不在"都对着这条
        const QString id = added.first().toMap().value(QLatin1String("id")).toString();
        QVERIFY2(!id.isEmpty(), "getSpeciesLocations 返回的 map 里应带可删的 id");
        QCOMPARE(m_svc->getStats().value(QLatin1String("speciesCount")).toInt(), 1);

        // 非法 id: 空串 / 路径注入 / 混字母 —— 一律 InvalidArgument, 且不许碰真标注.
        // ("../etc/passwd" 会被拼进 species_<id>.json 的文件名, 全靠纯数字白名单挡)
        for (const QString& bad : {QString(), QStringLiteral("../etc/passwd"),
                                   QStringLiteral("12a")}) {
            const QVariantMap r = m_svc->deleteSpeciesLocation(bad);
            QVERIFY2(!isOk(r),
                     qPrintable(QStringLiteral("非法 id「%1」竟然删成功了").arg(bad)));
            QCOMPARE(errOf(r), QStringLiteral("InvalidArgument"));
            QVERIFY2(hasId(id),  // 正向断言: 被拒的删除没把真标注一起删掉
                     qPrintable(QStringLiteral("拒绝非法 id「%1」后真标注应还在").arg(bad)));
        }
        QVERIFY(!hasId(QStringLiteral("../etc/passwd")));  // 配上一条: 注入串本来就不是合法 id

        // 形状合法但不存在 → NotFound; 同样不许动到真标注
        const QVariantMap missing = m_svc->deleteSpeciesLocation(QStringLiteral("99999999999999"));
        QVERIFY2(!isOk(missing), "不存在的 id 不应算删除成功");
        QCOMPARE(errOf(missing), QStringLiteral("NotFound"));
        QVERIFY2(hasId(id), "NotFound 的删除不应碰真标注");
        // 带空格的合法 id 走 trimmed() 分支: 应报 NotFound 而不是 InvalidArgument
        QCOMPARE(errOf(m_svc->deleteSpeciesLocation(QStringLiteral("  99999999999999  "))),
                 QStringLiteral("NotFound"));

        // 成功删除: value=true, 列表回到空, speciesCount 跟着回落 (getStats 现扫目录, 无缓存)
        const QVariantMap del = m_svc->deleteSpeciesLocation(id);
        QVERIFY2(isOk(del), qPrintable(errText(del)));
        QVERIFY2(del.value(QLatin1String("value")).toBool(), "删除成功时 value 应为 true");
        QVERIFY(!hasId(id));  // 删完"不在"……
        // ……与整表归空配对: 若 hasId 本身写坏了, isEmpty 这条会兜住假绿
        QVERIFY2(m_svc->getSpeciesLocations().isEmpty(), "删掉唯一一条后列表应重新为空");
        QCOMPARE(m_svc->getStats().value(QLatin1String("speciesCount")).toInt(), 0);
        // 再删同一个 id → NotFound, 顺带证明文件确实没了
        QCOMPARE(errOf(m_svc->deleteSpeciesLocation(id)), QStringLiteral("NotFound"));
    }

    void test_speciesLocationWriteAndBoundsQuery() {
        QVERIFY(isOk(m_svc->addSpeciesLocation(
            QStringLiteral("plant_test"), QStringLiteral("测试植物"),
            QStringLiteral("plant"), 36.25, 117.10, 150,
            QStringLiteral("泰山脚下"))));

        const QVariantList all = m_svc->getSpeciesLocations();
        QVERIFY2(!all.isEmpty(), "物种位置列表为空");

        const QVariantList hit = m_svc->getSpeciesLocationsInBounds(
            36.0, 36.5, 117.0, 117.2);
        QVERIFY2(!hit.isEmpty(), "范围内应命中刚写入的物种点");
        // 范围外不应命中
        QVERIFY(m_svc->getSpeciesLocationsInBounds(0.0, 1.0, 0.0, 1.0).isEmpty());
    }

    void test_speciesLocationAccuracyAndAltitudeOmission() {
        // 未知: 高程与精度都不该出现在落盘的 map 里 (写 0 会被读成"海平面 / 极准")
        QVERIFY(isOk(m_svc->addSpeciesLocation(
            QStringLiteral("plant_noacc"), QStringLiteral("无读数标注"),
            QStringLiteral("plant"), 36.30, 117.20, kNaN,
            QStringLiteral("精度批次: 未知"))));
        QTest::qWait(3);  // id = epoch-ms, 同一毫秒连写会撞文件名后一条盖前一条
        // 已知: 负高程是真数 (吐鲁番盆地), 不能按 ">0 才写" 处理
        QVERIFY(isOk(m_svc->addSpeciesLocation(
            QStringLiteral("plant_negalt"), QStringLiteral("低洼标注"),
            QStringLiteral("plant"), 36.31, 117.21, -15.0,
            QStringLiteral("精度批次: 有读数"), 1.5)));

        QVariantMap noAcc, withAcc;
        for (const QVariant& v : m_svc->getSpeciesLocations()) {
            const QVariantMap m = v.toMap();
            if (m.value("speciesId").toString() == QLatin1String("plant_noacc")) noAcc = m;
            if (m.value("speciesId").toString() == QLatin1String("plant_negalt")) withAcc = m;
        }
        QVERIFY2(!noAcc.isEmpty() && !withAcc.isEmpty(), "两条标注应都能读回来");
        QVERIFY2(noAcc.contains("lat"), "没读回 lat 说明整条写入坏了, 下面的\"不含\"断言才没有意义");
        QVERIFY(!noAcc.contains("altitude"));
        QVERIFY(!noAcc.contains("accuracy"));
        QCOMPARE(withAcc.value("accuracy").toDouble(), 1.5);
        QCOMPARE(withAcc.value("altitude").toDouble(), -15.0);
    }

    // 标注这一路的坐标门与轨迹同源 (无权限时 EmergencyService 的经纬度是 0).
    void test_speciesLocationRejectsInvalidCoordinates() {
        const int before = m_svc->getSpeciesLocations().size();
        for (const QVariantList bad : {QVariantList{kNaN, 117.0},
                                       QVariantList{36.0, kNaN},
                                       QVariantList{0.0, 0.0},
                                       QVariantList{-91.0, 117.0}}) {
            const QVariantMap r = m_svc->addSpeciesLocation(
                QStringLiteral("plant_bad"), QStringLiteral("坏坐标"),
                QStringLiteral("plant"), bad[0].toDouble(), bad[1].toDouble());
            QVERIFY2(!isOk(r), qPrintable(errText(r)));
            QCOMPARE(errOf(r), QStringLiteral("InvalidArgument"));
        }
        // 正向配对: 门只拦坏点. 全被拒的话上面四条也是"通过", 这里数一下才分得开
        QVERIFY(isOk(m_svc->addSpeciesLocation(
            QStringLiteral("plant_ok"), QStringLiteral("好点"),
            QStringLiteral("plant"), 36.32, 117.22, kNaN,
            QStringLiteral("精度批次: 合法"))));
        QCOMPARE(m_svc->getSpeciesLocations().size(), before + 1);
    }

    void test_exportAllSpeciesAsKml() {
        const QString out = m_tmpDir->path() + "/species.kml";
        QVERIFY2(isOk(m_svc->exportAllSpeciesAsKml(out)), "物种 KML 导出失败");
        QFile f(out);
        QVERIFY(f.open(QIODevice::ReadOnly));
        const QByteArray data = f.readAll();
        QVERIFY2(data.contains("kml"), qPrintable(QStringLiteral("导出内容不像 KML")));
        QVERIFY(data.contains("测试植物"));
    }

    // ===== 汇总统计 =====
    void test_statsAndAltitudeStats() {
        QVERIFY(!m_svc->getStats().isEmpty());
        QVERIFY(!m_svc->getAltitudeStats().isEmpty());
    }

    void test_cleanupOldDataIsIdempotent() {
        const int removed = m_svc->cleanupOldData(0);
        QVERIFY(removed >= 0);
        QVERIFY(m_svc->cleanupOldData(90) >= 0);
    }

    // ===== 底图 =====
    void test_tileUrlAndBaseMapName() {
        const QString url = m_svc->getTileUrl(10, 512, 256);
        QVERIFY2(url.contains("512") && url.contains("256"), qPrintable(url));
        QVERIFY(!m_svc->getBaseMapName(BaseMapType::Terrain).isEmpty());
        QVERIFY(!m_svc->getBaseMapName(BaseMapType::Satellite).isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestMapService)
#include "test_map_service.moc"
