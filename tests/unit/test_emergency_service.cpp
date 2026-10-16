/**
 * @file test_emergency_service.cpp
 * @brief SOS 紧急服务测试
 */

#include "lifesaver/EmergencyService.h"
#include "core/Database.h"
#include "core/ServiceErrors.h"
#include "platform/PlatformInterface.h"

#include <QtTest>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QDir>

using namespace outdoor;

namespace {

// 阶段 L3.6 / Phase 5 之后, 联系人读写统一返回 Result 形状 {ok, value, error},
// 其中 error 是 Q_DECLARE_METATYPE 的 ServiceError (无 Q_GADGET), 只能 qvariant_cast 取.
QString errText(const QVariantMap& r) {
    const QVariant ev = r.value(QLatin1String("error"));
    if (!ev.canConvert<ServiceError>()) return QString();
    const ServiceError e = ev.value<ServiceError>();
    return QStringLiteral("%1: %2").arg(ServiceError::codeToString(e.code), e.message);
}

QVariantList contactsOf(const EmergencyService* s) {
    return s->getContacts().value(QLatin1String("value")).toList();
}

QString errOfCode(const QVariantMap& r) {
    const QVariant ev = r.value(QLatin1String("error"));
    if (!ev.canConvert<ServiceError>()) return QString();
    return ServiceError::codeToString(ev.value<ServiceError>().code);
}

}  // namespace

class MockPlatform : public PlatformInterface {
public:
    bool checkPermission(const QString&) override { return true; }
    void requestPermission(const QString&,
                            std::function<void(bool)>) override {}
    bool makePhoneCall(const QString& num) override {
        lastCallNumber = num;
        callCount++;
        return true;
    }
    bool sendSMS(const QString& num, const QString& text) override {
        lastSmsNumber = num;
        lastSmsText = text;
        smsCount++;
        return true;
    }
    void openUrl(const QString&) override {}
    void openAppSettings() override {}
    void vibrate(int) override {}
    bool hasFlashlight() override { return false; }
    void setFlashlight(bool) override {}
    int getBatteryLevel() override { return 80; }
    void keepScreenOn(bool) override {}
    void setBrightness(double) override {}
    void acquireWakeLock() override {}
    void releaseWakeLock() override {}
    QString getVersionName() override { return "1.0.0"; }
    QString getDeviceModel() override { return "Test"; }
    QString getManufacturer() override { return "TestCo"; }

    QString lastCallNumber;
    QString lastSmsNumber;
    QString lastSmsText;
    int callCount = 0;
    int smsCount = 0;
};

class TestEmergencyService : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void cleanupTestCase();
    void init();
    void cleanup();

    // 联系人测试
    void testAddContact_valid();
    void testAddContact_emptyName();
    void testAddContact_emptyPhone();
    void testDeleteContact();
    void testDeleteContact_outOfRange();
    void testSetPrimary();
    void testContactCount();
    void testGetContacts();
    void testContactLimit();

    // SOS 触发测试
    void testTriggerSOS();
    void testTriggerSOS_duplicate();
    void testCancelSOS();
    void testIsSosActive();
    void testSosHistory();

    // 拨号测试
    void testCall120();
    void testCall110();
    void testCall119();
    void testCallNumber();
    void testCallInitiatedSignal();

    // 短信测试
    void testSendSMS();
    void testSendSosSMSToAll();
    void testSmsContainsGPS();

private:
    EmergencyService* m_service;
    Database* m_db;
    MockPlatform* m_platform;
};

void TestEmergencyService::initTestCase() {
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QCoreApplication::instance();

    m_db = new Database();
    QString testDataPath = QStandardPaths::writableLocation(
        QStandardPaths::TempLocation) + "/test_emergency";
    QDir().mkpath(testDataPath);
    QVERIFY(m_db->open(testDataPath));

    m_platform = new MockPlatform();
    m_service = new EmergencyService(m_db, m_platform);
}

void TestEmergencyService::cleanupTestCase() {
    delete m_service;
    delete m_platform;
    delete m_db;
}

void TestEmergencyService::init() {
    m_platform->callCount = 0;
    m_platform->smsCount = 0;
    m_platform->lastCallNumber.clear();
    m_platform->lastSmsNumber.clear();
    m_platform->lastSmsText.clear();
}

