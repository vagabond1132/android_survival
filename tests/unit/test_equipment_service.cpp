/**
 * @file test_equipment_service.cpp
 * @brief 装备服务单元测试 (2026-09-21: 阶段 I-3 EquipmentEngine → EquipmentService 改名)
 *
 * 2026-10-16: 本套件此前从未编译通过, 按 EquipmentService.h 的真实 API 重写:
 *   - 构造函数是 EquipmentService(QObject*), 不吃 Database; 初始化叫 initialize() 不叫 loadInitialData()
 *   - 海拔枚举现在只有一个定义源 src/common/AltitudeLevel.h (7 段 L0-L6)，
 *     EquipmentAltitudeLevel 只是它的别名；2026-10-21 #18 C3 之前这里有两份
 *     (MapService 那份是 5 段封顶)，同一个高度两边读成不同档
 *   - generateList(name, QVariantMap) 返回 {id, critical/important/recommended/optional}, 没有 "items"
 *   - startCheck/getCheckProgress 返回 {listId, total, checked, progress}, 没有 "totalItems"
 */

#include <QtTest>
#include <QCoreApplication>
#include <QTemporaryDir>
#include <cmath>     // 2026-11-03 #45: std::isfinite 校验气候表锚点坐标
#include <limits>    // 2026-11-03 #45: numeric_limits<double>::infinity()

#include "src/equipment/EquipmentService.h"
#include "src/map/MapService.h"  // 2026-10-21 (#18 C3): 跨服务比对同一个高度的档位读法

using namespace outdoor;

namespace {

// generateList 的入参: 键名与 EquipmentService::generateList 逐字段对齐
QVariantMap tripParams(int altitudeMax, int days) {
    QVariantMap p;
    p["altitudeMax"] = altitudeMax;
    p["altitudeMin"] = qMax(0, altitudeMax - 500);
    p["altitudeCamp"] = qMax(0, altitudeMax - 200);
    p["days"] = days;
    p["people"] = 1;
    p["difficulty"] = 2;
    p["season"] = static_cast<int>(Season::Summer);
    p["tempAvg"] = 15.0;
    p["tempMin"] = 5.0;
    p["windSpeed"] = 2.0;
    p["precipitation"] = 0;
    p["uvIndex"] = 5.0;
    return p;
}

int bucketTotal(const QVariantMap& list) {
    return list["critical"].toList().size() + list["important"].toList().size()
         + list["recommended"].toList().size() + list["optional"].toList().size();
}

}  // namespace

class TestEquipmentService : public QObject {
    Q_OBJECT

private:
    EquipmentService* m_engine = nullptr;

private slots:
    void init() {
        m_engine = new EquipmentService();
        QVERIFY(m_engine->initialize());
        // 偏好存在 QSettings, 用例之间会串, 每次清空
        m_engine->clearPreferences();
    }

    void cleanup() {
        m_engine->clearPreferences();
        delete m_engine;
        m_engine = nullptr;
    }

    // === 海拔分级 (7 段, 上界开区间) ===
    void test_altitude_level_boundaries() {
        QCOMPARE(m_engine->getAltitudeLevel(0), EquipmentAltitudeLevel::L0);
        QCOMPARE(m_engine->getAltitudeLevel(100), EquipmentAltitudeLevel::L0);
        QCOMPARE(m_engine->getAltitudeLevel(499), EquipmentAltitudeLevel::L0);
        QCOMPARE(m_engine->getAltitudeLevel(500), EquipmentAltitudeLevel::L1);
        QCOMPARE(m_engine->getAltitudeLevel(1000), EquipmentAltitudeLevel::L1);
        QCOMPARE(m_engine->getAltitudeLevel(1500), EquipmentAltitudeLevel::L2);
        QCOMPARE(m_engine->getAltitudeLevel(2000), EquipmentAltitudeLevel::L2);
        QCOMPARE(m_engine->getAltitudeLevel(2500), EquipmentAltitudeLevel::L3);
        QCOMPARE(m_engine->getAltitudeLevel(3000), EquipmentAltitudeLevel::L3);
        QCOMPARE(m_engine->getAltitudeLevel(3500), EquipmentAltitudeLevel::L4);
        QCOMPARE(m_engine->getAltitudeLevel(4500), EquipmentAltitudeLevel::L5);
        QCOMPARE(m_engine->getAltitudeLevel(5500), EquipmentAltitudeLevel::L6);
        QCOMPARE(m_engine->getAltitudeLevel(8848), EquipmentAltitudeLevel::L6);
    }

    // === 海拔颜色 / 名称 ===
    void test_altitude_level_names() {
        for (int i = 0; i <= 6; ++i) {
            const EquipmentAltitudeLevel lvl = static_cast<EquipmentAltitudeLevel>(i);
            QVERIFY(!m_engine->getAltitudeLevelName(lvl).isEmpty());
            // getAltitudeLevelColor 已于 2026-10-21 (#18 C3) 删除: 色源只剩 CommonOptions.
        }
    }

