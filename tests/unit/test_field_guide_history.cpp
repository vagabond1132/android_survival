/**
 * @file test_field_guide_history.cpp
 * @brief FieldGuideHistory 测试
 *
 * 覆盖: addRecord/delete/setFavorite/addNote/getRecent/getByKingdom/
 *       getByRoute/statsByKingdom/dataChanged 信号 + Result 形状.
 *
 * 2026-10-16: 原来用 initTestCase 让 11 个用例共用一份历史, 计数断言互相依赖
 *   (test_addRecord_animal 里的 plantCount 期望值取决于前一个用例是否先跑).
 *   改成 init/cleanup, 每个用例独占一个临时库, 断言可以直接写死.
 */

#include "species/FieldGuideHistory.h"
#include "core/Database.h"
#include "core/ServiceErrors.h"

#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>

using namespace outdoor;

namespace {

// 阶段 L3.7: 写操作返回 Result {ok, value, error}. error 是 Q_DECLARE_METATYPE 的
// ServiceError (无 Q_GADGET), 只能 qvariant_cast 取出, 不能当 QVariantMap 读.
QString errText(const QVariantMap& r) {
    const QVariant ev = r.value(QLatin1String("error"));
    if (!ev.canConvert<ServiceError>()) return QString();
    const ServiceError e = ev.value<ServiceError>();
    return QStringLiteral("%1: %2").arg(ServiceError::codeToString(e.code), e.message);
}

QString errCode(const QVariantMap& r) {
    const QVariant ev = r.value(QLatin1String("error"));
    if (!ev.canConvert<ServiceError>()) return QString();
    return ServiceError::codeToString(ev.value<ServiceError>().code);
}

}  // namespace

class TestFieldGuideHistory : public QObject {
    Q_OBJECT

private:
    QTemporaryDir m_tmpDir;
    Database* m_db = nullptr;
    FieldGuideHistory* m_history = nullptr;

    qint64 addOne(const QString& entityId, const QString& kingdom,
                  const QString& commonName, int dangerLevel = 0) {
        ViewRecord r;
        r.entityId = entityId;
        r.kingdom = kingdom;
        r.commonName = commonName;
        r.dangerLevel = dangerLevel;
        r.viewedAt = QDateTime::currentDateTime();
        const QVariantMap res = m_history->addRecord(r);
        // QVERIFY2 在返回值非 void 的辅助函数里会展开成 `return;`, 这里只能手动报错
        if (!res.value("ok").toBool()) {
            qWarning() << "addRecord 失败:" << errText(res);
            return -1;
        }
        return res.value("value").toLongLong();
    }

private slots:
    void init() {
        // 2026-10-16 修: 成员 QTemporaryDir 只建一次, 用例间共用同一个 db 会让
        // 上一条用例写的浏览记录漏进下一条 (count 类断言全歪). 每个用例换新临时目录.
        m_tmpDir = QTemporaryDir();
        QVERIFY(m_tmpDir.isValid());
        m_db = new Database();
        QVERIFY(m_db->open(m_tmpDir.path()));
        m_history = new FieldGuideHistory(m_db);
        QCOMPARE(m_history->totalCount(), 0);
    }

    void cleanup() {
        delete m_history;
        delete m_db;
        m_history = nullptr;
        m_db = nullptr;
    }

    void test_addRecord_returnsId() {
        const qint64 id = addOne("plant_shepherd_purse", "plantae", "荠菜");
        QVERIFY(id > 0);
        QCOMPARE(m_history->totalCount(), 1);
        QCOMPARE(m_history->plantCount(), 1);
    }

    void test_addRecord_kingdomCounts() {
        addOne("animal_gloydius_brevicaudus", "animalia", "短尾蝮", 5);
        addOne("mushroom_amanita_verna", "fungi", "致命白毒伞", 5);
        addOne("insect_tick", "insecta", "蜱虫", 4);
        QCOMPARE(m_history->animalCount(), 1);
        QCOMPARE(m_history->mushroomCount(), 1);
        QCOMPARE(m_history->insectCount(), 1);
        QCOMPARE(m_history->totalCount(), 3);
    }

    void test_addRecord_persistsAllFields() {
        ViewRecord r;
        r.entityId = "plant_taraxacum";
        r.kingdom = "plantae";
        r.commonName = "蒲公英";
        r.scientificName = "Taraxacum mongolicum";
        r.category = "wild_vegetable";
        r.dangerLevel = 1;
        r.viewSource = "route";
        r.routeId = "taihang_south";
        r.note = "崂山巨峰线 4 月见到大片";
        r.viewedAt = QDateTime::currentDateTime();
        const QVariantMap res = m_history->addRecord(r);
        QVERIFY2(res.value("ok").toBool(), qPrintable(errText(res)));
        const qint64 added = res.value("value").toLongLong();
        QVERIFY(added > 0);

        const QVariantMap got = m_history->getById(added);
        QCOMPARE(got["entityId"].toString(), r.entityId);
        QCOMPARE(got["kingdom"].toString(), r.kingdom);
        QCOMPARE(got["commonName"].toString(), r.commonName);
        QCOMPARE(got["scientificName"].toString(), r.scientificName);
        QCOMPARE(got["category"].toString(), r.category);
        QCOMPARE(got["dangerLevel"].toInt(), r.dangerLevel);
        QCOMPARE(got["routeId"].toString(), r.routeId);
    }

