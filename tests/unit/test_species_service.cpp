/**
 * @file test_species_service.cpp
 * @brief 危险物种服务单元测试
 */

#include <QtTest>
#include <QTemporaryDir>

#include "src/species/SpeciesService.h"
#include "src/core/Database.h"

using namespace outdoor;

class TestSpeciesService : public QObject {
    Q_OBJECT

private:
    SpeciesService* m_service = nullptr;
    Database* m_db = nullptr;
    QTemporaryDir m_tmpDir;

private slots:
    void init() {
        QVERIFY(m_tmpDir.isValid());
        m_db = new Database();
        QVERIFY(m_db->open(m_tmpDir.path()));
        m_db->migrate();
        m_service = new SpeciesService(m_db);
        QVERIFY(m_service->loadInitialData());
    }

    void cleanup() {
        delete m_service;
        delete m_db;
    }

    // === 数据加载 ===
    void test_load_data() {
        QVERIFY(m_service->totalCount() > 0);
        qInfo() << "Loaded species:" << m_service->totalCount();
    }

    // === 查询 ===
    void test_get_by_id() {
        QVariantList all = m_service->getAll();
        QVERIFY(!all.isEmpty());
        QString firstId = all.first().toMap()["id"].toString();
        QVariantMap s = m_service->getById(firstId);
        QVERIFY(!s.isEmpty());
        // 字段名与 SpeciesService::getById 的输出保持一致 (commonName, 不是 name)
        QVERIFY(s["commonName"].toString().length() > 0);
    }

    void test_get_by_id_nonexistent() {
        QVariantMap s = m_service->getById("nonexistent_species_999");
        QVERIFY(s.isEmpty());
    }

    // === 按危险等级 ===
    void test_dangerous_level5() {
        QVariantList l5 = m_service->getDangerous(5);
        QVERIFY(l5.size() > 0);
        for (const auto& s : l5) {
            int level = s.toMap()["dangerLevel"].toInt();
            QVERIFY(level >= 5);
        }
    }

    void test_dangerous_level4() {
        QVariantList l4 = m_service->getDangerous(4);
        QVERIFY(l4.size() > 0);
    }

    void test_dangerous_count() {
        // dangerLevel >= 3 的记录数必须与 dangerousCount() 一致
        QCOMPARE(m_service->getDangerous(3).size(), m_service->dangerousCount());
    }

    // === 按类别 ===
    void test_by_category_snake() {
        QVariantList snakes = m_service->getByCategory(SpeciesService::Category::Snake);
        QVERIFY(snakes.size() > 0);
        // getByCategory 的精简 map 不带 category 字段, 需回查 getById 校验归属
        for (const auto& s : snakes) {
            const QString id = s.toMap()["id"].toString();
            QCOMPARE(m_service->getById(id)["category"].toInt(),
                     static_cast<int>(SpeciesService::Category::Snake));
        }
    }

    void test_by_category_mushroom() {
        QVariantList mushrooms = m_service->getByCategory(SpeciesService::Category::Mushroom);
        QVERIFY(mushrooms.size() > 0);
    }

    void test_by_categories_cover_all_records() {
        // 五个类别之和必须等于总数, 否则说明有 category 越界的脏数据
        int sum = 0;
        for (SpeciesService::Category c : {SpeciesService::Category::Snake,
                                           SpeciesService::Category::Mushroom,
                                           SpeciesService::Category::Insect,
                                           SpeciesService::Category::Plant,
                                           SpeciesService::Category::Animal}) {
            sum += m_service->getByCategory(c).size();
        }
        QCOMPARE(sum, m_service->totalCount());
    }

    // === 按省份 ===
    void test_for_region() {
        QVariantList yunnan = m_service->getForRegion("云南");
        QVERIFY(yunnan.size() > 0);
    }

    void test_for_region_empty() {
        QVariantList r = m_service->getForRegion("不存在的省份");
        QCOMPARE(r.size(), 0);
    }

    // === 急救联动 ===
    void test_get_first_aid_id() {
        bool linked = false;
        QVariantList all = m_service->getAll();
        for (const auto& s : all) {
            QString id = s.toMap()["id"].toString();
            QString faId = m_service->getFirstAidId(id);
            if (!faId.isEmpty()) {
                QVERIFY(faId.startsWith("firstaid_"));
                linked = true;
            }
        }
        QVERIFY(linked);  // 至少有一条物种关联到急救条目
        QVERIFY(m_service->getFirstAidId("nonexistent_species_999").isEmpty());
    }

    // === 搜索 ===
    void test_search_keyword() {
        QVariantList results = m_service->search("蛇");
        QVERIFY(results.size() > 0);
        for (const auto& r : results) {
            QVERIFY(!r.toMap()["id"].toString().isEmpty());
        }
    }

    void test_search_empty() {
        // search() 对空关键词直接返回空列表 (不做全量返回), 与 FirstAidService::search 一致
        QCOMPARE(m_service->search("").size(), 0);
    }
};

QTEST_MAIN(TestSpeciesService)
#include "test_species_service.moc"
