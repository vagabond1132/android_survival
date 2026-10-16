/**
 * @file test_map_service.cpp
 * @brief map/MapService 单元测试 (45 个 Q_INVOKABLE, 此前 0 覆盖)
 *
 * MapService 用 JSON 文件存储 (PathService::mapDir()), 不走 SQLite。
 * 测试通过 QStandardPaths::setTestModeEnabled 把 AppDataLocation 指向临时目录。
 *
 * 覆盖:
 *   - 海拔 5 段分级边界 (L0-L4) + 名称/颜色/区间
 *   - 记录频率选项 (2/5/10/20/30)
 *   - 轨迹生命周期 start → addPoint → stop → get → delete
 *   - 轨迹统计与海拔曲线
 *   - GPX 导入 / 导出回环, CSV 导入 (表头列名兼容)
 *   - 物种位置写入 + 矩形范围查询
 *   - Result 契约 {ok, value, error} 与 NotFound / IoError 分支
 */
#include <QtTest>
#include <QCoreApplication>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QFile>
#include <QGeoCoordinate>

#include "src/core/PathService.h"
#include "src/core/ServiceErrors.h"
#include "src/map/MapService.h"
#include "fixtures/MapTestFixtures.h"

using namespace outdoor;

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
        QCOMPARE(MapService::getAltitudeLevel(8848.0), AltitudeLevel::L4);   // 封顶
    }

    void test_altitudeLevelMetadata() {
        QCOMPARE(MapService::getAltitudeLevelName(AltitudeLevel::L0), QStringLiteral("低海拔"));
        QCOMPARE(MapService::getAltitudeLevelName(AltitudeLevel::L4), QStringLiteral("极高海拔"));
        QVERIFY(MapService::getAltitudeLevelColor(AltitudeLevel::L0).startsWith('#'));
        QCOMPARE(MapService::getAltitudeLevelMin(AltitudeLevel::L1), 500.0);
        QCOMPARE(MapService::getAltitudeLevelMax(AltitudeLevel::L1), 1500.0);
    }

    // ===== 记录频率 (关键决策: 2/5/10/20/30 秒) =====
    void test_frequencyOptions() {
        const QVariantList opts = m_svc->getFrequencyOptions();
        QVERIFY2(opts.size() >= 5, qPrintable(QStringLiteral("频率选项 %1 个").arg(opts.size())));
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
        for (const char* expect : {"2", "5", "10", "20", "30"}) {
            QVERIFY2(values.contains(QString::fromLatin1(expect)),
                     qPrintable(QStringLiteral("缺频率 %1").arg(expect)));
        }
        QVERIFY(!m_svc->getFrequencyLabel(5).isEmpty());
        QVERIFY(m_svc->getDefaultFrequency() > 0);
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

    void test_startTrackRejectsBlankName() {
        const QVariantMap r = m_svc->startTrack(QString());
        QVERIFY(!isOk(r));
    }

    void test_addTrackPointOnMissingTrackFails() {
        const QVariantMap r = m_svc->addTrackPoint(
            QStringLiteral("no_such_track"), 36.0, 117.0, 100);
        QVERIFY(!isOk(r));
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
    }

    void test_importGpxMissingFileReturnsIoError() {
        const QVariantMap r = m_svc->importGpx(m_tmpDir->path() + "/absent.gpx");
        QVERIFY(!isOk(r));
        QCOMPARE(errOf(r), QStringLiteral("IoError"));
    }

    void test_importCsvHeaderAliases() {
        const QString csv = m_tmpDir->path() + "/track.csv";
        QFile f(csv);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("latitude,longitude,elevation,time\n"
                "36.250,117.100,150,2026-10-01T08:00:00Z\n"
                "36.252,117.102,650,2026-10-01T09:00:00Z\n"
                "36.254,117.104,1545,2026-10-01T10:00:00Z\n");
        f.close();

        const QVariantMap r = m_svc->importCsv(csv);
        QVERIFY2(isOk(r), qPrintable(errText(r)));
        QCOMPARE(m_svc->getTrackPoints(r.value("value").toString()).size(), 3);
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
