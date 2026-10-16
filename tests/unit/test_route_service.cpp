/**
 * @file test_route_service.cpp
 * @brief 路线服务单元测试
 */

#include <QtTest>
#include <QCoreApplication>
#include <QTemporaryDir>

#include "src/routes/RouteService.h"
#include "src/core/Database.h"

using namespace outdoor;

class TestRouteService : public QObject {
    Q_OBJECT

private:
    RouteService* m_service = nullptr;
    Database* m_db = nullptr;
    QTemporaryDir m_tmpDir;

private slots:
    void init() {
        QVERIFY(m_tmpDir.isValid());
        m_db = new Database();
        QVERIFY(m_db->open(m_tmpDir.path()));
        m_db->migrate();
        m_service = new RouteService(m_db);
        QVERIFY(m_service->loadInitialData());
    }

    void cleanup() {
        delete m_service;
        delete m_db;      // ServiceBase 不持有 Database 所有权, 原来这里泄漏了
        m_service = nullptr;
        m_db = nullptr;
    }

    // === 数据加载测试 ===
    void test_load_initial_data() {
        QVERIFY(m_service->totalCount() > 0);
        qInfo() << "Loaded routes:" << m_service->totalCount();
    }

    // === 基础查询 ===
    void test_get_by_id_existing() {
        QVariantList all = m_service->getAll();
        QVERIFY(all.size() > 0);
        QString firstId = all.first().toMap()["id"].toString();
        QVERIFY(!firstId.isEmpty());

        QVariantMap route = m_service->getById(firstId);
        QVERIFY(!route.isEmpty());
        QCOMPARE(route["id"].toString(), firstId);
        QVERIFY(route["name"].toString().length() > 0);
    }

    void test_get_by_id_nonexistent() {
        QVariantMap route = m_service->getById("nonexistent_route_id_999");
        QVERIFY(route.isEmpty());
    }

    void test_get_by_id_empty() {
        QVariantMap route = m_service->getById("");
        QVERIFY(route.isEmpty());
    }

    // === 筛选测试 ===
    void test_filter_by_difficulty() {
        QVariantList easy = m_service->getByDifficulty(1, 1);
        QVariantList hard = m_service->getByDifficulty(4, 5);
        QVERIFY(easy.size() > 0);
        QVERIFY(hard.size() > 0);
        // 验证筛选结果都是 1 级
        for (const auto& r : easy) {
            int d = r.toMap()["difficulty"].toInt();
            QVERIFY(d >= 1 && d <= 1);
        }
    }

    void test_filter_by_month() {
        QVariantList july = m_service->getByMonth(7);
        QVariantList jan = m_service->getByMonth(1);
        QVERIFY(july.size() > 0);
        QVERIFY(jan.size() > 0);
    }

    void test_filter_by_province() {
        QVariantList yunnan = m_service->getByProvince("云南");
        QVariantList sichuan = m_service->getByProvince("四川");
        QVERIFY(yunnan.size() > 0);
        QVERIFY(sichuan.size() > 0);
    }

    // === 多维筛选 ===
    void test_get_filtered() {
        // 阶段 L3.x: getFiltered 返回 Result, 列表在 .value
        const QVariantMap r = m_service->getFiltered("四川", 1, 3, 7);
        QVERIFY(r.value("ok").toBool());
        const QVariantList results = r.value("value").toList();
        QVERIFY(!results.isEmpty());
        for (const auto& item : results) {
            const QVariantMap& m = item.toMap();
            QCOMPARE(m["province"].toString(), QString("四川"));
            const int d = m["difficulty"].toInt();
            QVERIFY2(d >= 1 && d <= 3, qPrintable(QStringLiteral("%1 difficulty=%2").arg(m["id"].toString()).arg(d)));
            QVERIFY(m["bestSeason"].toStringList().contains("7月"));
        }
    }

    void test_get_filtered_empty_province_means_all() {
        // province 传空 = 不过滤省份
        const QVariantMap r = m_service->getFiltered(QString(), 1, 5, 0);
        QVERIFY(r.value("ok").toBool());
        QCOMPARE(r.value("value").toList().size(), m_service->getAll().size());
    }

    // === 边界 ===
    void test_get_by_month_zero_means_all() {
        // 2026-09-14 起 month=0 约定为"全部月份", 不是非法输入
        const QVariantList all = m_service->getAll();
        QVariantList results = m_service->getByMonth(0);
        QCOMPARE(results.size(), all.size());
    }