    // === 两个服务对同一个高度必须读成同一档 (#18 C3 的意义所在) ===
    void test_altitude_level_matches_map_service() {
        const int heights[] = { 0, 499, 500, 1500, 2500, 3500, 4500, 5500, 8848 };
        for (int h : heights) {
            QCOMPARE(static_cast<int>(m_engine->getAltitudeLevel(h)),
                     static_cast<int>(MapService::getAltitudeLevel(static_cast<double>(h))));
        }
    }

    void test_altitude_segment_has_range() {
        const QJsonObject seg = EquipmentService::getAltitudeSegment(EquipmentAltitudeLevel::L3);
        QVERIFY(!seg.isEmpty());
    }

    // === 装备项 ===
    void test_get_all_items() {
        const QVariantList items = m_engine->getAllItems();
        // equipment_base.json 有 49 条
        QVERIFY2(items.size() >= 49, qPrintable(QStringLiteral("装备库 %1 条").arg(items.size())));
        QCOMPARE(items.size(), m_engine->totalItems());
        for (const auto& i : items) {
            QVERIFY(!i.toMap()["id"].toString().isEmpty());
            QVERIFY(!i.toMap()["name"].toString().isEmpty());
        }
    }

    void test_total_rules() {
        // equipment_rules.json 有 39 条规则
        QVERIFY2(m_engine->totalRules() >= 39,
                 qPrintable(QStringLiteral("规则 %1 条").arg(m_engine->totalRules())));
    }

    void test_get_critical_items() {
        const QVariantList critical = m_engine->getCriticalItems();
        QVERIFY(critical.size() > 0);
        for (const auto& i : critical) {
            const QString id = i.toMap()["id"].toString();
            QVERIFY2(m_engine->getById(id)["isCritical"].toBool(), qPrintable(id));
        }
    }

    void test_get_item_by_id() {
        const QVariantList all = m_engine->getAllItems();
        QVERIFY(!all.isEmpty());
        const QString firstId = all.first().toMap()["id"].toString();
        const QVariantMap item = m_engine->getById(firstId);  // 2026-09-20: rename from getItem
        QVERIFY(!item.isEmpty());
        QCOMPARE(item["id"].toString(), firstId);
    }

    void test_get_item_by_id_nonexistent() {
        QVERIFY(m_engine->getById("nonexistent_999").isEmpty());
    }

    // === 分类筛选 ===
    void test_get_items_by_category() {
        const QVariantList warm = m_engine->getItemsByCategory("warmth");
        QVERIFY(warm.size() > 0);
        for (const auto& i : warm) {
            // getItemsByCategory 的精简 map 不含 category, 回查 getById
            QVERIFY(m_engine->getById(i.toMap()["id"].toString())["category"].toString()
                    == QStringLiteral("warmth"));
        }
        QVERIFY(m_engine->getItemsByCategory("no_such_category").isEmpty());
    }

    // === 智能生成清单 ===
    void test_generate_list_low_altitude() {
        const QVariantMap generated = m_engine->generateList("上海一日徒步", tripParams(100, 1));
        QVERIFY(!generated["id"].toString().isEmpty());
        QCOMPARE(generated["altitudeLevel"].toInt(), static_cast<int>(EquipmentAltitudeLevel::L0));

        const QVariantMap list = m_engine->getList(generated["id"].toString());
        QVERIFY(!list.isEmpty());
        QVERIFY(bucketTotal(list) > 0);
        // 兜底规则保证基础库每个 item 都出现在某个桶里
        QCOMPARE(bucketTotal(list), m_engine->totalItems());
    }

    void test_generate_list_high_altitude() {
        const QVariantMap generated = m_engine->generateList("珠峰大本营", tripParams(5000, 5));
        const QVariantMap list = m_engine->getList(generated["id"].toString());
        QVERIFY(!list.isEmpty());
        QCOMPARE(generated["altitudeLevel"].toInt(), static_cast<int>(EquipmentAltitudeLevel::L5));
        // 高海拔必须有"绝对必带"桶
        QVERIFY(!list["critical"].toList().isEmpty());

        const QVariantMap low = m_engine->getList(
            m_engine->generateList("低海拔", tripParams(100, 1))["id"].toString());
        // totalWeightG = sum of all items 无论 altitude 都一样 (兜底规则把 49 项都塞进桶),
        //   所以桶数量 (critical + important + recommended) 才是高海拔"背得更多"的体现.
        const int hiActive = list["critical"].toList().size()
                           + list["important"].toList().size()
                           + list["recommended"].toList().size();
        const int loActive = low["critical"].toList().size()
                           + low["important"].toList().size()
                           + low["recommended"].toList().size();
        QVERIFY2(hiActive > loActive,
                 qPrintable(QStringLiteral("高海拔有效装备 %1 ≤ 低海拔 %2")
                                .arg(hiActive).arg(loActive)));
    }

    void test_generate_list_more_days() {
        const QVariantMap r1 = m_engine->getList(
            m_engine->generateList("1天", tripParams(2000, 1))["id"].toString());
        const QVariantMap r7 = m_engine->getList(
            m_engine->generateList("7天", tripParams(2000, 7))["id"].toString());
        QVERIFY(!r1.isEmpty() && !r7.isEmpty());
        // 天数增加只会追加装备, 总重不降
        QVERIFY2(r7["totalWeightG"].toInt() >= r1["totalWeightG"].toInt(),
                 qPrintable(QStringLiteral("1天=%1 7天=%2")
                                .arg(r1["totalWeightG"].toInt())
                                .arg(r7["totalWeightG"].toInt())));
    }

