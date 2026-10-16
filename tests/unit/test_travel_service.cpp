/**
 * @file test_travel_service.cpp
 * @brief 自驾游服务单元测试
 */

#include <QtTest>
#include <QCoreApplication>
#include <QTemporaryDir>

#include "src/travel/TravelService.h"
#include "src/core/Database.h"

using namespace outdoor;

class TestTravelService : public QObject {
    Q_OBJECT

private:
    TravelService* m_service = nullptr;
    Database* m_db = nullptr;
    QTemporaryDir m_tmpDir;

private slots:
    void init() {
        QVERIFY(m_tmpDir.isValid());
        m_db = new Database();
        QVERIFY(m_db->open(m_tmpDir.path()));
        m_db->migrate();
        m_service = new TravelService();
        QVERIFY(m_service->loadInitialData());
    }

    void cleanup() {
        delete m_service;
        delete m_db;
    }

    // === 数据加载 ===
    void test_load_initial_data() {
        QVERIFY(m_service->totalCount() >= 100);
        qInfo() << "Loaded travels:" << m_service->totalCount();
    }

    // === 查询 ===
    void test_get_by_id_existing() {
        QVariantList all = m_service->getAll();
        QVERIFY(all.size() > 0);
        QString firstId = all.first().toMap()["id"].toString();
        QVariantMap t = m_service->getById(firstId);
        QVERIFY(!t.isEmpty());
        QVERIFY(t["name"].toString().length() > 0);
    }

    void test_get_by_id_nonexistent() {
        QVariantMap t = m_service->getById("nonexistent_travel_999");
        QVERIFY(t.isEmpty());
    }

    // === 省份筛选 ===
    void test_by_province() {
        QVariantList xinjiang = m_service->getByProvince("新疆");
        QVERIFY(xinjiang.size() > 0);
        for (const auto& t : xinjiang) {
            QString prov = t.toMap()["province"].toString();
            QVERIFY(prov.contains("新疆"));
        }
    }

    void test_by_province_multi() {
        // 跨省路线:含 "/" 分割
        QVariantList all = m_service->getAll();
        int multiCount = 0;
        for (const auto& t : all) {
            QString prov = t.toMap()["province"].toString();
            if (prov.contains("/")) multiCount++;
        }
        qInfo() << "跨省路线数:" << multiCount;
        QVERIFY(multiCount > 0);
    }

    // === 天数筛选 ===
    void test_by_days_short() {
        QVariantList shortTrips = m_service->getByDaysRange(1, 2);
        QVERIFY(shortTrips.size() > 0);
    }

    void test_by_days_long() {
        QVariantList longTrips = m_service->getByDaysRange(7, 30);
        QVERIFY(longTrips.size() > 0);
    }

    void test_by_days_invalid_range() {
        // min > max 应返回空
        QVariantList r = m_service->getByDaysRange(10, 2);
        QCOMPARE(r.size(), 0);
    }

    // === 距离筛选 ===
    void test_by_distance() {
        // 变量名原为 short/long, 是 C++ 关键字, 无法编译
        QVariantList near = m_service->getByDistanceRange(0, 200);
        QVariantList far = m_service->getByDistanceRange(2000, 9999);
        QVERIFY(near.size() > 0);
        QVERIFY(far.size() > 0);
        for (const auto& t : near) {
            QVERIFY(t.toMap()["distanceKm"].toDouble() <= 200);
        }
        for (const auto& t : far) {
            QVERIFY(t.toMap()["distanceKm"].toDouble() >= 2000);
        }
    }

    // === 月份筛选 ===
    void test_by_season_july() {
        QVariantList july = m_service->getByMonth(7);  // 2026-09-20: rename from getBySeason
        QVERIFY(july.size() > 0);
        for (const auto& t : july) {
            QVERIFY(t.toMap()["bestSeason"].toStringList().contains("7月"));
        }
    }

    void test_by_month_zero_or_out_of_range_means_all() {
        // 2026-09-14 起 (month < 1 || month > 12) 统一走"全部月份"分支, 与 RouteService 一致
        const int all = m_service->getByMonth(0).size();
        QCOMPARE(all, m_service->getAll().size());
        QCOMPARE(m_service->getByMonth(13).size(), all);
        QCOMPARE(m_service->getByMonth(-1).size(), all);
    }

    // === 多维筛选 ===
    void test_filtered_complex() {
        // 新疆 + 5-10 天 + 1000km 以上 (Phase 5: getFiltered 返回 Result)
        const QVariantMap res = m_service->getFiltered("新疆", 5, 10, 1000, 9999, 7);
        QVERIFY(res.value("ok").toBool());
        const QVariantList results = res.value("value").toList();
        QVERIFY(!results.isEmpty());
        for (const auto& r : results) {
            const QVariantMap& m = r.toMap();
            QVERIFY(m["province"].toString().contains("新疆"));
            const int d = m["days"].toInt();
            QVERIFY2(d >= 5 && d <= 10, qPrintable(QStringLiteral("%1 days=%2").arg(m["id"].toString()).arg(d)));
            QVERIFY(m["distanceKm"].toDouble() >= 1000);
        }
    }

    void test_filtered_zero_bounds_skips_range() {
        // min/max 同为 0 表示该维度不过滤 (实现里的显式约定)
        const QVariantMap res = m_service->getFiltered(QString(), 0, 0, 0, 0, 0);
        QVERIFY(res.value("ok").toBool());
        QCOMPARE(res.value("value").toList().size(), m_service->getAll().size());
    }

    // === 搜索 ===
    void test_search_keyword() {
        QVariantList results = m_service->search("川西");
        QVERIFY(results.size() > 0);
    }

    void test_search_empty() {
        // TravelService::search("") 返回全量 (与 Route/Species/FirstAid 不同, 它们返回空)
        QCOMPARE(m_service->search("").size(), m_service->totalCount());
    }

    // === 收藏/计数 ===
    void test_add_delete_favorite() {
        QVariantList all = m_service->getAll();
        QString id = all.first().toMap()["id"].toString();
        // Phase 5: 写操作返回 Result {ok, value, error}
        QVERIFY(m_service->addFavorite(id).value("ok").toBool());
        QVERIFY(m_service->isFavorite(id));
        QVERIFY(m_service->deleteFavorite(id).value("ok").toBool());
        QVERIFY(!m_service->isFavorite(id));
    }

    void test_add_favorite_unknown_id() {
        QVERIFY(!m_service->addFavorite("nonexistent_travel_999").value("ok").toBool());
    }

    void test_increment_visit_count() {
        QVariantList all = m_service->getAll();
        QString id = all.first().toMap()["id"].toString();
        for (int i = 0; i < 3; ++i) {
            QVERIFY(m_service->incrementVisitCount(id).value("ok").toBool());
        }
    }

    // === 工具 ===
    void test_available_provinces() {
        QStringList provs = m_service->getAvailableProvinces();
        QVERIFY(provs.size() > 10);
        QVERIFY(provs.contains("新疆"));
    }

    void test_available_months() {
        QStringList months = m_service->getAvailableMonths();
        QVERIFY(months.size() > 0);
        for (const auto& m : months) {
            // 格式如 "5月"
            QVERIFY(m.contains("月"));
        }
    }
};

QTEST_MAIN(TestTravelService)
#include "test_travel_service.moc"
