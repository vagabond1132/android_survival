/**
 * @file test_checklist_service.cpp
 * @brief preparation/ChecklistService 单元测试
 *
 * 此前该服务 0 覆盖 (线上实现是 preparation/, 旧 test_* 只测 emergency/ 副本)。
 *
 * 覆盖:
 *   - checklists.json 4 套模板加载 + 条目落库 (item id 非空, QML 勾选依赖)
 *   - 自定义清单 CRUD (createCustom / getCustomLists / getById / deleteChecklist)
 *   - 勾选与数量变更 → checkedCount / totalWeight 统计
 *   - addItem / deleteItem
 *   - 文本与 JSON 导出 + importFromJson 回环
 *   - 非法入参的错误契约 {ok:false, error.code}
 */
#include <QtTest>
#include <QTemporaryDir>
#include <QJsonArray>
#include <QJsonObject>

#include "src/core/Database.h"
#include "src/core/ServiceErrors.h"
#include "src/preparation/ChecklistService.h"

using namespace outdoor;

class TestChecklistService : public QObject {
    Q_OBJECT

private:
    QTemporaryDir* m_tmpDir = nullptr;
    Database* m_db = nullptr;
    ChecklistService* m_svc = nullptr;

    // QmlResultBridge 把 error 塞成 QVariant(ServiceError) 而非 QVariantMap,
    // 必须先取出结构体再读 code/message
    static ServiceError errOf(const QVariantMap& r) {
        const QVariant ev = r.value(QLatin1String("error"));
        if (ev.canConvert<ServiceError>()) return ev.value<ServiceError>();
        return {};
    }

    static QString ok(const QVariantMap& r) {
        if (r.value(QLatin1String("ok")).toBool()) return QString();
        const ServiceError e = errOf(r);
        return QStringLiteral("code=%1 msg=%2")
            .arg(ServiceError::codeToString(e.code), e.message);
    }

private slots:
    void initTestCase() {
        m_tmpDir = new QTemporaryDir();
        QVERIFY(m_tmpDir->isValid());
        m_db = new Database();
        QVERIFY(m_db->open(m_tmpDir->path()));
        m_svc = new ChecklistService(m_db);
        QVERIFY(m_svc->loadInitialData());
    }

    void cleanupTestCase() {
        delete m_svc;
        if (m_db) { m_db->close(); }
        delete m_db;
        delete m_tmpDir;
    }

    // ===== 模板 =====
    void test_templatesLoaded() {
        const QVariantList t = m_svc->getTemplates();
        QVERIFY2(t.size() >= 4, qPrintable(QStringLiteral("模板数 %1").arg(t.size())));
        QCOMPARE(m_svc->totalTemplates() >= 4, true);
    }

    void test_templateItemsHaveIds() {
        // QML ChecklistDetailPage 用 item.id 勾选, id 为空则勾选必然失效
        const QVariantMap hike = m_svc->getTemplate(QStringLiteral("hike_1day"));
        QVERIFY2(!hike.isEmpty(), "hike_1day 模板不存在");
        const QVariantList items = hike.value(QLatin1String("items")).toList();
        QVERIFY2(!items.isEmpty(), "hike_1day 无条目");
        for (const QVariant& v : items) {
            QVERIFY2(!v.toMap().value(QLatin1String("id")).toString().isEmpty(),
                     "模板条目缺 id");
        }
    }

    void test_getTemplateUnknownScenarioIsEmpty() {
        QVERIFY(m_svc->getTemplate(QStringLiteral("nope")).isEmpty());
    }

    // ===== 自定义清单 =====
    void test_createCustomReturnsIdAndIsListed() {
        const QVariantMap r = m_svc->createCustom(QStringLiteral("测试清单"));
        QVERIFY2(r.value("ok").toBool(), qPrintable(ok(r)));
        const QString id = r.value(QLatin1String("value")).toString();
        QVERIFY(!id.isEmpty());

        const QVariantMap got = m_svc->getById(id);
        QCOMPARE(got.value("name").toString(), QStringLiteral("测试清单"));
        QVERIFY(!got.value("isTemplate").toBool());
        QVERIFY(m_svc->getCustomLists().size() >= 1);
    }

    void test_createCustomRejectsBlankName() {
        const QVariantMap r = m_svc->createCustom(QStringLiteral("   "));
        QVERIFY(!r.value("ok").toBool());
        QCOMPARE(ServiceError::codeToString(errOf(r).code),
                 QStringLiteral("InvalidArgument"));
    }

    void test_addItemUpdatesWeightAndCount() {
        const QString id = m_svc->createCustom(QStringLiteral("负重测试"))
                             .value("value").toString();

        ChecklistService::Item item;
        item.name = QStringLiteral("登山杖");
        item.category = QStringLiteral("装备");
        item.quantity = 2;
        item.weightG = 180;
        item.required = true;

        const QVariantMap add = m_svc->addItem(id, item);
        QVERIFY2(add.value("ok").toBool(), qPrintable(ok(add)));

        const QVariantMap got = m_svc->getById(id);
        QCOMPARE(got.value("items").toList().size(), 1);
        QCOMPARE(m_svc->getTotalWeight(id), 360.0);   // 180g x 2
    }

