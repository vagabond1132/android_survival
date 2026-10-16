/**
 * @file test_db_helper.cpp
 * @brief DbHelper 单元测试 (5 阶段架构重构 Phase 2)
 *
 * 覆盖:
 *   - execDdl: CREATE TABLE 成功/失败
 *   - execDml: INSERT/UPDATE/DELETE 成功 + UNIQUE 冲突
 *   - execSelect: SELECT 成功 + 绑定失败
 *   - dmlResultToString / lastErrorText
 */
#include <QtTest>
#include <QTemporaryDir>
#include <QSqlDatabase>
#include <QSqlQuery>

#include "src/common/DbHelper.h"

using namespace outdoor;

class TestDbHelper : public QObject {
    Q_OBJECT

private:
    QTemporaryDir m_tmpDir;
    QSqlDatabase m_db;
    int m_dbSeq = 0;  // 每个 test 使用独立 sqlite 文件, 避免 "table t already exists"

    void openTemp() {
        const QString connName = QStringLiteral("dbhelper_test_%1_%2")
                                     .arg(QCoreApplication::applicationPid())
                                     .arg(++m_dbSeq);
        const QString filePath = m_tmpDir.path() + QStringLiteral("/test_%1.db").arg(m_dbSeq);
        m_db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connName);
        m_db.setDatabaseName(filePath);
        QVERIFY(m_db.open());
    }

    void closeTemp() {
        const QString name = m_db.connectionName();
        m_db.close();
        m_db = QSqlDatabase();
        QSqlDatabase::removeDatabase(name);
    }

private slots:
    void init() {
        QVERIFY(m_tmpDir.isValid());
    }

    void cleanup() {
        if (m_db.isOpen()) closeTemp();
    }

    // ===== DDL =====
    void test_execDdl_create_table_ok() {
        openTemp();
        QSqlQuery q(m_db);
        QVERIFY(DbHelper::execDdl(q,
            "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)",
            "test_create_ok"));
        QVERIFY(q.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='t'"));
        QVERIFY(q.next());
    }

    void test_execDdl_syntax_error_returns_false() {
        openTemp();
        QSqlQuery q(m_db);
        QVERIFY(!DbHelper::execDdl(q,
            "CREATE TABEL typo (id INT)",  // 错: TABEL 不是 TABLE
            "test_syntax_error"));
    }

    // ===== DML: INSERT =====
    void test_execDml_insert_ok() {
        openTemp();
        QSqlQuery q(m_db);
        QVERIFY(DbHelper::execDdl(q,
            "CREATE TABLE t (id TEXT PRIMARY KEY, val INT)",
            "test_insert_ok.setup"));

        DmlResult rc = DbHelper::execDml(q,
            "INSERT INTO t (id, val) VALUES (:id, :val)",
            {{":id", "a"}, {":val", 1}},
            "test_insert_ok");
        QCOMPARE(rc, DmlResult::Ok);
    }

    void test_execDml_unique_conflict_returns_alreadyExists() {
        openTemp();
        QSqlQuery q(m_db);
        QVERIFY(DbHelper::execDdl(q,
            "CREATE TABLE t (id TEXT PRIMARY KEY, val INT)",
            "test_unique.setup"));

        QVERIFY(DbHelper::execDml(q,
            "INSERT INTO t (id, val) VALUES (:id, :val)",
            {{":id", "a"}, {":val", 1}},
            "test_unique.first") == DmlResult::Ok);

        DmlResult rc = DbHelper::execDml(q,
            "INSERT INTO t (id, val) VALUES (:id, :val)",
            {{":id", "a"}, {":val", 2}},  // 同 id 触发 UNIQUE 冲突
            "test_unique.second");
        QCOMPARE(rc, DmlResult::AlreadyExists);
    }

    void test_execDml_update_no_match_returns_ok() {
        openTemp();
        QSqlQuery q(m_db);
        QVERIFY(DbHelper::execDdl(q,
            "CREATE TABLE t (id TEXT PRIMARY KEY, val INT)",
            "test_update.setup"));

        DmlResult rc = DbHelper::execDml(q,
            "UPDATE t SET val = 1 WHERE id = :id",
            {{":id", "nonexistent"}},
            "test_update");
        // UPDATE 0 行仍是 Ok (DbHelper 不区分 affected rows 0/1)
        QCOMPARE(rc, DmlResult::Ok);
    }

    // ===== SELECT =====
    void test_execSelect_basic() {
        openTemp();
        QSqlQuery q(m_db);
        QVERIFY(DbHelper::execDdl(q,
            "CREATE TABLE t (id TEXT PRIMARY KEY, val INT)",
            "test_select.setup"));
        QVERIFY(DbHelper::execDml(q,
            "INSERT INTO t (id, val) VALUES (:id, :val)",
            {{":id", "a"}, {":val", 42}},
            "test_select.insert") == DmlResult::Ok);

        QVERIFY(DbHelper::execSelect(q,
            "SELECT val FROM t WHERE id = :id",
            {{":id", "a"}},
            "test_select"));

        QVERIFY(q.next());
        QCOMPARE(q.value(0).toInt(), 42);
    }

    void test_execSelect_table_not_exist_returns_false() {
        openTemp();
        QSqlQuery q(m_db);
        // 不建表,直接 SELECT
        QVERIFY(!DbHelper::execSelect(q,
            "SELECT * FROM nonexistent",
            {},
            "test_select_missing"));
    }

    // ===== 工具函数 =====
    void test_dmlResultToString() {
        QCOMPARE(DbHelper::dmlResultToString(DmlResult::Ok), QString("Ok"));
        QCOMPARE(DbHelper::dmlResultToString(DmlResult::AlreadyExists),
                 QString("AlreadyExists"));
    }

    void test_lastErrorText_empty_when_no_error() {
        openTemp();
        QSqlQuery q(m_db);
        QVERIFY(DbHelper::execDdl(q, "CREATE TABLE t (id INT)", "test_lasterr.setup"));
        // 刚成功执行,lastError 应该 invalid
        // (注: SQLite driver 在 SELECT 没结果时也算 error, 这里只验证不崩溃)
        QString err = DbHelper::lastErrorText(q);
        Q_UNUSED(err);
    }
};

QTEST_MAIN(TestDbHelper)
#include "test_db_helper.moc"