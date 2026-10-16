/**
 * @file test_equipment_service.cpp
 * @brief 装备服务单元测试 (2026-09-21: 阶段 I-3 EquipmentEngine → EquipmentService 改名)
 *
 * 2026-10-16: 本套件此前从未编译通过, 按 EquipmentService.h 的真实 API 重写:
 *   - 构造函数是 EquipmentService(QObject*), 不吃 Database; 初始化叫 initialize() 不叫 loadInitialData()
 *   - 海拔枚举是 EquipmentAltitudeLevel (L0-L6, 7 段), 与 MapService::AltitudeLevel (L0-L4) 不同名同义易混
 *   - generateList(name, QVariantMap) 返回 {id, critical/important/recommended/optional}, 没有 "items"
 *   - startCheck/getCheckProgress 返回 {listId, total, checked, progress}, 没有 "totalItems"
 */

#include <QtTest>
#include <QCoreApplication>
#include <QTemporaryDir>

#include "src/equipment/EquipmentService.h"

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
            QVERIFY(!m_engine->getAltitudeLevelColor(lvl).isEmpty());
        }
    }

    void test_altitude_segment_has_range() {
        const QJsonObject seg = EquipmentService::getAltitudeSegment(EquipmentAltitudeLevel::L3);
        QVERIFY(!seg.isEmpty());
    }

    // === 装备项 ===
    void test_get_all_items() {
        const QVariantList items = m_engine->getAllItems();
        // equipment_base.json 有 43 条
        QVERIFY2(items.size() >= 43, qPrintable(QStringLiteral("装备库 %1 条").arg(items.size())));
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
        // totalWeightG = sum of all items 无论 altitude 都一样 (兜底规则把 43 项都塞进桶),
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

    void test_generate_list_persisted_and_deletable() {
        const QString id = m_engine->generateList("待删除", tripParams(800, 1))["id"].toString();
        QVERIFY(!id.isEmpty());
        const QVariantMap all = m_engine->getAllLists();
        QVERIFY(all.value("ok").toBool());
        QStringList ids;
        for (const QVariant& v : all.value("value").toList()) ids << v.toMap()["id"].toString();
        QVERIFY2(ids.contains(id), qPrintable(QStringLiteral("getAllLists 未包含 %1").arg(id)));

        QVERIFY(m_engine->deleteList(id).value("ok").toBool());
        QVERIFY(m_engine->getList(id).isEmpty());
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
};

QTEST_MAIN(TestEquipmentService)
#include "test_equipment_service.moc"