    // === 2026-10-21: 冬季降雪档位真的改清单 (用户报"选冬天没有雪的选择") ===
    // 注意断言的是**档位**, 不是"有没有出现": 库里没被任何规则选中的 item 会被
    // _base_fallback 兜底进 Optional 桶, 49 项永远全在场.
    void test_generate_list_winter_snow_promotes_buckets() {
        auto bucketOf = [](const QVariantMap& list, const QString& itemId) -> QString {
            for (const QString& b : {QStringLiteral("critical"), QStringLiteral("important"),
                                     QStringLiteral("recommended")})
                for (const QVariant& v : list[b].toList())
                    if (v.toMap()["id"].toString() == itemId) return b;
            return QString();
        };
        auto winter = [](int precip) {
            QVariantMap p = tripParams(1200, 2);
            p["season"] = static_cast<int>(Season::Winter);
            p["precipitation"] = precip;
            // 2026-10-22 规则重写: 保暖档位改由 temp_min 分带决定, 雪档只管防滑/雪镜/手套.
            //   把夜间最低钉在 8℃ (温和冬夜, 一条 temp_min 保暖规则都不触发),
            //   这样下面读到的档位只可能来自雪规则, 测试才有归因.
            p["tempMin"] = 8.0;
            p["tempAvg"] = 11.0;
            return p;
        };
        auto list = [this](const QString& name, const QVariantMap& p) {
            return m_engine->getList(m_engine->generateList(name, p)["id"].toString());
        };

        const QVariantMap dry   = list("冬·无雪", winter(static_cast<int>(Precipitation::None)));
        const QVariantMap light = list("冬·小雪", winter(static_cast<int>(Precipitation::SnowLight)));
        const QVariantMap storm = list("冬·暴雪", winter(static_cast<int>(Precipitation::SnowStorm)));
        QVERIFY(!dry.isEmpty() && !light.isEmpty() && !storm.isEmpty());

        // 冰爪: 无雪不进档位, 小雪起进推荐, 大雪以上提到强必带
        QCOMPARE(bucketOf(dry, "crampons"), QString());
        QCOMPARE(bucketOf(light, "crampons"), QStringLiteral("recommended"));
        QCOMPARE(bucketOf(storm, "crampons"), QStringLiteral("important"));
        // 雪镜只在雪档, 且暴雪是"防雪盲"级别的必带
        QCOMPARE(bucketOf(dry, "snow_goggles"), QString());
        QCOMPARE(bucketOf(storm, "snow_goggles"), QStringLiteral("critical"));
        // 薄羽绒不再跟着雪走 (原来 R_SNOW_GRIP 把 crampons + light_down_jacket 捆在一条),
        // 捆在一起的后果是"下小雪就得带羽绒", 现在保暖只看温度 —— 见下面的分带用例.
        QCOMPARE(bucketOf(light, "light_down_jacket"), QString());
        QCOMPARE(bucketOf(storm, "down_jacket"), QString());

        // 反向: 雨档不能误触雪规则 (snow_* 与 heavy/storm 是两套 token)
        QVariantMap rain = tripParams(1200, 2);
        rain["precipitation"] = static_cast<int>(Precipitation::Heavy);
        const QVariantMap rainy = list("夏·大雨", rain);
        QCOMPARE(bucketOf(rainy, "crampons"), QString());
        QCOMPARE(bucketOf(rainy, "down_jacket"), QString());
        // 2026-10-22 补数据后的正向锁: 雨具规则原来因 rain_jacket 不在库里整条空转,
        //   现在必须真的涨档 (这条断言同时也是"规则引用了库外 id"的哨兵).
        QCOMPARE(bucketOf(rainy, "rain_jacket"), QStringLiteral("critical"));
    }

    // === 2026-10-22: 保暖看温度分带, 不再看海拔/季节猜 (用户报"没区分轻装重装") ===
    void test_generate_list_warmth_follows_temperature() {
        auto bucketOf = [](const QVariantMap& list, const QString& itemId) -> QString {
            for (const QString& b : {QStringLiteral("critical"), QStringLiteral("important"),
                                     QStringLiteral("recommended")})
                for (const QVariant& v : list[b].toList())
                    if (v.toMap()["id"].toString() == itemId) return b;
            return QString();
        };
        auto cold = [this](float tempMin) {
            QVariantMap p = tripParams(1200, 2);
            p["season"] = static_cast<int>(Season::Winter);
            p["tempMin"] = tempMin;
            p["tempAvg"] = tempMin + 4.0;
            return m_engine->getList(
                m_engine->generateList(QStringLiteral("夜温 %1").arg(tempMin), p)["id"].toString());
        };

        // 分带互斥: 一件厚羽绒 (-5..-15) 与一件极地羽绒 (<= -16) 不会同时必带
        const QVariantMap m5   = cold(-5.0f);
        const QVariantMap m20  = cold(-20.0f);
        QCOMPARE(bucketOf(m5, "down_jacket"), QStringLiteral("critical"));
        QCOMPARE(bucketOf(m5, "expedition_down"), QString());
        QCOMPARE(bucketOf(m20, "down_jacket"), QString());
        QCOMPARE(bucketOf(m20, "expedition_down"), QStringLiteral("critical"));
        // 睡袋按同一套温度带来: 0℃ 以上 5℃ 袋, -13℃ 以下 -30℃ 袋
        QCOMPARE(bucketOf(m5, "sleeping_bag_m30c"), QString());
        QCOMPARE(bucketOf(m20, "sleeping_bag_m30c"), QStringLiteral("critical"));
        QVERIFY2(m20["totalWeightG"].toInt() > m5["totalWeightG"].toInt(),
                 qPrintable(QStringLiteral("-20℃=%1 -5℃=%2")
                                .arg(m20["totalWeightG"].toInt())
                                .arg(m5["totalWeightG"].toInt())));
    }

