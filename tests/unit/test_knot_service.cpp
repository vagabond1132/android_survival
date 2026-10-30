/**
 * @file test_knot_service.cpp
 * @brief 绳结服务单元测试
 */

#include <QtTest>
#include <QTemporaryDir>

#include "src/knots/KnotService.h"
#include "src/core/Database.h"

using namespace outdoor;

class TestKnotService : public QObject {
    Q_OBJECT

private:
    KnotService* m_service = nullptr;
    Database* m_db = nullptr;
    QTemporaryDir m_tmpDir;

private slots:
    void init() {
        // 2026-10-16 修: QTemporaryDir 成员只在测试对象构造时建一次, 每个用例又复用
        // 同一个 db 文件 → 上一个用例 learn 的绳结会漏进下一个用例, isLearned 判断失真.
        m_tmpDir = QTemporaryDir();
        QVERIFY(m_tmpDir.isValid());
        m_db = new Database();
        QVERIFY(m_db->open(m_tmpDir.path()));
        m_db->migrate();
        m_service = new KnotService(m_db);
        QVERIFY(m_service->loadInitialData());
    }

    void cleanup() {
        delete m_service;
        delete m_db;
    }

    void test_loadCount() {  // 2026-10-22: 原名 test_load_data — QTest 把 *_data 当数据函数, 没有同名 _test 就整条静默跳过
        QVERIFY(m_service->totalCount() > 0);
        qInfo() << "Loaded knots:" << m_service->totalCount();
    }

    void test_get_all() {
        QVariantList all = m_service->getAll();
        QVERIFY(all.size() > 0);
    }

    void test_get_by_id() {
        QVariantList all = m_service->getAll();
        QString firstId = all.first().toMap()["id"].toString();
        QVariantMap k = m_service->getById(firstId);
        QVERIFY(!k.isEmpty());
    }

    void test_get_by_id_nonexistent() {
        QVariantMap k = m_service->getById("nonexistent_knot_999");
        QVERIFY(k.isEmpty());
    }

    void test_by_category() {
        QVariantList basic = m_service->getByCategory("基础");
        QVERIFY(basic.size() > 0);
    }

    void test_by_difficulty() {
        QVariantList easy = m_service->getByDifficulty(1);
        QVERIFY(easy.size() > 0);
    }

    void test_learning_path() {
        // 阶段 L3.x: getLearningPath 返回 Result, 路径在 .value 里
        const QVariantMap r = m_service->getLearningPath();
        QVERIFY2(r.value("ok").toBool(), qPrintable(r.value("error").toString()));
        const QVariantList path = r.value("value").toList();
        QVERIFY(path.size() > 0);
        // 学习路径应按难度递进 (同难度内维持 byOrder 的教学顺序)
        for (int i = 0; i < path.size() - 1; ++i) {
            int cur = path[i].toMap()["difficulty"].toInt();
            int nxt = path[i + 1].toMap()["difficulty"].toInt();
            QVERIFY2(cur <= nxt, qPrintable(QStringLiteral("index %1: %2 > %3").arg(i).arg(cur).arg(nxt)));
        }
    }

    // 学习进度
    void test_mark_learned() {
        QVariantList all = m_service->getAll();
        QString firstId = all.first().toMap()["id"].toString();
        // markLearned 返回 Result<bool>, ok 才是成功标志
        QVERIFY(m_service->markLearned(firstId).value("ok").toBool());
        QVERIFY(m_service->isLearned(firstId));
        QCOMPARE(m_service->learnedCount(), 1);
    }

    void test_mark_learned_unknown_id() {
        const QVariantMap r = m_service->markLearned("nonexistent_knot_999");
        QVERIFY(!r.value("ok").toBool());
    }

    void test_is_learned_new() {
        QVariantList all = m_service->getAll();
        QString firstId = all.first().toMap()["id"].toString();
        // init() 每个用例都重建 service + 临时库, 这里验证初始进度为空
        QVERIFY(!m_service->isLearned(firstId));
    }

    void test_learned_count() {
        int n = m_service->learnedCount();
        QVERIFY(n >= 0);
    }

    void test_reset_progress() {
        m_service->resetProgress();
        QCOMPARE(m_service->learnedCount(), 0);
    }

    void test_get_learned_list() {
        QVariantList all = m_service->getAll();
        for (const auto& k : all) {
            m_service->markLearned(k.toMap()["id"].toString());
        }
        QVariantList learned = m_service->getLearnedList();
        QCOMPARE(learned.size(), m_service->totalCount());
    }
};

QTEST_MAIN(TestKnotService)
#include "test_knot_service.moc"
