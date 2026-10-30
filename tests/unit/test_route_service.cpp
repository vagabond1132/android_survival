/**
 * @file test_route_service.cpp
 * @brief 路线服务单元测试
 */

#include <QtTest>
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QJsonDocument>
#include <QJsonObject>

#include "src/routes/RouteService.h"
#include "src/core/AssetLoader.h"
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
    void test_loadInitialCount() {  // 2026-10-22: 原名 test_load_initial_data, *_data 无配对 = 从不执行
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

    // 2026-10-27 #132: 地点级检索. 「查找」Tab 的地点模式把这张表直接当列表模型渲染
    // (SearchTab 读 name/region/routeName/side + lat/lon), 所以契约是"键齐不齐"而不是
    // 排序细节; (0,0) 哨兵与空关键词两条也一并钉住 —— 前者会跳几内亚湾, 后者会把
    // 1500 个端点当搜索结果倒进抽屉.
    void test_searchPlaces_contract() {
        QCOMPARE(m_service->searchPlaces(QString()).size(), 0);
        QCOMPARE(m_service->searchPlaces(QStringLiteral("   ")).size(), 0);

        // 关键词从真数据里取, 不把地名写死在断言里 (数据一改就假失败)
        QString poi, routeId;
        for (const auto& item : m_service->getAll()) {
            const QVariantMap r = m_service->getById(item.toMap()["id"].toString());
            const QString n = r["trailheadName"].toString();
            const double lat = r["trailheadLat"].toDouble();
            const double lon = r["trailheadLon"].toDouble();
            if (n.length() >= 2 && !(lat == 0.0 && lon == 0.0)) {
                poi = n;
                routeId = r["id"].toString();
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
            const QString side = m["side"].toString();
            QVERIFY2(side == QStringLiteral("起点") || side == QStringLiteral("终点"),
                     qPrintable(side));
            QVERIFY(m["id"].toString().endsWith(QStringLiteral("#start"))
                    || m["id"].toString().endsWith(QStringLiteral("#end")));
            QVERIFY2(!(m["lat"].toDouble() == 0.0 && m["lon"].toDouble() == 0.0),
                     "缺坐标的哨兵不该出现在地点结果里");
            if (m["routeId"].toString() == routeId && side == QStringLiteral("起点"))
                ownHit = true;
        }
        QVERIFY(ownHit);
        // POI 名命中 (3 分) 必须排在只命中省/市/山 (1 分) 的前面
        QVERIFY2(hits.first().toMap()["name"].toString()
                     .contains(poi, Qt::CaseInsensitive),
                 qPrintable(hits.first().toMap()["name"].toString()));
    }

    // limit 是硬上限: 抽屉一次画 80 行已经到底了, 服务层不能把全库倒给它.
    void test_searchPlaces_respectsLimit() {
        const QVariantList hits = m_service->searchPlaces(QStringLiteral("山"), 5);
        QVERIFY(hits.size() > 0);
        QVERIFY(hits.size() <= 5);
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

    // === 评分分项 ===
    // 2026-10-20 修 loader: routes.json 里这一项是驼峰键 "scoreDetail" 而且值是对象,
    // 原来读的是下划线 "score_detail" 并用 QJsonValue::toString() 取对象 —— 键不存在,
    // 且 toString() 对对象也返回空串, 两道都落空. 后果是 entity.scoreDetail 全站恒为
    // 空, 详情页 11 项分项 (海拔/路况/爬升/水源/蛇虫/危险/长度/补给/季节/救援/线路调整)
    // 一个都渲染不出来. 这条把契约钉住: 有分的路线必须带可解析的分项 JSON, 分项之和 == score.
    void test_score_detail_json_roundtrip() {
        int withScore = 0;
        for (const auto& v : m_service->getAll()) {
            const QString id = v.toMap()["id"].toString();
            const QVariantMap r = m_service->getById(id);
            const int score = r["score"].toInt();
            const QString detail = r["scoreDetail"].toString();

            // 库里 755 条有 28 条既没有 score 也没有 scoreDetail (青神山那批 +
            // 6 条两步路实测轨迹: KML 只撑得起 11 项分项里的 4 项),
            // 两者必须同进同退 —— 有分无项 / 有项无分都算数据口径破了.
            if (score <= 0) {
                QVERIFY2(detail.isEmpty(),
                         qPrintable(id + ": score 为 0 却带 scoreDetail"));
                continue;
            }
            ++withScore;
            QVERIFY2(!detail.isEmpty(), qPrintable(id + ": scoreDetail 为空"));

            QJsonParseError err;
            const QJsonDocument doc = QJsonDocument::fromJson(detail.toUtf8(), &err);
            QVERIFY2(err.error == QJsonParseError::NoError,
                     qPrintable(id + ": " + err.errorString()));
            QVERIFY(doc.isObject());

            const QJsonObject o = doc.object();
            QVERIFY2(o.contains("altitude") && o.contains("road") && o.contains("danger"),
                     qPrintable(id + ": 分项键不全"));
            int sum = 0;
            for (auto it = o.constBegin(); it != o.constEnd(); ++it) sum += it.value().toInt();
            QVERIFY2(sum == score,
                     qPrintable(id + QString(": 分项和 %1 != score %2").arg(sum).arg(score)));
        }
        // 全部路线都跑一遍, 至少要覆盖到有分项的那批。
        // 循环走的是 getAll() = isRecommended 过滤后的 753 条 (库里 755 条, 2 条 6000m+
        // 不推荐的恰好都带分), 28 条无分全在这 753 条里, 所以这里报出的 withScore 是
        // 725 而不是 755-28=727 —— 看日志时别以为少了两条。
        QVERIFY2(withScore > 500, "带分项的路线太少, 说明 loader 又读空了");
        qInfo() << "scoreDetail round-trip checked on" << withScore << "routes";
    }

    // === 实测轨迹入库 (2026-10-27 #131) =====================================
    // getWaypoints() 是全工程唯一的 polyline 通道 (MapPage 靠它连线), 而 waypoints
    // 表此前只建不写: routes.json 装载时没人灌, 于是全库路线在图上全部退化成
    // approx:true 的起终点直线。这几条钉住"灌了、顺序对、没灌的仍然是空"。
    void test_waypoints_seeded_from_json() {
        QString err;
        auto doc = AssetLoader::loadJson("routes.json", &err);
        QVERIFY2(doc.has_value(), qPrintable(err));
        const QJsonArray arr = doc->object()["routes"].toArray();

        int seeded = 0, expectedTotal = 0;
        for (const auto& v : arr) {
            const QJsonObject o = v.toObject();
            const QJsonArray wps = o["waypoints"].toArray();
            if (wps.isEmpty()) continue;
            ++seeded;
            // (0,0) 是"没填"的哨兵, 装载时被跳过, 期望值要按同一口径算
            int want = 0;
            for (const auto& p : wps) {
                const QJsonObject po = p.toObject();
                if (po["lat"].toDouble() == 0.0 && po["lon"].toDouble() == 0.0) continue;
                ++want;
            }
            const QString id = o["id"].toString();
            const QVariantList got = m_service->getWaypoints(id);
            QVERIFY2(got.size() == want,
                     qPrintable(id + ": 库里 " + QString::number(got.size())
                                + " 点, JSON 写了 " + QString::number(want)));
            QCOMPARE(m_service->waypointCount(id), static_cast<int>(got.size()));
            expectedTotal += want;
        }
        // 反证 ①: 装载通路真的没被写死成空 —— 至少要有一条实测轨迹进来
        QVERIFY2(seeded >= 1, "没有任何一条路线带上 waypoints, 入库通路又断了");
        QVERIFY2(expectedTotal >= 50,
                 qPrintable(QString("实测轨迹点数太少 (%1), 不像是走过一圈的线").arg(expectedTotal)));
        // 反证 ②: "全都非空"同样不对 —— 库里绝大多数路线仍然只有起终点,
        // 断言这个 0 仍然存在, 否则说明 getWaypoints 在返回假数据。
        int empty = 0;
        for (const auto& v : m_service->getAll())
            if (m_service->getWaypoints(v.toMap()["id"].toString()).isEmpty()) ++empty;
        QVERIFY2(empty > 500, qPrintable(QString("只剩 %1 条路线没有路径点?").arg(empty)));
        qInfo() << "waypoints seeded:" << seeded << "routes," << expectedTotal << "points;"
                << empty << "routes still have none";
    }

    void test_waypoints_keep_sequence_and_types() {
        QVariantList wps;
        QString rid;
        for (const auto& v : m_service->getAll()) {
            const QString id = v.toMap()["id"].toString();
            const QVariantList l = m_service->getWaypoints(id);
            if (l.size() >= 50) { rid = id; wps = l; break; }
        }
        QVERIFY2(!rid.isEmpty(), "找不到一条 ≥50 点的实测轨迹");
        // 首尾必须是起终点 (MapPage 的 S/E 标记取的就是这两点)
        QCOMPARE(wps.first().toMap()["type"].toString(), QString("start"));
        QCOMPARE(wps.last().toMap()["type"].toString(), QString("end"));
        // 中间一律是 track/poi, 不许混进第二个 start/end —— 顺序乱了说明
        // ORDER BY sequence 没生效 (灌库时 sequence 写错或没写)。
        for (int i = 1; i < wps.size() - 1; ++i) {
            const QString t = wps[i].toMap()["type"].toString();
            QVERIFY2(t == "track" || t == "poi",
                     qPrintable(rid + " #" + QString::number(i) + ": 中间点类型 " + t));
        }
        // 高程是真的 (GPS 原始海拔, 没做椭球高→正高改正): 全 0 说明列没落库
        int withAlt = 0;
        for (const auto& w : wps)
            if (w.toMap()["elevation"].toInt() > 0) ++withAlt;
        QVERIFY2(withAlt == wps.size(),
                 qPrintable(rid + ": " + QString::number(withAlt) + "/"
                            + QString::number(wps.size()) + " 点有高程序列"));
    }

    void test_coord_precision_metadata_exposed() {
        // total 来自 getAll(), 它按 isRecommended 过滤: 库里 755 条, 这里看到 753 条
        // (库拉岗日 6450m、玉珠峰 6178m 两条 6000m+ 默认不推荐)。那 2 条的元数据由
        // tools/qml_checks/coord_metadata_check.js 在 JSON 层全覆盖, 不靠这条兜底。
        int labeled = 0, precise = 0, coarse = 0;
        for (const auto& v : m_service->getAll()) {
            const QVariantMap r = m_service->getById(v.toMap()["id"].toString());
            if (!r["coordSource"].toString().isEmpty()) ++labeled;
            const int m = r["coordPrecisionM"].toInt();
            if (m > 0) ++precise;
            if (m >= 5000) ++coarse;      // 整数度端点: ±5.6 公里
            // 读数条要能同时容下两端: ±10 米 与 ±56 公里都是真实存在的量级
            if (m > 0) QVERIFY2(m <= 56000,
                                qPrintable(v.toMap()["id"].toString() + ": 精度读数超出库内上限"));
        }
        const int total = m_service->getAll().size();
        QVERIFY2(labeled == total, qPrintable(QString("%1/%2 条有 coordSource").arg(labeled).arg(total)));
        // 反证: 若 loader 一个键都没读, precise/coarse 会一起塌成 0
        QVERIFY2(precise >= total - 20, qPrintable(QString("只有 %1 条标了精度").arg(precise)));
        QVERIFY2(coarse >= 50, qPrintable(QString("±5 公里量级的记录只有 %1 条, 分布不对").arg(coarse)));
        qInfo() << "coord metadata:" << labeled << "labeled," << precise << "precise,"
                << coarse << "coarse (>=5km)";
    }

    // 可证伪端点清理后的读法: 坐标删掉、地名留着, 而且不许把 QGeoCoordinate 的
    // "未设置" 哨兵 (91.0 / 181.0) 漏给 QML —— 那既不是 0 (QML 的 _validCoord 会放行),
    // 也不是任何中国境内的点。
    void test_cleaned_endpoint_reads_as_no_coordinate() {
        QString victim;
        QString err;
        auto doc = AssetLoader::loadJson("routes.json", &err);
        QVERIFY2(doc.has_value(), qPrintable(err));
        for (const auto& v : doc->object()["routes"].toArray()) {
            const QJsonObject o = v.toObject();
            if (o["trailend"].toObject()["coord_unavailable"].toBool(false)) {
                victim = o["id"].toString();
                break;
            }
        }
        QVERIFY2(!victim.isEmpty(), "routes.json 里没有任何 coord_unavailable 端点, 清理没落盘");

        const QVariantMap r = m_service->getById(victim);
        QCOMPARE(r["trailendLat"].toDouble(), 0.0);
        QCOMPARE(r["trailendLon"].toDouble(), 0.0);
        QCOMPARE(r["trailendCoordUnavailable"].toBool(), true);
        // 名称与地址必须还在: 不知道在哪 ≠ 不知道是什么地方
        QVERIFY2(!r["trailendName"].toString().isEmpty(),
                 qPrintable(victim + ": 端点名字被一起清掉了"));

        int checked = 0;
        for (const auto& v : m_service->getAll()) {
            const QVariantMap e = m_service->getById(v.toMap()["id"].toString());
            for (const QString& key : {QString("trailhead"), QString("trailend")}) {
                const double la = e[key + "Lat"].toDouble();
                const double lo = e[key + "Lon"].toDouble();
                if (la == 0.0 && lo == 0.0) continue;   // 哨兵: 没有坐标
                QVERIFY2(qAbs(la) <= 90.0 && qAbs(lo) <= 180.0,
                         qPrintable(v.toMap()["id"].toString() + ": " + key
                                    + " 漏出了 " + QString::number(la) + ", " + QString::number(lo)));
            }
            ++checked;
        }
        QVERIFY2(checked > 500, "只抽查了几条, 覆盖不住");
        qInfo() << "endpoint sentinel checked on" << checked << "routes; victim" << victim;
    }
};

QTEST_MAIN(TestRouteService)
#include "test_route_service.moc"
