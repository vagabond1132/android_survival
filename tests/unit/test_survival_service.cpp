/**
 * @file test_survival_service.cpp
 * @brief 生存技能服务单元测试
 *
 * 2026-10-16: 本套件从未参与编译 (tests/CMakeLists.txt 之前只挂了一部分),
 *   对照 SurvivalService.h 的真实 API 重写:
 *     - 没有 totalCount()/getAll(), 只有 fireMethodsCount/shelterCount/toolCount
 *       + getByTopic(Topic) (枚举参数, 不是字符串主题名)
 *     - getCategories 参数同样是 Topic 枚举
 *   数据基线来自 assets/data/survival_items.json: 15 条, topic 仅 0/1/2/7 有值.
 */

#include <QtTest>
#include <QTemporaryDir>

#include "src/survival/SurvivalService.h"
#include "src/core/Database.h"

using namespace outdoor;

namespace {

// 与 SurvivalService::Topic 一一对应, 用于遍历全量
const SurvivalService::Topic kAllTopics[] = {
    SurvivalService::Topic::Fire,       SurvivalService::Topic::Shelter,
    SurvivalService::Topic::Water,      SurvivalService::Topic::Food,
    SurvivalService::Topic::Signaling,  SurvivalService::Topic::Navigation,
    SurvivalService::Topic::Weather,    SurvivalService::Topic::Tools,
};

}  // namespace

class TestSurvivalService : public QObject {
    Q_OBJECT

private:
    SurvivalService* m_service = nullptr;
    Database* m_db = nullptr;
    QTemporaryDir m_tmpDir;

    QVariantList allItems() const {
        QVariantList all;
        for (SurvivalService::Topic t : kAllTopics) all << m_service->getByTopic(t);
        return all;
    }

private slots:
    void init() {
        QVERIFY(m_tmpDir.isValid());
        m_db = new Database();
        QVERIFY(m_db->open(m_tmpDir.path()));
        m_db->migrate();
        m_service = new SurvivalService(m_db);
        QVERIFY(m_service->loadInitialData());
    }

    void cleanup() {
        delete m_service;
        delete m_db;
    }

    void test_loadCount() {  // 2026-10-22: 原名 test_load_data — QTest 把 *_data 当数据函数, 没有同名 _test 就整条静默跳过
        // survival_items.json 有 15 条, 低于 10 说明 JSON 解析或入库有丢数据
        const QVariantList all = allItems();
        QVERIFY2(all.size() >= 15, qPrintable(QStringLiteral("加载 %1 条").arg(all.size())));
        qInfo() << "Survival items:" << all.size();
    }

    void test_topic_counts() {
        QCOMPARE(m_service->fireMethodsCount(), m_service->getByTopic(SurvivalService::Topic::Fire).size());
        QCOMPARE(m_service->shelterCount(), m_service->getByTopic(SurvivalService::Topic::Shelter).size());
        QCOMPARE(m_service->toolCount(), m_service->getByTopic(SurvivalService::Topic::Tools).size());
        QVERIFY(m_service->fireMethodsCount() > 0);
    }

    void test_get_by_topic() {
        const QVariantList fire = m_service->getByTopic(SurvivalService::Topic::Fire);
        QVERIFY(fire.size() > 0);
        // getByTopic 的精简 map 不含 topic 字段, 回查 getById 校验归属
        for (const auto& i : fire) {
            const QString id = i.toMap()["id"].toString();
            const QVariantMap full = m_service->getById(id);
            QCOMPARE(full["topic"].toInt(), static_cast<int>(SurvivalService::Topic::Fire));
            QVERIFY(!full["category"].toString().isEmpty());
            QVERIFY(full["difficulty"].toInt() >= 1);
        }
        // 分类必须与 getCategories 去重结果一致
        QStringList cats;
        for (const auto& i : fire) {
            const QString c = m_service->getById(i.toMap()["id"].toString())["category"].toString();
            if (!cats.contains(c)) cats << c;
        }
        QCOMPARE(cats.size(), m_service->getCategories(SurvivalService::Topic::Fire).size());
    }

    void test_get_by_topic_empty_topic() {
        // 当前数据集里"食物"主题还没有内容, 返回空列表而不是崩溃
        QVERIFY(m_service->getByTopic(SurvivalService::Topic::Food).isEmpty());
    }

    void test_get_by_difficulty() {
        QVariantList easy = m_service->getByDifficulty(2);
        QVERIFY(easy.size() > 0);
        for (const auto& i : easy) {
            QVERIFY(i.toMap()["difficulty"].toInt() <= 2);
        }
        // maxDifficulty=5 是全量上界, 不少于任何更小的阈值
        QVERIFY(m_service->getByDifficulty(5).size() >= easy.size());
        QVERIFY(m_service->getByDifficulty(1).size() <= easy.size());
    }

    void test_get_by_id() {
        const QVariantList all = allItems();
        QVERIFY(!all.isEmpty());
        const QString firstId = all.first().toMap()["id"].toString();
        QVERIFY(!firstId.isEmpty());
        const QVariantMap item = m_service->getById(firstId);
        QVERIFY(!item.isEmpty());
        QCOMPARE(item["id"].toString(), firstId);
        QVERIFY(!item["name"].toString().isEmpty());
    }

    void test_get_by_id_nonexistent() {
        QVERIFY(m_service->getById("nonexistent").isEmpty());
    }

    void test_search() {
        QVariantList r = m_service->search("火");
        QVERIFY(r.size() > 0);
        for (const auto& i : r) {
            QVERIFY(!i.toMap()["id"].toString().isEmpty());
        }
    }

    void test_search_empty_keyword() {
        // search("") 直接返回空列表 (与 FirstAid/Species/Route 一致), 全量请用 getByTopic
        QCOMPARE(m_service->search("").size(), 0);
    }

    void test_get_categories() {
        QStringList cats = m_service->getCategories(SurvivalService::Topic::Fire);
        QVERIFY(cats.size() > 0);
        for (const QString& c : cats) QVERIFY(!c.isEmpty());
        // 空主题不应给出分类
        QVERIFY(m_service->getCategories(SurvivalService::Topic::Food).isEmpty());
    }
};

QTEST_MAIN(TestSurvivalService)
#include "test_survival_service.moc"