void TestEmergencyService::cleanup() {
    // 清理联系人: deleteContact 按当前列表索引定位, 倒序删除
    const QVariantList contacts = contactsOf(m_service);
    for (int i = contacts.size() - 1; i >= 0; --i) {
        m_service->deleteContact(i);
    }
}

// ============================================================================
// 联系人测试
// ============================================================================

void TestEmergencyService::testAddContact_valid() {
    const QVariantMap r = m_service->addContact("张三", "13800138000", "家人", true);
    QVERIFY2(r.value("ok").toBool(), qPrintable(errText(r)));
    QCOMPARE(m_service->contactCount(), 1);
}

void TestEmergencyService::testAddContact_emptyName() {
    QSignalSpy spy(m_service, &EmergencyService::errorOccurred);
    const QVariantMap r = m_service->addContact("", "13800138000", "家人");
    QVERIFY(!r.value("ok").toBool());
    QCOMPARE(errOfCode(r), QStringLiteral("InvalidArgument"));
    QCOMPARE(spy.count(), 1);
}

void TestEmergencyService::testAddContact_emptyPhone() {
    QSignalSpy spy(m_service, &EmergencyService::errorOccurred);
    const QVariantMap r = m_service->addContact("李四", "", "朋友");
    QVERIFY(!r.value("ok").toBool());
    QCOMPARE(errOfCode(r), QStringLiteral("InvalidArgument"));
    QCOMPARE(spy.count(), 1);
}

void TestEmergencyService::testDeleteContact() {
    QVERIFY(m_service->addContact("王五", "13900139000", "同事").value("ok").toBool());
    QVERIFY(m_service->addContact("赵六", "13700137000", "朋友").value("ok").toBool());
    QCOMPARE(m_service->contactCount(), 2);

    const QVariantMap r = m_service->deleteContact(0);
    QVERIFY2(r.value("ok").toBool(), qPrintable(errText(r)));
    QCOMPARE(m_service->contactCount(), 1);
}

void TestEmergencyService::testDeleteContact_outOfRange() {
    QVERIFY(m_service->addContact("甲", "13800000009", "家人").value("ok").toBool());
    const QVariantMap r = m_service->deleteContact(7);
    QVERIFY(!r.value("ok").toBool());
    QCOMPARE(errOfCode(r), QStringLiteral("InvalidArgument"));
    QCOMPARE(m_service->contactCount(), 1);
}

void TestEmergencyService::testSetPrimary() {
    m_service->addContact("A", "13800000001", "家人", false);
    m_service->addContact("B", "13800000002", "朋友", true);

    QVariantList contacts = contactsOf(m_service);
    int bIndex = -1;
    for (int i = 0; i < contacts.size(); ++i) {
        if (contacts[i].toMap()["name"] == "B") {
            bIndex = i;
            QVERIFY(contacts[i].toMap()["isPrimary"].toBool());
        }
    }
    QVERIFY(bIndex >= 0);

    // 设置 A 为主
    int aIndex = -1;
    for (int i = 0; i < contacts.size(); ++i) {
        if (contacts[i].toMap()["name"] == "A") {
            aIndex = i;
        }
    }
    m_service->setPrimary(aIndex);

    contacts = contactsOf(m_service);
    for (const auto& c : contacts) {
        if (c.toMap()["name"] == "A") {
            QVERIFY(c.toMap()["isPrimary"].toBool());
        } else {
            QVERIFY(!c.toMap()["isPrimary"].toBool());
        }
    }
}

void TestEmergencyService::testContactCount() {
    QVERIFY(m_service->contactCount() == 0);
    m_service->addContact("A", "13800138001", "家人");
    QCOMPARE(m_service->contactCount(), 1);
    m_service->addContact("B", "13800138002", "朋友");
    QCOMPARE(m_service->contactCount(), 2);
}

void TestEmergencyService::testGetContacts() {
    QVERIFY(contactsOf(m_service).isEmpty());
    m_service->addContact("A", "13800138001", "家人", true);
    QVERIFY(!contactsOf(m_service).isEmpty());
}

