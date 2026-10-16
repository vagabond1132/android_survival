/**
 * @file test_insect_service.cpp
 * @brief InsectService 测试
 */

#include "species/InsectService.h"
#include "core/Database.h"

#include <QtTest>
#include <QTemporaryDir>

using namespace outdoor;

class TestInsectService : public QObject {
    Q_OBJECT

private:
    QTemporaryDir* m_tmpDir = nullptr;
    Database* m_db = nullptr;
    InsectService* m_service = nullptr;

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
        m_service = new InsectService(m_db);
        m_service->loadInitialData();

        QVariantList all = m_service->getAll();
        QVERIFY(all.size() >= 0);
    }

    void test_byProvince() {
        QVariantList list = m_service->getByProvince("山东");
        QVERIFY(list.size() >= 0);
    }

    void test_dangerous() {
        QVariantList list = m_service->getDangerous(3);
        QVERIFY(list.size() >= 0);
    }
};

QTEST_MAIN(TestInsectService)
#include "test_insect_service.moc"
