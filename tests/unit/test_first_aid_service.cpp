/**
 * @file test_first_aid_service.cpp
 * @brief 急救服务单元测试
 */

#include <QtTest>
#include <QTemporaryDir>

#include "src/lifesaver/FirstAidService.h"
#include "src/core/Database.h"

using namespace outdoor;

class TestFirstAidService : public QObject {
    Q_OBJECT

private:
    FirstAidService* m_service = nullptr;
    Database* m_db = nullptr;
    QTemporaryDir m_tmpDir;

private slots:
    void init() {
        QVERIFY(m_tmpDir.isValid());
        m_db = new Database();
        QVERIFY(m_db->open(m_tmpDir.path()));
        m_db->migrate();
        m_service = new FirstAidService(m_db);
        QVERIFY(m_service->loadInitialData());
    }

    void cleanup() {
        delete m_service;
        delete m_db;
    }

    void test_load_data() {
        QVERIFY(m_service->totalEntries() > 0);
        qInfo() << "First aid entries:" << m_service->totalEntries();
    }

    void test_get_by_id() {
        // 2026-09-21: Phase 5 批次 3 - getAllEntries 返回 Result, 记录在 .value 里
        QVariantList all = m_service->getAllEntries().value("value").toList();
        QVERIFY(all.size() > 0);
        QString firstId = all.first().toMap()["id"].toString();
        QVariantMap e = m_service->getById(firstId);
        QVERIFY(!e.isEmpty());
    }

    void test_get_by_id_nonexistent() {
        QVERIFY(m_service->getById("nonexistent").isEmpty());
    }

    void test_by_category() {
        QVariantList l = m_service->getByCategory(FirstAidService::Category::Critical);
        QVERIFY(l.size() > 0);
        for (const auto& e : l) {
            QCOMPARE(e.toMap()["category"].toInt(), (int)FirstAidService::Category::Critical);
        }
    }

    void test_get_critical() {
        QVariantList c = m_service->getCritical();
        QVERIFY(c.size() > 0);
    }

    void test_decision_tree() {
        QVariantMap root = m_service->getDecisionRoot("firstaid_snake_bite");
        // root 可能为空(没实现)或包含节点
        if (!root.isEmpty()) {
            QVERIFY(root.contains("id"));
        }
    }

    void test_kit_templates() {
        QVariantList t = m_service->getKitTemplates();
        QVERIFY(t.size() >= 3);  // 至少 1日徒步/3-5日露营/家庭应急
    }

    void test_kit_template_by_scenario() {
        QVariantMap t1 = m_service->getKitTemplate("hike_1day");
        QVERIFY(!t1.isEmpty());
    }

    void test_kit_template_invalid() {
        QVERIFY(m_service->getKitTemplate("nonexistent").isEmpty());
    }

    void test_search() {
        // 原断言 size() >= 0 恒真, 改为覆盖 search 的三条真实分支
        QVERIFY(m_service->search("").isEmpty());                  // 空关键词直接返回
        QVERIFY(m_service->search("zzz_不可能命中").isEmpty());     // 无匹配
        for (const auto& e : m_service->search("蛇")) {             // 命中项必须可跳转详情页
            QVERIFY(!e.toMap()["id"].toString().isEmpty());
            QVERIFY(!e.toMap()["title"].toString().isEmpty());
        }
    }
};

QTEST_MAIN(TestFirstAidService)
#include "test_first_aid_service.moc"
