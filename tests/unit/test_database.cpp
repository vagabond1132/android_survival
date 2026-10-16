/**
 * @file test_database.cpp
 * @brief 数据库迁移+表结构测试
 */

#include <QtTest>
#include <QTemporaryDir>
#include <QSqlQuery>

#include "src/core/Database.h"

using namespace outdoor;

class TestDatabase : public QObject {
    Q_OBJECT

private:
    Database* m_db = nullptr;
    QTemporaryDir m_tmpDir;

private slots:
    void init() {
        QVERIFY(m_tmpDir.isValid());
        m_db = new Database();
    }

    void cleanup() {
        delete m_db;
    }

    // === 打开/关闭 ===
    void test_open_close() {
        QVERIFY(m_db->open(m_tmpDir.path()));
        QVERIFY(m_db->isOpen(Database::Name::User));
        QVERIFY(m_db->isOpen(Database::Name::Settings));
        QVERIFY(m_db->isOpen(Database::Name::Species));
        QVERIFY(m_db->isOpen(Database::Name::FirstAid));
        QVERIFY(m_db->isOpen(Database::Name::Survival));
        QVERIFY(m_db->isOpen(Database::Name::Routes));
    }

    // === 关键 bug 验证:migrate() 创建真实表 ===
    void test_migrate_creates_real_tables() {
        QVERIFY(m_db->open(m_tmpDir.path()));
        QVERIFY(m_db->migrate());

        // 验证 User 库的 emergency_contacts 表存在
        QSqlDatabase userDb = m_db->get(Database::Name::User);
        QVERIFY(userDb.isOpen());
        QSqlQuery q(userDb);
        QVERIFY(q.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='emergency_contacts'"));
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toString(), QString("emergency_contacts"));

        // 验证 User 库 route_favorites
        QVERIFY(q.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='route_favorites'"));
        QVERIFY(q.next());

        // 验证 User 库 equipment_lists
        QVERIFY(q.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='equipment_lists'"));
        QVERIFY(q.next());

        // 验证 Settings 库的 app_settings
        QSqlDatabase setDb = m_db->get(Database::Name::Settings);
        QSqlQuery q2(setDb);
        QVERIFY(q2.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='app_settings'"));
        QVERIFY(q2.next());

        // 验证 track_records
        QVERIFY(q2.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='track_records'"));
        QVERIFY(q2.next());

        // 验证 recognition_history
        QVERIFY(q2.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='recognition_history'"));
        QVERIFY(q2.next());
    }

    // === 表可读写 ===
    void test_emergency_contacts_writeable() {
        QVERIFY(m_db->open(m_tmpDir.path()));
        QVERIFY(m_db->migrate());

        QSqlDatabase userDb = m_db->get(Database::Name::User);
        QSqlQuery q(userDb);
        QVERIFY(q.exec("INSERT INTO emergency_contacts (name, phone, relation, is_primary) "
                       "VALUES ('张三', '13800001111', '父亲', 1)"));
        QVERIFY(q.exec("SELECT name, phone FROM emergency_contacts WHERE name='张三'"));
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toString(), QString("张三"));
        QCOMPARE(q.value(1).toString(), QString("13800001111"));
    }

    // === 重复 migrate 不报错 ===
    void test_migrate_idempotent() {
        QVERIFY(m_db->open(m_tmpDir.path()));
        QVERIFY(m_db->migrate());
        // CREATE TABLE IF NOT EXISTS 应保证第二次也成功
        QVERIFY(m_db->migrate());
        QVERIFY(m_db->migrate());
    }

    // === 跨数据库隔离 ===
    void test_database_isolation() {
        QVERIFY(m_db->open(m_tmpDir.path()));
        QVERIFY(m_db->migrate());

        // 在 User 库建表
        QSqlDatabase userDb = m_db->get(Database::Name::User);
        QSqlQuery q(userDb);
        QVERIFY(q.exec("CREATE TABLE test_user (id INTEGER)"));

        // Settings 库不应有 test_user
        QSqlDatabase setDb = m_db->get(Database::Name::Settings);
        QSqlQuery q2(setDb);
        QVERIFY(q2.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='test_user'"));
        QVERIFY(!q2.next());
    }
};

QTEST_MAIN(TestDatabase)
#include "test_database.moc"
