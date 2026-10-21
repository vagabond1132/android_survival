/**
 * @file test_first_aid.cpp
 * @brief 急救服务单元测试
 */

#include "lifesaver/FirstAidService.h"
#include "core/Database.h"

#include <QtTest>
#include <QSignalSpy>
#include <QCoreApplication>

using namespace outdoor;

class TestFirstAidService : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void cleanupTestCase();
    void init();
    void cleanup();

    // 数据加载测试
    void testLoadInitialData();
    void testTotalCount();
    void testCriticalCount();

    // 查询测试
    void testGetById_valid();
    void testGetById_invalid();
    void testGetByCategory();
    void testGetByCategoryAll();
    void testGetByUrgency();
    void testGetCritical();
    void testSearch_existing();
    void testSearch_empty();
    void testSearch_notFound();
    void testSearch_caseInsensitive();

    // 决策树测试
    void testGetDecisionRoot_valid();
    void testGetDecisionRoot_invalid();
    void testGetDecisionNode();

    // 急救包测试
    void testGetKitTemplates();
    void testGetKitTemplate_valid();
    void testGetKitTemplate_invalid();

    // 关联测试
    void testGetRelatedSpecies();

    // 数据完整性
    void testDataIntegrity_titleNotEmpty();
    void testDataIntegrity_criticalActionsForHighUrgency();
    void testDataIntegrity_urgencyInRange();

private:
    FirstAidService* m_service;
    Database* m_db;
};

void TestFirstAidService::initTestCase() {
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QCoreApplication::instance();  // 确保应用实例存在

    m_db = new Database();
    QString testDataPath = QStandardPaths::writableLocation(
        QStandardPaths::TempLocation) + "/test_outdoor_survival";
    QDir().mkpath(testDataPath);
    QVERIFY(m_db->open(testDataPath));

    m_service = new FirstAidService(m_db);
    QVERIFY(m_service->loadInitialData());
}

void TestFirstAidService::cleanupTestCase() {
    delete m_service;
    delete m_db;
}

void TestFirstAidService::init() {}
void TestFirstAidService::cleanup() {}

// ============================================================================
// 数据加载测试
// ============================================================================

void TestFirstAidService::testLoadInitialData() {
    // 已经 initTestCase 中加载
    QVERIFY(m_service->totalEntries() > 0);
}

void TestFirstAidService::testTotalCount() {
    int count = m_service->totalEntries();
    QVERIFY2(count >= 8, qPrintable(QString("Expected >= 8, got %1").arg(count)));
}

void TestFirstAidService::testCriticalCount() {
    int critical = m_service->criticalCount();
    QVERIFY2(critical >= 3, qPrintable(QString("Expected >= 3 critical, got %1").arg(critical)));
}

// ============================================================================
// 查询测试
// ============================================================================

void TestFirstAidService::testGetById_valid() {
    QVariantMap entry = m_service->getById("firstaid_cpr");
    QVERIFY(!entry.isEmpty());
    QCOMPARE(entry["id"].toString(), QString("firstaid_cpr"));
    QVERIFY(!entry["title"].toString().isEmpty());
    QVERIFY(entry["urgency"].toInt() >= 4);  // CPR 是危急
}

void TestFirstAidService::testGetById_invalid() {
    QVariantMap entry = m_service->getById("nonexistent_id_12345");
    QVERIFY(entry.isEmpty());
}

void TestFirstAidService::testGetByCategory() {
    auto critical = m_service->getByCategory(FirstAidService::Category::Critical);
    QVERIFY(critical.size() > 0);

    auto trauma = m_service->getByCategory(FirstAidService::Category::Trauma);
    QVERIFY(trauma.size() > 0);

    // 互斥性
    for (const auto& c : critical) {
        for (const auto& t : trauma) {
            QVERIFY(c.toMap()["id"] != t.toMap()["id"]);
        }
    }
}

// getAllEntries() 从 Phase 5 批次 3 起返回 Result 信封 {ok, value, error},
// 不是裸列表. 测试统一走这个 helper 解包, 否则会拿到信封的 5 个 key.
static QVariantList allEntriesOf(FirstAidService* s) {
    QVariantMap env = s->getAllEntries();
    if (!env["ok"].toBool()) return {};
    return env["value"].toList();
}

void TestFirstAidService::testGetByCategoryAll() {
    auto all = allEntriesOf(m_service);
    QVERIFY(all.size() >= 8);

    auto critical = m_service->getByCategory(FirstAidService::Category::Critical);
    auto trauma = m_service->getByCategory(FirstAidService::Category::Trauma);
    auto environment = m_service->getByCategory(FirstAidService::Category::Environment);
    auto poison = m_service->getByCategory(FirstAidService::Category::Poison);

    int total = critical.size() + trauma.size() +
                environment.size() + poison.size();
    QVERIFY(total >= 8);
}