    // === 2026-10-22: 轻装一日 ≠ 多日重装 (原来两边读出来是同一份清单) ===
    void test_generate_list_light_vs_heavy_load() {
        auto bucketOf = [](const QVariantMap& list, const QString& itemId) -> QString {
            for (const QString& b : {QStringLiteral("critical"), QStringLiteral("important"),
                                     QStringLiteral("recommended")})
                for (const QVariant& v : list[b].toList())
                    if (v.toMap()["id"].toString() == itemId) return b;
            return QString();
        };
        // 轻装一日: 1200m / 1 天 / 难度 2 → 推断为 DayHike
        const QVariantMap day = m_engine->getList(
            m_engine->generateList("轻装一日", tripParams(1200, 1))["id"].toString());
        // 多日重装: 3500m / 5 天 / 难度 3 → 推断为 Expedition
        QVariantMap heavy = tripParams(3500, 5);
        heavy["difficulty"] = 3;
        const QVariantMap exp = m_engine->getList(
            m_engine->generateList("多日重装", heavy)["id"].toString());
        QVERIFY(!day.isEmpty() && !exp.isEmpty());

        QCOMPARE(day["load"].toInt(), static_cast<int>(LoadStyle::DayHike));
        QCOMPARE(exp["load"].toInt(), static_cast<int>(LoadStyle::Expedition));
        // 宿营三件 (帐篷 / 防潮垫 / 炉具) 只在重装出现
        QCOMPARE(bucketOf(day, "tent_3season"), QString());
        QCOMPARE(bucketOf(day, "stove"), QString());
        QCOMPARE(bucketOf(exp, "tent_3season"), QStringLiteral("critical"));
        QCOMPARE(bucketOf(exp, "stove"), QStringLiteral("critical"));
        // 包本身也要分档: 28L 给轻装, 55L 给重装
        QCOMPARE(bucketOf(day, "pack_28l"), QStringLiteral("critical"));
        QCOMPARE(bucketOf(day, "pack_55l"), QString());
        QCOMPARE(bucketOf(exp, "pack_55l"), QStringLiteral("critical"));
        // 定量: 5 天重装的口粮根数必须多于 2 天基线
        auto qtyOf = [](const QVariantMap& list, const QString& itemId) -> int {
            for (const QString& b : {QStringLiteral("critical"), QStringLiteral("important"),
                                     QStringLiteral("recommended"), QStringLiteral("optional")})
                for (const QVariant& v : list[b].toList()) {
                    const QVariantMap m = v.toMap();
                    if (m["id"].toString() == itemId) return m["qty"].toInt();
                }
            return 0;
        };
        QVERIFY2(qtyOf(exp, "energy_bar") > qtyOf(day, "energy_bar"),
                 qPrintable(QStringLiteral("能量棒 轻装=%1 重装=%2")
                                .arg(qtyOf(day, "energy_bar")).arg(qtyOf(exp, "energy_bar"))));
        // 背负合计真的按档位变了 —— 这条是拦"总重恒等于整库重量"那个 bug 的:
        // 修之前两份都是 28285 g (可选兜底把 77 件全算上包了).
        const int wDay = day["totalWeightG"].toInt();
        const int wExp = exp["totalWeightG"].toInt();
        QVERIFY2(wDay > 0 && wDay <= 5000,
                 qPrintable(QStringLiteral("轻装一日合计 %1 g, 不该超过 5 kg").arg(wDay)));
        QVERIFY2(wExp > wDay * 2,
                 qPrintable(QStringLiteral("轻装 %1 g vs 多日重装 %2 g 没拉开").arg(wDay).arg(wExp)));
    }

    void test_generate_list_persisted_and_deletable() {
        const QString id = m_engine->generateList("待删除", tripParams(800, 1))["id"].toString();
        QVERIFY(!id.isEmpty());
        const QVariantMap all = m_engine->getAllLists();
        QVERIFY(all.value("ok").toBool());
        QStringList ids;
        for (const QVariant& v : all.value("value").toList()) ids << v.toMap()["id"].toString();
        QVERIFY2(ids.contains(id), qPrintable(QStringLiteral("getAllLists 未包含 %1").arg(id)));

        // 2026-10-22: 删除必须发信号, 否则 QML 端要靠重开页面才回表 (用户报)
        QSignalSpy deleted(m_engine, &EquipmentService::dataChanged);
        QVERIFY(m_engine->deleteList(id).value("ok").toBool());
        QCOMPARE(deleted.count(), 1);
        QVERIFY(m_engine->getList(id).isEmpty());

        // 删不存在的清单不该发信号 (失败路径不刷表)
        deleted.clear();
        QVERIFY(!m_engine->deleteList(id).value("ok").toBool());
        QCOMPARE(deleted.count(), 0);
    }