    void test_get_by_month_out_of_range_also_returns_all() {
        // 实现用 (month < 1 || month > 12) 走同一个"全部"分支, 与 0 等价
        const QVariantList all = m_service->getByMonth(0);
        QCOMPARE(m_service->getByMonth(13).size(), all.size());
        QCOMPARE(m_service->getByMonth(-1).size(), all.size());
    }

    void test_get_by_month_filters_best_season() {
        QVariantList july = m_service->getByMonth(7);
        QVERIFY(july.size() > 0);
        for (const auto& r : july) {
            QVERIFY(r.toMap()["bestSeason"].toStringList().contains("7月"));
        }
    }

    // === 搜索 ===
    void test_search_keyword() {
        QVariantList results = m_service->search("太行");
        QVERIFY(results.size() > 0);
        for (const auto& r : results) {
            QVariantMap route = m_service->getById(r.toMap()["id"].toString());
            // 命中条件是 name/mountain/area/province/description 任一包含关键词
            bool hit = route["name"].toString().contains("太行") ||
                       route["mountain"].toString().contains("太行") ||
                       route["area"].toString().contains("太行") ||
                       route["province"].toString().contains("太行") ||
                       route["description"].toString().contains("太行");
            QVERIFY2(hit, qPrintable(route["name"].toString()));
        }
    }

    void test_search_empty() {
        // search("") 直接返回空列表 (与 SpeciesService/FirstAidService 一致),
        // 全量列表请用 getAll()
        QCOMPARE(m_service->search("").size(), 0);
    }

    // === 6000m+ 不推荐规则 ===
    void test_6000m_plus_not_recommended() {
        // getAll 已按 isRecommended() 过滤: 海拔 ≥6000 的路线只允许「休闲徒步/休闲登山」
        QVariantList all = m_service->getAll();
        QVERIFY(all.size() > 0);
        for (const auto& item : all) {
            const QVariantMap r = m_service->getById(item.toMap()["id"].toString());
            if (r["maxAltitudeM"].toInt() >= 6000) {
                const QString type = r["type"].toString();
                QVERIFY2(type == "休闲徒步" || type == "休闲登山",
                         qPrintable(QStringLiteral("%1: %2m type=%3").arg(r["id"].toString())
                                        .arg(r["maxAltitudeM"].toInt()).arg(type)));
            }
        }
        // notRecommended 显式标记的路线绝不能出现在 getAll 里
        for (const auto& item : all) {
            QVERIFY(!m_service->getById(item.toMap()["id"].toString())["notRecommended"].toBool());
        }
    }

    // === 收藏/计数 ===
    void test_add_delete_favorite() {
        QVariantList all = m_service->getAll();
        QString id = all.first().toMap()["id"].toString();
        // 阶段 L3.x: 写操作返回 Result {ok, value, error}
        QVERIFY(m_service->addFavorite(id).value("ok").toBool());
        QVERIFY(m_service->isFavorite(id));
        QVERIFY(m_service->deleteFavorite(id).value("ok").toBool());
        QVERIFY(!m_service->isFavorite(id));
    }

    void test_favorite_unknown_id() {
        QVERIFY(!m_service->addFavorite("nonexistent_route_id_999").value("ok").toBool());
    }

    void test_increment_visit_count() {
        QVariantList all = m_service->getAll();
        QString id = all.first().toMap()["id"].toString();
        QVERIFY(m_service->incrementVisitCount(id).value("ok").toBool());
        QVERIFY(m_service->incrementVisitCount(id).value("ok").toBool());
        // 计数落库后由 getMostVisited 读出, 至少应包含该路线
        bool found = false;
        for (const auto& r : m_service->getMostVisited(10)) {
            if (r.toMap()["id"].toString() == id) found = true;
        }
        QVERIFY(found);
    }

    // === 路线性质 ===
    void test_route_nature() {
        QVariantMap r = m_service->getById(
            m_service->getAll().first().toMap()["id"].toString());
        QString nature = r["routeNature"].toString();
        QVERIFY(nature == "穿越" || nature == "环线" || nature == "单程");
    }

    // === 评分字段 ===
    void test_score_field() {
        QVariantMap r = m_service->getById(
            m_service->getAll().first().toMap()["id"].toString());
        int score = r["score"].toInt();
        QVERIFY(score >= 0 && score <= 100);
    }
};

QTEST_MAIN(TestRouteService)
#include "test_route_service.moc"