void TestEmergencyService::testContactLimit() {
    // 添加 5 个联系人
    for (int i = 0; i < 5; ++i) {
        const QVariantMap r = m_service->addContact(
            QString("Contact%1").arg(i),
            QString("1380013800%1").arg(i),
            "test");
        QVERIFY2(r.value("ok").toBool(), qPrintable(errText(r)));
    }
    QCOMPARE(m_service->contactCount(), 5);
    // 第 6 个也允许（不在 App 层强制限制，由 UI 控制）
}

// ============================================================================
// SOS 触发测试
// ============================================================================

void TestEmergencyService::testTriggerSOS() {
    m_service->addContact("A", "13800138001", "家人");

    QSignalSpy spy(m_service, &EmergencyService::sosTriggered);
    m_service->triggerSOS();

    QVERIFY(m_service->isSosActive());
    QCOMPARE(spy.count(), 1);

    // 1.5 秒后发短信（异步）
    QTest::qWait(2000);
    QVERIFY(m_platform->smsCount > 0);

    m_service->cancelSOS();
}

void TestEmergencyService::testTriggerSOS_duplicate() {
    m_service->triggerSOS();
    bool wasActive = m_service->isSosActive();
    m_service->triggerSOS();  // 重复
    QVERIFY(m_service->isSosActive() == wasActive);
    m_service->cancelSOS();
}

void TestEmergencyService::testCancelSOS() {
    m_service->triggerSOS();
    m_service->cancelSOS();
    QVERIFY(!m_service->isSosActive());
}

void TestEmergencyService::testIsSosActive() {
    QVERIFY(!m_service->isSosActive());
    m_service->triggerSOS();
    QVERIFY(m_service->isSosActive());
    m_service->cancelSOS();
    QVERIFY(!m_service->isSosActive());
}

void TestEmergencyService::testSosHistory() {
    m_service->triggerSOS();
    m_service->cancelSOS();
    auto history = m_service->getSosHistory();
    QVERIFY(!history.isEmpty());
}

// ============================================================================
// 拨号测试
// ============================================================================

void TestEmergencyService::testCall120() {
    m_service->call120();
    QCOMPARE(m_platform->lastCallNumber, QString("120"));
    QCOMPARE(m_platform->callCount, 1);
}

void TestEmergencyService::testCall110() {
    m_service->call110();
    QCOMPARE(m_platform->lastCallNumber, QString("110"));
}

void TestEmergencyService::testCall119() {
    m_service->call119();
    QCOMPARE(m_platform->lastCallNumber, QString("119"));
}

void TestEmergencyService::testCallNumber() {
    m_service->callNumber("13800138000");
    QCOMPARE(m_platform->lastCallNumber, QString("13800138000"));
}

void TestEmergencyService::testCallInitiatedSignal() {
    QSignalSpy spy(m_service, &EmergencyService::callInitiated);
    m_service->call120();
    QCOMPARE(spy.count(), 1);
    QList<QVariant> args = spy.takeFirst();
    QCOMPARE(args.at(0).toString(), QString("120"));
    QVERIFY(args.at(1).toBool());
}

// ============================================================================
// 短信测试
// ============================================================================

void TestEmergencyService::testSendSMS() {
    QSignalSpy spy(m_service, &EmergencyService::smsSent);
    m_service->sendSMS("13800138000", "test");
    QCOMPARE(m_platform->lastSmsNumber, QString("13800138000"));
    QCOMPARE(m_platform->lastSmsText, QString("test"));
    QCOMPARE(spy.count(), 1);
}

void TestEmergencyService::testSendSosSMSToAll() {
    m_service->addContact("A", "13800138001", "家人");
    m_service->addContact("B", "13800138002", "朋友");
    m_service->sendSosSMSToAll();
    QCOMPARE(m_platform->smsCount, 2);
}

void TestEmergencyService::testSmsContainsGPS() {
    QString msg = m_service->formatLocationMessage(39.9087, 116.3975);
    QVERIFY(msg.contains("39.9087"));
    QVERIFY(msg.contains("116.3975"));
    QVERIFY(msg.contains("紧急"));
}

QTEST_MAIN(TestEmergencyService)
#include "test_emergency_service.moc"
