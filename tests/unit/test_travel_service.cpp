/**
 * @file test_travel_service.cpp
 * @brief 自驾游服务单元测试
 */

#include <QtTest>
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QJsonArray>
#include <QJsonObject>

#include "src/travel/TravelService.h"
#include "src/core/AssetLoader.h"
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
    void test_loadInitialCount() {  // 2026-10-22: 原名 test_load_initial_data, *_data 无配对 = 从不执行
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

    // 2026-10-27 #132: 地点级检索. 与 RouteService::searchPlaces 同一张表结构 ——
    // 「查找」Tab 的地点模式把两个来源合并成同一个列表渲染, 一边缺键就画出一行空字.
    void test_searchPlaces_contract() {
        // 注意与 search("") 相反: 地点检索没有"全量端点"这种东西, 空关键词必须是空表
        QCOMPARE(m_service->searchPlaces(QString()).size(), 0);

        QString poi, routeId;
        for (const auto& item : m_service->getAll()) {
            const QVariantMap t = m_service->getById(item.toMap()["id"].toString());
            const QString n = t["startName"].toString();
            const double lat = t["startLat"].toDouble();
            const double lon = t["startLon"].toDouble();
            if (n.length() >= 2 && !(lat == 0.0 && lon == 0.0)) {
                poi = n;
                routeId = t["id"].toString();
                break;
            }
        }
        QVERIFY2(!poi.isEmpty(), "库里没有一个带坐标的起点名, 这条测试就没意义");

        const QVariantList hits = m_service->searchPlaces(poi, 40);
        QVERIFY2(hits.size() > 0, qPrintable(QStringLiteral("搜自己的起点名 %1 却 0 命中").arg(poi)));
        bool ownHit = false;
        for (const auto& v : hits) {
            const QVariantMap m = v.toMap();
            QVERIFY(!m["name"].toString().isEmpty());
            QVERIFY(!m["routeId"].toString().isEmpty());
            QVERIFY(!m["routeName"].toString().isEmpty());
            const QString side = m["side"].toString();
            QVERIFY2(side == QStringLiteral("起点") || side == QStringLiteral("终点"),
                     qPrintable(side));
            QVERIFY(m["id"].toString() == m["routeId"].toString()
                    + (side == QStringLiteral("起点") ? QStringLiteral("#start")
                                                      : QStringLiteral("#end")));
            QVERIFY2(!(m["lat"].toDouble() == 0.0 && m["lon"].toDouble() == 0.0),
                     "缺坐标的哨兵不该出现在地点结果里");
            if (m["routeId"].toString() == routeId && side == QStringLiteral("起点"))
                ownHit = true;
        }
        QVERIFY(ownHit);
        QVERIFY2(hits.first().toMap()["name"].toString()
                     .contains(poi, Qt::CaseInsensitive),
                 qPrintable(hits.first().toMap()["name"].toString()));
    }

    // === tag 字段 (2026-10-20) ===
    // travel.json 用的是单数 "tag" + "/" 连接字符串, loader 原本读复数数组 "tags"
    // → 每条 tags 恒空 → 按标签搜永远 0 命中. 这条钉住拆分与搜索两条链路.
    void test_tags_split_and_searchable() {
        QVariantList all = m_service->getAll();
        QVERIFY(all.size() >= 100);
        int withTags = 0;
        for (const auto& v : all) {
            const QStringList tags = v.toMap()["tags"].toStringList();
            if (!tags.isEmpty()) withTags++;
            // 拆分后不该再残留分隔符, 也不该有空段
            for (const QString& t : tags) {
                QVERIFY2(!t.contains('/'), qPrintable(t));
                QVERIFY2(!t.trimmed().isEmpty(), qPrintable(t));
            }
        }
        QCOMPARE(withTags, all.size());

        // "318" 只出现在 tag 里 (路线名是 "川藏线南线(成都-拉萨)" 之类),
        // 之前恒为空 → 命中 0; 现在应能搜到.
        QVariantList byTag = m_service->search("318");
        QVERIFY2(byTag.size() > 0, "search(\"318\") 没命中, tag 链路又断了");
        bool sawKnown = false;
        for (const auto& v : m_service->getAll()) {
            if (v.toMap()["tags"].toStringList().contains(QStringLiteral("川西"))) sawKnown = true;
        }
        QVERIFY2(sawKnown, "没有任何一条的 tag 段是「川西」, 拆分口径变了");
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
        QVERIFY(months.size() > 1);
        // 2026-09-14 起首项固定是筛选用 "全部", 不带 "月", 从第 2 项起才是月份
        QCOMPARE(months.first(), QStringLiteral("全部"));
        for (int i = 1; i < months.size(); ++i) {
            QVERIFY(months.at(i).contains("月"));
        }
    }

    // === 端点精度元数据 (2026-10-27 #131c) ===
    // 自驾库里 88/101 条的起点坐标与终点坐标逐位相同 —— 两端取的是同一个城区中心
    // 点。TravelDetailPage 用 coordSource 说清这件事, MapPage 用它拼读数条; 这几句
    // 话只有在键真的从 travel.json 读到时才成立。写成断言是因为读错键 (蛇形/驼峰混用,
    // #44 C2) 的表现是"读数条安静地少一段", 肉眼看不出来。
    void test_coord_metadata_reaches_ui() {
        int total = 0, cityCenter = 0, editorial = 0, precise = 0;
        for (const auto& v : m_service->getAll()) {
            const QString id = v.toMap()["id"].toString();
            const QVariantMap t = m_service->getById(id);
            QVERIFY2(!t.isEmpty(), qPrintable(id + " getById 返回空"));
            ++total;
            const QString src = t["coordSource"].toString();
            const int m = t["coordPrecisionM"].toInt();
            QVERIFY2(src == "city_center" || src == "editorial_estimate",
                     qPrintable(id + ": coordSource 读出来是 \"" + src + "\""));
            if (src == "city_center") ++cityCenter; else ++editorial;
            if (m > 0) ++precise;
            QVERIFY2(m <= 56000, qPrintable(id + ": 精度读数超出库内上限"));
            // city_center 的含义就是"两端同一个点", 标记与数据必须互证
            if (src == "city_center") {
                QVERIFY2(t["startLat"].toDouble() == t["endLat"].toDouble()
                         && t["startLon"].toDouble() == t["endLon"].toDouble(),
                         qPrintable(id + ": 标了 city_center 但两端不是同一个点"));
            }
        }
        QVERIFY2(total >= 100, "自驾库条数不对, 上面这些计数没有意义");
        // 反证: loader 一个键都没读时 cityCenter/editorial/precise 会一起塌成 0,
        // 光看 "src 非空" 是挡不住的 (空串不等于任何已知来源, 但 total 仍然过)
        QVERIFY2(cityCenter >= 50, qPrintable(QString("城区中心点只有 %1 条").arg(cityCenter)));
        QVERIFY2(editorial >= 5, qPrintable(QString("editorial_estimate 只有 %1 条").arg(editorial)));
        QVERIFY2(precise == total, qPrintable(QString("%1/%2 条标了精度").arg(precise).arg(total)));
        qInfo() << "travel coord metadata:" << total << "records,"
                << cityCenter << "city_center," << editorial << "editorial," << precise << "with precision";
    }

    // 与 routes 侧同一件事: 全工程"没有坐标"的约定是 (0,0) 这一对。QGeoCoordinate
    // 未设置时 latitude()/longitude() 返回 91.0/181.0, 那不是 0, QML 的 _validCoord
    // 会放行并画出一个境外点 —— 所以库里既不许出现哨兵, 标记也必须与数据一致。
    void test_endpoints_never_leak_invalid_sentinel() {
        for (const auto& v : m_service->getAll()) {
            const QString id = v.toMap()["id"].toString();
            const QVariantMap t = m_service->getById(id);
            for (const QString& side : {QString("start"), QString("end")}) {
                const double la = t[side + "Lat"].toDouble();
                const double lo = t[side + "Lon"].toDouble();
                QVERIFY2(qAbs(la) <= 90.0 && qAbs(lo) <= 180.0,
                         qPrintable(id + ": " + side + " = " + QString::number(la) + ", "
                                    + QString::number(lo) + " (91/181 是 QGeoCoordinate 未设置的哨兵)"));
                const bool missing = (la == 0.0 && lo == 0.0);
                if (side == "end") {
                    // 没有坐标必须有标记, 否则 UI 只能整行不说, 看着像数据丢了
                    if (missing) QVERIFY2(t["endCoordUnavailable"].toBool(),
                                          qPrintable(id + ": 终点无坐标但没标 endCoordUnavailable"));
                } else {
                    QVERIFY2(!missing, qPrintable(id + ": 起点没有坐标, 自驾页无法定位"));
                }
            }
            // 端点缺坐标时地名必须还在: 不知道在哪 ≠ 不知道是什么地方
            if (t["endCoordUnavailable"].toBool())
                QVERIFY2(!t["endName"].toString().isEmpty(), qPrintable(id + ": 终点名字被一起清了"));
        }
    }

    // 蛇形键在 travel.json 里等于没写: TravelService::loadFromJson 读的是驼峰,
    // 这条把键名口径钉住 (门禁 tools/qml_checks/coord_metadata_check.js 从数据侧查同一件事)。
    void test_travel_json_keys_are_camelcase() {
        QString err;
        auto doc = AssetLoader::loadJson("travel.json", &err);
        QVERIFY2(doc.has_value(), qPrintable(err));
        const QJsonArray arr = doc->object()["routes"].toArray();
        QVERIFY(arr.size() >= 100);
        for (const auto& v : arr) {
            const QJsonObject o = v.toObject();
            QVERIFY2(!o.contains("coord_precision_m"),
                     qPrintable(o["id"].toString() + ": travel.json 出现蛇形键, 解析端读不到"));
            QVERIFY2(!o.contains("coord_source"),
                     qPrintable(o["id"].toString() + ": travel.json 出现蛇形键 coord_source"));
            QVERIFY2(o.contains("coordPrecisionM") && o.contains("coordSource"),
                     qPrintable(o["id"].toString() + ": 缺 coordPrecisionM/coordSource"));
        }
    }
};

QTEST_MAIN(TestTravelService)
#include "test_travel_service.moc"