    void test_setItemCheckedDrivesCheckedCount() {
        const QString id = m_svc->createCustom(QStringLiteral("勾选测试"))
                             .value("value").toString();
        ChecklistService::Item item;
        item.name = QStringLiteral("头灯");
        item.weightG = 90;
        item.quantity = 1;
        QVERIFY(m_svc->addItem(id, item).value("ok").toBool());

        const QString itemId = m_svc->getById(id).value("items").toList()
                                 .first().toMap().value("id").toString();
        QVERIFY(!itemId.isEmpty());

        QCOMPARE(m_svc->getCheckedCount(id), 0);
        QVERIFY(m_svc->setItemChecked(id, itemId, true).value("ok").toBool());
        QCOMPARE(m_svc->getCheckedCount(id), 1);
        QVERIFY(m_svc->setItemChecked(id, itemId, false).value("ok").toBool());
        QCOMPARE(m_svc->getCheckedCount(id), 0);
    }

    void test_setItemQuantityRecomputesWeight() {
        const QString id = m_svc->createCustom(QStringLiteral("数量测试"))
                             .value("value").toString();
        ChecklistService::Item item;
        item.name = QStringLiteral("能量胶");
        item.weightG = 40;
        item.quantity = 1;
        QVERIFY(m_svc->addItem(id, item).value("ok").toBool());

        const QString itemId = m_svc->getById(id).value("items").toList()
                                 .first().toMap().value("id").toString();
        QVERIFY(m_svc->setItemQuantity(id, itemId, 5).value("ok").toBool());
        QCOMPARE(m_svc->getTotalWeight(id), 200.0);
    }

    void test_deleteItemRemovesIt() {
        const QString id = m_svc->createCustom(QStringLiteral("删项测试"))
                             .value("value").toString();
        ChecklistService::Item item;
        item.name = QStringLiteral("废弃项");
        item.weightG = 10;
        QVERIFY(m_svc->addItem(id, item).value("ok").toBool());

        const QString itemId = m_svc->getById(id).value("items").toList()
                                 .first().toMap().value("id").toString();
        QVERIFY(m_svc->deleteItem(id, itemId).value("ok").toBool());
        QVERIFY(m_svc->getById(id).value("items").toList().isEmpty());
    }

    void test_deleteChecklistIsSoftDelete() {
        const QString id = m_svc->createCustom(QStringLiteral("待删清单"))
                             .value("value").toString();
        QVERIFY(m_svc->deleteChecklist(id).value("ok").toBool());
        // 软删除后 getById 不应再命中
        QVERIFY(m_svc->getById(id).isEmpty());
    }

    // ===== 导出 / 导入 =====
    void test_exportToTextContainsItems() {
        const QString id = m_svc->createCustom(QStringLiteral("导出测试"))
                             .value("value").toString();
        ChecklistService::Item item;
        item.name = QStringLiteral("雨衣");
        item.category = QStringLiteral("衣物");
        item.weightG = 220;
        item.quantity = 1;
        QVERIFY(m_svc->addItem(id, item).value("ok").toBool());

        const QString text = m_svc->exportToText(id);
        QVERIFY2(text.contains(QStringLiteral("雨衣")), qPrintable(text));
        QVERIFY(text.contains(QStringLiteral("导出测试")));
    }

    void test_jsonExportImportRoundTrip() {
        const QString id = m_svc->createCustom(QStringLiteral("回环清单"))
                             .value("value").toString();
        ChecklistService::Item item;
        item.name = QStringLiteral("保温毯");
        item.weightG = 55;
        item.quantity = 2;
        QVERIFY(m_svc->addItem(id, item).value("ok").toBool());

        const QJsonObject json = m_svc->exportToJson(id);
        QVERIFY2(!json.isEmpty(), "exportToJson 返回空对象");

        const QVariantMap imp = m_svc->importFromJson(json);
        QVERIFY2(imp.value("ok").toBool(), qPrintable(ok(imp)));
        const QString newId = imp.value("value").toString();
        QVERIFY(!newId.isEmpty());
        QVERIFY(newId != id);

        const QVariantMap imported = m_svc->getById(newId);
        QCOMPARE(imported.value("items").toList().size(), 1);
        QCOMPARE(m_svc->getTotalWeight(newId), 110.0);
    }

    void test_importFromJsonRejectsGarbage() {
        const QVariantMap r = m_svc->importFromJson(QJsonObject{});
        QVERIFY2(!r.value("ok").toBool(), "空 JSON 不应导入成功");
    }

    // ===== 错误契约 =====
    void test_operationsOnMissingChecklistReturnNotFound() {
        const QString missing = QStringLiteral("00000000-0000-0000-0000-000000000000");
        for (const QVariantMap& r : {m_svc->deleteChecklist(missing),
                                     m_svc->setItemChecked(missing, "x", true),
                                     m_svc->addItem(missing, ChecklistService::Item{})}) {
            QVERIFY2(!r.value("ok").toBool(), "不存在的清单操作应失败");
        }
    }

    void test_persistenceAcrossReconstruction() {
        const QString id = m_svc->createCustom(QStringLiteral("持久化测试"))
                             .value("value").toString();
        ChecklistService::Item item;
        item.name = QStringLiteral("指南针");
        item.weightG = 30;
        QVERIFY(m_svc->addItem(id, item).value("ok").toBool());

        delete m_svc;
        m_svc = new ChecklistService(m_db);
        QVERIFY(m_svc->loadInitialData());
        // 自定义清单在 user.db, 重建服务后应仍在
        QVERIFY(!m_svc->getById(id).isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestChecklistService)
#include "test_checklist_service.moc"
