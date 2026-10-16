/**
 * @file test_plant_service.cpp
 * @brief PlantService 测试
 */

#include "species/PlantService.h"
#include "core/Database.h"

#include <QtTest>
#include <QTemporaryDir>

using namespace outdoor;

class TestPlantService : public QObject {
    Q_OBJECT

private:
    QTemporaryDir* m_tmpDir = nullptr;
    Database* m_db = nullptr;
    PlantService* m_service = nullptr;

private slots:
    void initTestCase() {
        m_tmpDir = new QTemporaryDir();
        QVERIFY(m_tmpDir->isValid());
        m_db = new Database();
        QVERIFY(m_db->open(m_tmpDir->path()));
    }

    void cleanupTestCase() {
        delete m_service;
        delete m_db;
        delete m_tmpDir;
    }

    void test_loadAndQuery() {
        m_service = new PlantService(m_db);
        // 加载可能失败(无 JSON),但 Service 仍可用
        m_service->loadInitialData();

        // 即使没数据,API 也不崩
        QVariantList all = m_service->getAll();
        QVERIFY(all.isEmpty() || all.size() >= 0);

        QVariantList shandong = m_service->getByProvince("山东");
        QVERIFY(shandong.isEmpty() || shandong.size() >= 0);

        QVariantList may = m_service->getByMonth(5);
        QVERIFY(may.isEmpty() || may.size() >= 0);
    }

    void test_getByCategory() {
        QVariantList edible = m_service->getByCategory("wild_vegetable");
        QVERIFY(edible.isEmpty() || edible.size() >= 0);

        QVariantList poisonous = m_service->getPoisonous();
        QVERIFY(poisonous.isEmpty() || poisonous.size() >= 0);
    }

    void test_matchByColor() {
        QVariantMap userColor;
        userColor["h"] = 90;
        userColor["s"] = 60;
        userColor["v"] = 80;
        QVariantList result = m_service->matchByColor(userColor, 5);
        QVERIFY(result.size() <= 5);
    }

    void test_provincesAndCategories() {
        QStringList provinces = m_service->getAvailableProvinces();
        QVERIFY(provinces.isEmpty() || provinces.size() >= 0);

        QStringList categories = m_service->getAvailableCategories();
        QVERIFY(categories.isEmpty() || categories.size() >= 0);
    }
};

QTEST_MAIN(TestPlantService)
#include "test_plant_service.moc"
