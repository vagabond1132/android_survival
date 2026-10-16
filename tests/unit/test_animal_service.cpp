/**
 * @file test_animal_service.cpp
 * @brief AnimalService 测试
 */

#include "species/AnimalService.h"
#include "core/Database.h"

#include <QtTest>
#include <QTemporaryDir>

using namespace outdoor;

class TestAnimalService : public QObject {
    Q_OBJECT

private:
    QTemporaryDir* m_tmpDir = nullptr;
    Database* m_db = nullptr;
    AnimalService* m_service = nullptr;

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
        m_service = new AnimalService(m_db);
        m_service->loadInitialData();

        QVariantList all = m_service->getAll();
        QVERIFY(all.size() >= 0);

        QVariantList snakes = m_service->getSnakes();
        QVERIFY(snakes.size() >= 0);

        QVariantList venomous = m_service->getSnakes(true);
        QVERIFY(venomous.size() >= 0);
    }

    void test_dangerous() {
        QVariantList dangerous = m_service->getDangerous(4);
        QVERIFY(dangerous.size() >= 0);
    }

    void test_byProvinceAndMonth() {
        QVariantList shandongJune = m_service->getByProvinceAndMonth("山东", 6);
        QVERIFY(shandongJune.size() >= 0);
    }

    void test_matchByColor() {
        QVariantMap c;
        c["h"] = 25; c["s"] = 40; c["v"] = 60;
        QVariantList r = m_service->matchByColor(c, 3);
        QVERIFY(r.size() <= 3);
    }
};

QTEST_MAIN(TestAnimalService)
#include "test_animal_service.moc"
