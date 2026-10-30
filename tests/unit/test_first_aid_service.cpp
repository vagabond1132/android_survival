/**
 * @file test_first_aid_service.cpp
 * @brief 急救服务单元测试
 */

#include <QtTest>
#include <QTemporaryDir>
#include <QQueue>
#include <QSet>
#include <functional>

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

    void test_loadCount() {  // 2026-10-22: 原名 test_load_data — QTest 把 *_data 当数据函数, 没有同名 _test 就整条静默跳过
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
        QVERIFY2(!root.isEmpty(), "蛇咬条目应有决策树根节点");
        // 2026-10-20: 根必须是"没被任何 next_id 指过"的那个节点. 旧实现取该 entry 在
        // JSON 里出现的第一个节点, 顺序一变就返回一个 question 为空的叶子.
        QCOMPARE(root["id"].toString(), QStringLiteral("snake_bite_root"));
        QVERIFY2(!root["question"].toString().isEmpty(), "根节点应带问题文案");
        QCOMPARE(root["isTerminal"].toBool(), false);
    }

    void test_decision_nextIds_walk_the_tree() {
        // QML 只能靠 nextIds 逐跳, 因为它不知道 id 命名规则 (snake_bite_step2 是语义名,
        // 不是 "父id_序号"). 这一条是决策页能走通的唯一保证.
        QVariantMap root = m_service->getDecisionRoot("firstaid_snake_bite");
        const QVariantList options = root["options"].toList();
        const QVariantList nextIds = root["nextIds"].toList();
        QCOMPARE(nextIds.size(), options.size());
        QVERIFY2(!nextIds.isEmpty(), "根节点应有可选项");
        for (const QVariant& nid : nextIds) {
            const QString id = nid.toString();
            QVERIFY2(!id.isEmpty(), qPrintable(QStringLiteral("选项 %1 缺 next_id").arg(id)));
            const QVariantMap next = m_service->getDecisionNode(id);
            QVERIFY2(!next.isEmpty(), qPrintable(QStringLiteral("next_id %1 在库里不存在").arg(id)));
            QCOMPARE(next["id"].toString(), id);
        }

        // 顺着"不确定"这条路走到底, 应落在一个带 terminalAction 的叶子
        QVariantMap node = m_service->getDecisionNode(
            nextIds.at(options.size() > 1 ? 1 : 0).toString());
        int hops = 0;
        while (!node.isEmpty() && !node["isTerminal"].toBool() && hops < 8) {
            const QVariantList nx = node["nextIds"].toList();
            QVERIFY2(!nx.isEmpty(), "非终态节点必须有下一跳");
            node = m_service->getDecisionNode(nx.first().toString());
            ++hops;
        }
        QVERIFY2(!node.isEmpty(), "决策路径中途断了");
        QVERIFY2(node["isTerminal"].toBool(),
                 qPrintable(QStringLiteral("走 %1 跳后仍未到终态").arg(hops)));
        QVERIFY(!node["terminalAction"].toString().isEmpty());
    }

    void test_decision_root_absent_for_entry_without_tree() {
        // 35 条里只有蛇咬有决策树; 其余条目必须返回空, FirstAidDetailPage 靠它决定
        // 要不要显示"交互式决策"入口.
        QVERIFY(m_service->getDecisionRoot(QStringLiteral("firstaid_cpr")).isEmpty());
        QVERIFY(m_service->getDecisionNode(QStringLiteral("no_such_node")).isEmpty());
    }

    void test_decision_whole_tree_is_walkable() {
        // FirstAidDecisionPage 只做一件事: 拿 nextIds[index] 去 getDecisionNode().
        // 所以它对用户的全部保证就是"任何一条路都能走到有文案的终态, 且不会转圈".
        // 这里把树上每个分支都扫一遍 —— 只走一条路径的话, 断链的那支照样能瞒过去
        // (旧页靠猜 id, 猜错就掉进假终态, 就是这个盲区).
        const QVariantMap root = m_service->getDecisionRoot("firstaid_snake_bite");
        QVERIFY(!root.isEmpty());

        // ① 覆盖与断链 (BFS). 允许菱形: 根和"check"两支都汇到 snake_bite_step2,
        //    那是数据本意 (两条问法同一个结论), 不是环.
        QQueue<QString> q;
        QSet<QString> seen;
        q.enqueue(root["id"].toString());
        seen.insert(root["id"].toString());
        int terminals = 0;
        while (!q.isEmpty()) {
            const QVariantMap node = m_service->getDecisionNode(q.dequeue());
            QVERIFY2(!node.isEmpty(), "BFS 取到空节点");
            const QVariantList labels = node["options"].toList();
            const QVariantList nextIds = node["nextIds"].toList();
            if (node["isTerminal"].toBool()) {
                QVERIFY2(!node["terminalAction"].toString().isEmpty(),
                         qPrintable(QStringLiteral("终态 %1 没有结论文案").arg(node["id"].toString())));
                ++terminals;
                continue;
            }
            QVERIFY2(!labels.isEmpty(),
                     qPrintable(QStringLiteral("%1 既不是终态也没有选项 → 页面会卡在空问题上")
                                .arg(node["id"].toString())));
            QCOMPARE(nextIds.size(), labels.size());
            for (int i = 0; i < nextIds.size(); ++i) {
                const QString nid = nextIds.at(i).toString();
                QVERIFY2(!nid.isEmpty(),
                         qPrintable(QStringLiteral("%1 的选项「%2」没有 next_id")
                                    .arg(node["id"].toString())
                                    .arg(labels.at(i).toString())));
                QVERIFY2(!m_service->getDecisionNode(nid).isEmpty(),
                         qPrintable(QStringLiteral("next_id %1 在库里不存在").arg(nid)));
                if (seen.contains(nid)) continue;
                seen.insert(nid);
                q.enqueue(nid);
            }
        }
        // 库里 8 个节点: 1 根 + 3 问 + 4 结论. 数字变了说明数据动过, 页面文案要跟着核.
        QCOMPARE(seen.size(), 8);
        QCOMPARE(terminals, 4);

        // ② 每一条路都真的落到终态, 且同一条路上不重访 (环 = 页面永远走不出去)
        QString bad;
        std::function<bool(const QString&, QSet<QString>)> walk =
            [&](const QString& id, QSet<QString> path) -> bool {
                if (path.contains(id)) {
                    bad = QStringLiteral("路径绕回 %1").arg(id);
                    return false;
                }
                path.insert(id);
                const QVariantMap n = m_service->getDecisionNode(id);
                if (n.isEmpty()) {
                    bad = QStringLiteral("%1 查不到节点").arg(id);
                    return false;
                }
                if (n["isTerminal"].toBool()) return true;
                const QVariantList nx = n["nextIds"].toList();
                for (const QVariant& v : nx) {
                    if (!walk(v.toString(), path)) return false;
                }
                return true;
            };
        QVERIFY2(walk(root["id"].toString(), QSet<QString>()), qPrintable(bad));
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