    // === 偏好记忆 ===
    void test_preferences() {
        const QString firstId = m_engine->getAllItems().first().toMap()["id"].toString();
        // 2026-09-21: 阶段 L3.8 - addPreference/deletePreference 切 Result<bool>
        QVERIFY(m_engine->addPreference(firstId, QStringLiteral("always_skip")).value("ok").toBool());
        const QVariantList prefs = m_engine->getPreferences();
        QCOMPARE(prefs.size(), 1);
        QCOMPARE(prefs.first().toMap()["equipmentId"].toString(), firstId);

        const QString prefId = prefs.first().toMap()["id"].toString();
        QVERIFY(m_engine->deletePreference(prefId).value("ok").toBool());
        QCOMPARE(m_engine->getPreferences().size(), 0);
    }

    void test_add_preference_unknown_item() {
        // EquipmentService::addPreference 只校验 equipmentId 非空 (允许用户为
        //   未来才导入的装备项预留偏好), 不查库. 空字符串仍走 InvalidArgument.
        QVERIFY(!m_engine->addPreference(QString(), "always_skip").value("ok").toBool());
        // 未知 id 现在被接受, 记录到 preferences 里
        QVERIFY(m_engine->addPreference("nonexistent_999", "always_skip").value("ok").toBool());
        m_engine->clearPreferences();
    }

    void test_clear_preferences() {
        const QString firstId = m_engine->getAllItems().first().toMap()["id"].toString();
        m_engine->addPreference(firstId, "always_skip");
        QVERIFY(!m_engine->getPreferences().isEmpty());
        m_engine->clearPreferences();
        QCOMPARE(m_engine->getPreferences().size(), 0);
    }

    // === 强装检查 ===
    void test_start_check() {
        const QString listId = m_engine->generateList("测试", tripParams(3000, 3))["id"].toString();
        QVERIFY(!listId.isEmpty());

        const QVariantMap check = m_engine->startCheck(listId);
        QVERIFY(check.contains("total"));
        QVERIFY(check["total"].toInt() > 0);
        QCOMPARE(check["checked"].toInt(), 0);
    }

    void test_start_check_unknown_list() {
        const QVariantMap check = m_engine->startCheck("list_not_exist");
        QVERIFY(!check["total"].isValid() || check.contains("error"));
    }

    void test_check_item() {
        const QString listId = m_engine->generateList("测试", tripParams(3000, 2))["id"].toString();
        const QVariantMap list = m_engine->getList(listId);
        const QVariantList items = list["critical"].toList();
        QVERIFY(!items.isEmpty());
        const QString equipId = items.first().toMap()["id"].toString();

        // Phase 5: checkItem 返回 Result
        QVERIFY(m_engine->checkItem(listId, equipId, true).value("ok").toBool());
        QVariantMap progress = m_engine->getCheckProgress(listId);
        QCOMPARE(progress["checked"].toInt(), 1);

        // 幂等: 重复勾选同一个 id 不会重复计数
        QVERIFY(m_engine->checkItem(listId, equipId, true).value("ok").toBool());
        QCOMPARE(m_engine->getCheckProgress(listId)["checked"].toInt(), 1);

        // setItemChecked 是 checkItem 的别名 (CategorySection.qml 调用)
        QVERIFY(m_engine->setItemChecked(listId, equipId, false).value("ok").toBool());
        QCOMPARE(m_engine->getCheckProgress(listId)["checked"].toInt(), 0);

        // 勾选状态落库, getList 回显 checked 字段
        QVERIFY(m_engine->checkItem(listId, equipId, true).value("ok").toBool());
        bool echoed = false;
        for (const QVariant& v : m_engine->getList(listId)["critical"].toList()) {
            if (v.toMap()["id"].toString() == equipId) echoed = v.toMap()["checked"].toBool();
        }
        QVERIFY(echoed);
    }

    void test_check_item_unknown_list() {
        QVERIFY(!m_engine->checkItem("list_not_exist", "any", true).value("ok").toBool());
    }

    // === 2026-10-22 P3: 往年天气 (省 × 月 气候常态表) =========================
    // 表里存的是代表站海拔处的常年值, 海拔修正/档位换算全在 climateFor 里做,
    // 所以断言看的是**修正后的读数**, 不是 JSON 原文。
    void test_climate_table_loaded() {
        QCOMPARE(m_engine->climateTotalProvinces(), 34);
        const QStringList names = m_engine->climateProvinceNames();
        QCOMPARE(names.size(), 34);
        QVERIFY(names.contains(QStringLiteral("北京")));
        QVERIFY(names.contains(QStringLiteral("黑龙江")));
        QVERIFY(names.contains(QStringLiteral("西藏")));
    }