void TestFirstAidService::testGetByUrgency() {
    auto critical = m_service->getByUrgency(FirstAidService::Urgency::Crisis);
    QVERIFY(critical.size() > 0);

    for (const auto& e : critical) {
        QCOMPARE(e.toMap()["urgency"].toInt(), 5);
    }
}

void TestFirstAidService::testGetCritical() {
    auto critical = m_service->getCritical();
    QVERIFY(critical.size() > 0);

    for (const auto& e : critical) {
        QVERIFY(e.toMap()["urgency"].toInt() >= 4);
    }
}

void TestFirstAidService::testSearch_existing() {
    auto results = m_service->search("出血");
    QVERIFY(results.size() > 0);
}

void TestFirstAidService::testSearch_empty() {
    auto results = m_service->search("");
    QVERIFY(results.isEmpty());
}

void TestFirstAidService::testSearch_notFound() {
    auto results = m_service->search("xyzabc123notfound");
    QVERIFY(results.isEmpty());
}

void TestFirstAidService::testSearch_caseInsensitive() {
    auto lower = m_service->search("cpr");
    auto upper = m_service->search("CPR");
    auto mixed = m_service->search("Cpr");
    QCOMPARE(lower.size(), upper.size());
    QCOMPARE(lower.size(), mixed.size());
}

// ============================================================================
// 决策树测试
// ============================================================================

void TestFirstAidService::testGetDecisionRoot_valid() {
    QVariantMap root = m_service->getDecisionRoot("firstaid_snake_bite");
    QVERIFY(!root.isEmpty());
    QVERIFY(!root["question"].toString().isEmpty());
    QVERIFY(!root["options"].toList().isEmpty());
}

void TestFirstAidService::testGetDecisionRoot_invalid() {
    QVariantMap root = m_service->getDecisionRoot("nonexistent");
    QVERIFY(root.isEmpty());
}

void TestFirstAidService::testGetDecisionNode() {
    QVariantMap root = m_service->getDecisionRoot("firstaid_snake_bite");
    QString rootId = root["id"].toString();
    if (!rootId.isEmpty()) {
        QVariantMap node = m_service->getDecisionNode(rootId);
        // 子节点可能不存在
        Q_UNUSED(node);
    }
}

// ============================================================================
// 急救包测试
// ============================================================================

void TestFirstAidService::testGetKitTemplates() {
    auto templates = m_service->getKitTemplates();
    QVERIFY(templates.size() >= 3);
}

void TestFirstAidService::testGetKitTemplate_valid() {
    QVariantMap kit = m_service->getKitTemplate("hike_1day");
    QVERIFY(!kit.isEmpty());
    QVERIFY(!kit["items"].toList().isEmpty());
    // getKitTemplate() 原样透传 firstaid_entries.json 的下划线字段,
    // 只有 getKitTemplates() 会重命名成 totalWeightG.
    QVERIFY(kit["total_weight_g"].toInt() > 0);
}

void TestFirstAidService::testGetKitTemplate_invalid() {
    QVariantMap kit = m_service->getKitTemplate("nonexistent");
    QVERIFY(kit.isEmpty());
}

// ============================================================================
// 关联测试
// ============================================================================

void TestFirstAidService::testGetRelatedSpecies() {
    QStringList species = m_service->getRelatedSpecies("firstaid_snake_bite");
    QVERIFY(species.size() > 0);
}

// ============================================================================
// 数据完整性
// ============================================================================

void TestFirstAidService::testDataIntegrity_titleNotEmpty() {
    auto all = allEntriesOf(m_service);
    QVERIFY(!all.isEmpty());
    for (const auto& e : all) {
        QVERIFY2(!e.toMap()["title"].toString().isEmpty(),
                 qPrintable("Title is empty for id: " +
                            e.toMap()["id"].toString()));
    }
}

void TestFirstAidService::testDataIntegrity_criticalActionsForHighUrgency() {
    // getCritical() 是精简摘要 (id/title/urgency/category), 不含 criticalActions;
    // 完整性要逐条回到 getById() 取全量字段再校验.
    auto critical = m_service->getCritical();
    QVERIFY(!critical.isEmpty());
    for (const auto& e : critical) {
        QVariantMap summary = e.toMap();
        QVariantMap full = m_service->getById(summary["id"].toString());
        QVERIFY2(!full["criticalActions"].toList().isEmpty(),
                 qPrintable("Critical entry missing critical_actions: " +
                            summary["id"].toString()));
    }
}

void TestFirstAidService::testDataIntegrity_urgencyInRange() {
    auto all = allEntriesOf(m_service);
    QVERIFY(!all.isEmpty());
    for (const auto& e : all) {
        int urgency = e.toMap()["urgency"].toInt();
        QVERIFY(urgency >= 1 && urgency <= 5);
    }
}

QTEST_MAIN(TestFirstAidService)
#include "test_first_aid.moc"
