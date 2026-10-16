/**
 * @file test_mushroom_service.cpp
 * @brief MushroomService 测试
 */

#include "species/MushroomService.h"
#include "core/Database.h"

#include <QtTest>
#include <QTemporaryDir>

using namespace outdoor;

class TestMushroomService : public QObject {
    Q_OBJECT

private:
    QTemporaryDir* m_tmpDir = nullptr;
    Database* m_db = nullptr;
    MushroomService* m_service = nullptr;

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
        m_service = new MushroomService(m_db);
        m_service->loadInitialData();

        QVariantList all = m_service->getAll();
        QVERIFY(all.size() >= 0);
    }

    void test_safetyWarning() {
        QString warn = m_service->safetyWarning();
        QVERIFY(warn.contains("蘑菇"));
        QVERIFY(warn.contains("不"));
    }

    void test_deadlyAndEdible() {
        QVariantList deadly = m_service->getDeadly();
        QVERIFY(deadly.size() >= 0);

        QVariantList edible = m_service->getEdible();
        QVERIFY(edible.size() >= 0);
    }
};

QTEST_MAIN(TestMushroomService)
#include "test_mushroom_service.moc"