    void test_climate_altitude_correction() {
        // 四川锚点是成都平原 (500m), 1 月均温 6℃ / 夜间 1℃ / 7mm。
        // 路线在 4000m: 直减率 -6.5℃/1000m → 均温该掉到 -16.75℃ 左右,
        // 紫外线按 +12%/1000m 上浮, 那点毛毛雨也因此变成雪档。
        const QVariantMap plain = m_engine->climateFor(QStringLiteral("四川"), 1, 500);
        const QVariantMap ridge = m_engine->climateFor(QStringLiteral("四川"), 1, 4000);
        QVERIFY(!plain.isEmpty() && !ridge.isEmpty());

        const double drop = plain["tempAvg"].toDouble() - ridge["tempAvg"].toDouble();
        QVERIFY2(qAbs(drop - 22.75) < 0.2,
                 qPrintable(QStringLiteral("500→4000m 温差 %1, 期望 22.75").arg(drop)));
        QVERIFY2(ridge["tempMin"].toDouble() <= -16.0,
                 qPrintable(QStringLiteral("4000m 夜间 %1℃ 还不够冷").arg(ridge["tempMin"].toDouble())));
        QVERIFY(ridge["uvIndex"].toDouble() > plain["uvIndex"].toDouble());
        QCOMPARE(plain["precipitation"].toInt(), static_cast<int>(Precipitation::Light));
        QCOMPARE(ridge["precipitation"].toInt(), static_cast<int>(Precipitation::SnowLight));
        // 季节按气象月: 1 月是冬
        QCOMPARE(ridge["season"].toInt(), static_cast<int>(Season::Winter));
    }

    void test_climate_slash_province_average() {
        // 跨省路线 "北京/天津" 拆开各算再平均, 不等于任一省的单值
        const QVariantMap bj = m_engine->climateFor(QStringLiteral("北京"), 1, 50);
        const QVariantMap tj = m_engine->climateFor(QStringLiteral("天津"), 1, 50);
        const QVariantMap both = m_engine->climateFor(QStringLiteral("北京 / 天津"), 1, 50);
        QVERIFY(!bj.isEmpty() && !tj.isEmpty() && !both.isEmpty());
        const double mean = (bj["tempAvg"].toDouble() + tj["tempAvg"].toDouble()) / 2.0;
        QVERIFY2(qAbs(both["tempAvg"].toDouble() - mean) < 0.2,
                 qPrintable(QStringLiteral("平均 %1 vs 两省中值 %2")
                                .arg(both["tempAvg"].toDouble()).arg(mean)));
        QCOMPARE(both["climateProvince"].toString(), QStringLiteral("北京/天津"));
    }

    void test_climate_unknown_returns_empty() {
        // 查不到就返回空 map —— 宁可让页面提示"这一带没有往年天气", 也不编一份假天气
        QVERIFY(m_engine->climateFor(QStringLiteral("不存在的省"), 7, 1000).isEmpty());
        QVERIFY(m_engine->climateFor(QString(), 7, 1000).isEmpty());
        QVERIFY(m_engine->climateFor(QStringLiteral("四川"), 0, 1000).isEmpty());
        QVERIFY(m_engine->climateFor(QStringLiteral("四川"), 13, 1000).isEmpty());
        // 部分对上: 只把认得出的省算进去, 来源里也只留那一个
        const QVariantMap partial = m_engine->climateFor(QStringLiteral("四川/不存在的省"), 1, 500);
        QCOMPARE(partial["climateProvince"].toString(), QStringLiteral("四川"));
    }

    // === 2026-11-03 #45: 坐标 → 省 反查 (装备清单的「地点」按当前定位填) ======
    void test_climate_anchor_table_has_usable_lon() {
        // 反查靠 lat+lon 两个数。这份表在 #45 之前**只有 lat** (气候模型的形状锚),
        // `o["lon"].toDouble()` 对缺键静悄悄给 0 —— 于是"最近省"会算到本初子午线上,
        // 而气候表里没有任何一条会报错。所以这里把 34 条的坐标齐全性钉死。
        const QStringList names = m_engine->climateProvinceNames();
        QCOMPARE(names.size(), 34);
        for (const QString& n : names) {
            const QVariantMap st = m_engine->climateStation(n);
            QVERIFY2(!st.isEmpty(), qPrintable(n + QStringLiteral(" 查不到代表站")));
            const double lat = st["lat"].toDouble();
            const double lon = st["lon"].toDouble();
            QVERIFY2(std::isfinite(lat) && std::isfinite(lon),
                     qPrintable(n + QStringLiteral(" 坐标不是有限数")));
            QVERIFY2(lat >= -90.0 && lat <= 90.0, qPrintable(n + QStringLiteral(" 纬度超范围")));
            // 中国没有省的锚点在 0 经线上 (最西的新疆是 87.62) —— lon==0 就是缺键
            QVERIFY2(lon > 70.0 && lon <= 180.0,
                     qPrintable(QStringLiteral("%1 经度 %2 不像中国境内 (缺 lon?)")
                                    .arg(n).arg(lon)));
        }
    }