    void test_getRecent_ordersByViewedAtDesc() {
        // viewed_at 用 ISO 文本存储, 同一秒内的记录顺序不稳定 → 用递增时间戳
        for (int i = 0; i < 5; ++i) {
            ViewRecord r;
            r.entityId = QString("plant_%1").arg(i);
            r.kingdom = "plantae";
            r.commonName = QString("物种%1").arg(i);
            r.viewedAt = QDateTime::currentDateTime().addDays(-i);
            QVERIFY(m_history->addRecord(r).value("ok").toBool());
        }
        QVariantList list = m_history->getRecent(10);
        QCOMPARE(list.size(), 5);
        QCOMPARE(list.first().toMap()["entityId"].toString(), QString("plant_0"));
        QCOMPARE(list.last().toMap()["entityId"].toString(), QString("plant_4"));
        QVERIFY(list.first().toMap().contains("kingdom"));

        // limit 生效
        QCOMPARE(m_history->getRecent(2).size(), 2);
    }

    void test_getByKingdom() {
        addOne("plant_a", "plantae", "甲");
        addOne("plant_b", "plantae", "乙");
        addOne("animal_c", "animalia", "丙");
        QCOMPARE(m_history->getByKingdom("plantae").size(), 2);
        QCOMPARE(m_history->getByKingdom("animalia").size(), 1);
        QCOMPARE(m_history->getByKingdom("fungi").size(), 0);
    }

    void test_getByRoute() {
        ViewRecord r;
        r.entityId = "animal_x";
        r.kingdom = "animalia";
        r.commonName = "蝮蛇";
        r.routeId = "taihang_south";
        r.viewedAt = QDateTime::currentDateTime();
        QVERIFY(m_history->addRecord(r).value("ok").toBool());
        addOne("animal_y", "animalia", "无路线关联");

        QCOMPARE(m_history->getByRoute("taihang_south").size(), 1);
        QCOMPARE(m_history->getByRoute("no_such_route").size(), 0);
    }

    void test_setFavorite() {
        const qint64 id = addOne("plant_fav", "plantae", "荠菜");
        QVERIFY(m_history->setFavorite(id, true).value("ok").toBool());
        QCOMPARE(m_history->getFavorites().size(), 1);
        QCOMPARE(m_history->getById(id)["isFavorite"].toBool(), true);

        QVERIFY(m_history->setFavorite(id, false).value("ok").toBool());
        QCOMPARE(m_history->getFavorites().size(), 0);
    }

    void test_addNote() {
        const qint64 id = addOne("plant_note", "plantae", "蒲公英");
        QVERIFY(m_history->addNote(id, "崂山巨峰线 4 月见到大片").value("ok").toBool());
        QCOMPARE(m_history->getById(id)["note"].toString(),
                 QString("崂山巨峰线 4 月见到大片"));
    }

    void test_deleteByEntity() {
        addOne("plant_del", "plantae", "荠菜");
        addOne("plant_keep", "plantae", "蒲公英");
        QVERIFY(m_history->deleteByEntity("plant_del").value("ok").toBool());
        QCOMPARE(m_history->plantCount(), 1);
        QCOMPARE(m_history->totalCount(), 1);
    }

    void test_deleteRecord_unknownId_isNotError() {
        // UPDATE/DELETE 影响 0 行不算失败, 只做幂等
        const QVariantMap r = m_history->deleteRecord(9999);
        QVERIFY2(r.value("ok").toBool() || errCode(r) == QLatin1String("NotFound"),
                 qPrintable(errText(r)));
    }

    void test_statsByKingdom() {
        addOne("plant_s", "plantae", "荠菜");
        addOne("animal_s", "animalia", "短尾蝮");
        addOne("insect_s", "insecta", "蜱虫");
        addOne("mushroom_s", "fungi", "白毒伞");

        const QVariantMap stats = m_history->statsByKingdom();
        for (const QString& key : {"plant", "animal", "insect", "mushroom", "total"}) {
            QVERIFY2(stats.contains(key), qPrintable(QStringLiteral("缺少 %1").arg(key)));
        }
        QCOMPARE(stats["total"].toInt(), 4);
        QCOMPARE(stats["plant"].toInt(), m_history->plantCount());
        QCOMPARE(stats["animal"].toInt() + stats["plant"].toInt()
                     + stats["insect"].toInt() + stats["mushroom"].toInt(),
                 stats["total"].toInt());
    }

    void test_dataChangedSignal() {
        QSignalSpy added(m_history, &FieldGuideHistory::recordAdded);
        QSignalSpy changed(m_history, &FieldGuideHistory::dataChanged);
        addOne("plant_sig", "plantae", "测试");
        QCOMPARE(added.count(), 1);
        QCOMPARE(changed.count(), 1);
    }
};

QTEST_MAIN(TestFieldGuideHistory)
#include "test_field_guide_history.moc"