    void test_nearest_climate_province_by_location() {
        // 期望值不是拍的: 用表里的真锚点按同式 (haversine, R=6371000) 反算过一遍。
        struct Case { double lat; double lon; const char* want; };
        static const Case kCases[] = {
            {24.88, 102.83, "云南"},      // 昆明
            {39.90, 116.40, "北京"},      // 锚点本身, 0 km
            {29.65,  91.14, "西藏"},      // 拉萨
            {43.83,  87.62, "新疆"},      // 乌鲁木齐 (最西)
            {36.65, 117.00, "山东"},      // 济南 —— 真机验收就看这一条
            {45.80, 126.53, "黑龙江"},    // 哈尔滨 (最东北)
            {22.82, 108.37, "广西"},      // 南宁 (南疆界附近, 不误落到海南)
            {41.80, 123.43, "辽宁"},
            {34.34, 108.94, "陕西"},
        };
        for (const Case& c : kCases) {
            const QVariantMap r = m_engine->nearestClimateProvince(c.lat, c.lon);
            const QString got = r["province"].toString();
            QVERIFY2(!r.isEmpty(), qPrintable(QStringLiteral("%1,%2 反查为空")
                                                   .arg(c.lat).arg(c.lon)));
            QVERIFY2(got == QString::fromUtf8(c.want),
                     qPrintable(QStringLiteral("%1,%2 → %3, 期望 %4 (%5 km)")
                                    .arg(c.lat).arg(c.lon).arg(got,
                                                          QString::fromUtf8(c.want),
                                                          QString::number(r["distanceKm"].toDouble()))));
        }
    }

    void test_nearest_climate_province_distance_is_honest() {
        // distanceKm 是给页面提示用的, 必须是"到这个省锚点的距离"而不是恒 0。
        const QVariantMap bj = m_engine->nearestClimateProvince(39.90, 116.40);
        QCOMPARE(bj["distanceKm"].toInt(), 0);
        const QVariantMap lhasa = m_engine->nearestClimateProvince(29.65, 91.14);
        QVERIFY2(lhasa["distanceKm"].toInt() > 100,   // 锚点在 31N, 差 1.35 度 ≈ 150 km
                 qPrintable(QStringLiteral("拉萨→西藏锚点 %1 km, 偏小").arg(lhasa["distanceKm"].toInt())));
        // 锚点坐标一并回显, 页面要能说"按到 31°N 105°E 这一带来推"
        QVERIFY(std::isfinite(lhasa["anchorLat"].toDouble()));
        QVERIFY(std::isfinite(lhasa["anchorLon"].toDouble()));
    }

    void test_nearest_climate_province_rejects_bad_coords() {
        // 一律返回空 map: 页面据此走"没定位 → 手填/提示", 不能拿一个省当默认值糊过去
        QVERIFY(m_engine->nearestClimateProvince(0.0, 0.0).isEmpty());        // 定位没给数
        QVERIFY(m_engine->nearestClimateProvince(91.0, 100.0).isEmpty());     // 纬度超范围
        QVERIFY(m_engine->nearestClimateProvince(-91.0, 100.0).isEmpty());
        QVERIFY(m_engine->nearestClimateProvince(30.0, 181.0).isEmpty());     // 经度超范围
        QVERIFY(m_engine->nearestClimateProvince(30.0, -181.0).isEmpty());
        QVERIFY(m_engine->nearestClimateProvince(qQNaN(), 100.0).isEmpty());
        QVERIFY(m_engine->nearestClimateProvince(30.0, std::numeric_limits<double>::infinity()).isEmpty());
    }

    void test_climate_readout_keys_match_qml() {
        // QML 那两页 (EquipmentPage 的读数条 + RouteGearRecommendPage 的"送进引擎的天气")
        // 是直接按字符串取键的: climateFor 少给一个键, 页面上就是一片空白或 "undefined ℃",
        // 而 qmllint / load_check / ctest 三道都看不见 —— 字符串取键没有编译期约束.
        // 所以把 QML 用到的键在这里逐个钉住, 改 C++ 时漏键会在这里红.
        static const char* kKeys[] = {
            "tempAvg", "tempMin", "windSpeed", "uvIndex", "precipitation", "humidity",
            "diurnalRange", "season", "isRainySeason",
            "windLevel", "uvLevel",
            "climateProvince", "climateMonth", "climateAltitudeM",
            "climatePrecipMm", "climateRefAltitudeM", "climateCorrectC"
        };
        // 除了 climateProvince (字符串) 和 isRainySeason (布尔), 其余全是数字
        static const char* kNumeric[] = {
            "tempAvg", "tempMin", "windSpeed", "uvIndex", "precipitation", "humidity",
            "diurnalRange", "season", "windLevel", "uvLevel", "climateMonth",
            "climateAltitudeM", "climatePrecipMm", "climateRefAltitudeM", "climateCorrectC"
        };
        const QVariantMap c = m_engine->climateFor(QStringLiteral("四川"), 1, 4000);
        QVERIFY(!c.isEmpty());
        for (const char* k : kKeys) {
            QVERIFY2(c.contains(QString::fromLatin1(k)), k);
        }
        for (const char* k : kNumeric) {
            const QString key = QString::fromLatin1(k);
            bool ok = false;
            c.value(key).toDouble(&ok);
            QVERIFY2(ok, qPrintable(key + QStringLiteral(" 不是数字 (页面会渲染成 undefined)")));
        }
        QVERIFY(c.value(QStringLiteral("isRainySeason")).canConvert<bool>());
        QVERIFY(!c.value(QStringLiteral("climateProvince")).toString().isEmpty());

        // 档位与数值必须同源: 页面把 windLevel/uvLevel 直接当档位显示, 又把
        // windSpeed/uvIndex 当数值显示, 两者对不上就是"显示强、发出去是中等".
        // 阈值抄 EquipmentService.h:322-323 的注释 (蒲福 + WHO), 作为独立 oracle.
        auto windBand = [](double ms) {
            return ms < 0.3 ? 0 : ms < 3.4 ? 1 : ms < 8.0 ? 2 : ms < 10.8 ? 3 : 4;
        };
        auto uvBand = [](double uv) {
            return uv < 3.0 ? 0 : uv < 6.0 ? 1 : uv < 8.0 ? 2 : uv < 11.0 ? 3 : 4;
        };
        QCOMPARE(c["windLevel"].toInt(), windBand(c["windSpeed"].toDouble()));
        QCOMPARE(c["uvLevel"].toInt(), uvBand(c["uvIndex"].toDouble()));

        // 修正量与海拔差自洽: 4000 m 相对 500 m 的代表站, 应往下修 ~22.75 ℃
        QVERIFY2(c["climateRefAltitudeM"].toInt() == 500,
                 "四川代表站海拔应为 500 m");
        QVERIFY2(qAbs(c["climateCorrectC"].toDouble() - (-22.8)) < 0.15,
                 qPrintable(QStringLiteral("修正量异常: ")
                            + QString::number(c["climateCorrectC"].toDouble())));
        // 月份原样回显, 页面 SRC 行直接用它
        QCOMPARE(c["climateMonth"].toInt(), 1);
        QCOMPARE(c["climateAltitudeM"].toInt(), 4000);
    }

    void test_climate_feeds_generate_list() {
        auto bucketOf = [](const QVariantMap& list, const QString& itemId) -> QString {
            for (const QString& b : {QStringLiteral("critical"), QStringLiteral("important"),
                                     QStringLiteral("recommended")})
                for (const QVariant& v : list[b].toList())
                    if (v.toMap()["id"].toString() == itemId) return b;
            return QString();
        };
        // 用往年天气生成清单: 表单只剩海拔/天数/难度, 天气由省 × 月推出来。
        // (QVERIFY 不能在返回值的 lambda 里用, 所以这里只组装参数, 断言留在用例体内)
        auto withClimate = [this](const QString& province, int month, int altitudeMax, int days) {
            QVariantMap p = tripParams(altitudeMax, days);
            const QVariantMap c = m_engine->climateFor(province, month, altitudeMax);
            for (const QString& k : {QStringLiteral("tempAvg"), QStringLiteral("tempMin"),
                                     QStringLiteral("windSpeed"), QStringLiteral("uvIndex"),
                                     QStringLiteral("precipitation"), QStringLiteral("humidity"),
                                     QStringLiteral("diurnalRange"), QStringLiteral("season"),
                                     QStringLiteral("isRainySeason")})
                p[k] = c[k];
            return p;
        };
        auto generate = [this](const QVariantMap& p) {
            return m_engine->getList(m_engine->generateList(QStringLiteral("往年天气"), p)["id"].toString());
        };

        // 黑龙江 1 月: 夜温 -24.5℃ 级, 极寒羽绒必须进必带
        const QVariantMap harsh = generate(withClimate(QStringLiteral("黑龙江"), 1, 300, 2));
        QVERIFY2(!bucketOf(harsh, "expedition_down").isEmpty(),
                 QStringLiteral("黑龙江1月没出极地羽绒").toUtf8().constData());
        // 四川 4000m 1 月: 成都平原的毛毛雨修正到海拔后是轻雪, 冰爪要上场
        const QVariantMap icy = generate(withClimate(QStringLiteral("四川"), 1, 4000, 2));
        QVERIFY2(!bucketOf(icy, "crampons").isEmpty(),
                 QStringLiteral("四川4000m1月没出冰爪").toUtf8().constData());
        // 海南 7 月: 湿热多雨 —— 雨具在场, 羽绒一律不上榜
        const QVariantMap tropic = generate(withClimate(QStringLiteral("海南"), 7, 200, 1));
        QVERIFY2(bucketOf(tropic, "down_jacket").isEmpty()
                     && bucketOf(tropic, "expedition_down").isEmpty(),
                 QStringLiteral("海南7月误出羽绒").toUtf8().constData());
        QVERIFY2(!bucketOf(tropic, "rain_jacket").isEmpty(),
                 QStringLiteral("海南7月没出雨具").toUtf8().constData());
        // 同一条引擎, 换个地点月份, 上包的重量就该跟着气候走
        QVERIFY2(tropic["totalWeightG"].toInt() < harsh["totalWeightG"].toInt(),
                 qPrintable(QStringLiteral("海南7月 %1 g 不该比黑龙江1月 %2 g 还重")
                                .arg(tropic["totalWeightG"].toInt())
                                .arg(harsh["totalWeightG"].toInt())));
    }
};

QTEST_MAIN(TestEquipmentService)
#include "test_equipment_service.moc"
