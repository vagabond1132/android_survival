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
#include <QDateTime>
#include <QGeoCoordinate>
#include <QGeoPositionInfo>
#include <cmath>    // std::isnan
#include <limits>   // quiet_NaN

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

// JNI 那条路的入口是私有 Q_INVOKABLE (只给 Java 侧 QMetaObject::invokeMethod 用),
// 测试同样只能走 metaobject.
// timeMs < 0 = "现在" (Java 的 Location.getTime() 恒有值, 短信里那条读数不该被标成旧的);
// 要测"缓存了几小时/几天前的位置"就显式传一个旧时刻.
void feedJavaLocation(EmergencyService* s, double lat, double lon,
                      double acc, double alt, qint64 timeMs = -1) {
    const qint64 t = timeMs >= 0 ? timeMs : QDateTime::currentMSecsSinceEpoch();
    QMetaObject::invokeMethod(s, "onJavaLocationUpdated",
        Q_ARG(double, lat), Q_ARG(double, lon),
        Q_ARG(double, acc), Q_ARG(double, alt), Q_ARG(qint64, t));
}

const double kNaN = std::numeric_limits<double>::quiet_NaN();

// Qt 定位源那条路 (onPositionUpdated) 是私有槽, 测试同样只能走 metaobject.
// 它和 Java 桥的差别就是这条测试要验的: 只有 QGeoPositionInfo 带 Direction,
// 也就是"行进航向"这第二个朝向来源只能从这条路进来.
// 精度/航向传 NaN = "后端没给这个属性" → 干脆不 setAttribute, 走 hasAttribute 为假的分支.
void feedQtFix(EmergencyService* s, double lat, double lon,
               double acc, double alt, double course, qint64 timeMs = -1) {
    const qint64 t = timeMs >= 0 ? timeMs : QDateTime::currentMSecsSinceEpoch();
    QGeoPositionInfo info;
    info.setCoordinate(QGeoCoordinate(lat, lon, alt));
    info.setTimestamp(QDateTime::fromMSecsSinceEpoch(t));
    if (std::isfinite(acc) && acc > 0) {
        info.setAttribute(QGeoPositionInfo::HorizontalAccuracy, acc);
    }
    if (std::isfinite(course)) info.setAttribute(QGeoPositionInfo::Direction, course);
    QMetaObject::invokeMethod(s, "onPositionUpdated", Q_ARG(QGeoPositionInfo, info));
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

    // 定位读数测试 (#98: 精度/海拔未知必须是 NaN, 不能是 0)
    void testSmsAccuracyUnknownIsNotZero();
    void testJavaLocationCarriesAltitude();
    void testJavaLocationNaNAltitudeStaysUnknown();
    // 定位读数过时要在短信里写明 (#98 复盘: "时间:" 是发送时刻, 不是位置时刻)
    void testFreshLocationHasNoStaleNote();
    void testStaleLocationSaysHowOld();
    // 两条定位路混合上报时的取舍 ("更好或更新才覆盖") —— 精度显示上不去的真因
    void testLocationAcceptsBetterFix();
    void testLocationSkipsCoarseFixWhileFresh();
    void testLocationAllowsNormalJitter();
    void testLocationAcceptsCoarseFixWhenStale();
    void testLocationUnknownAccuracyDoesNotClobberFreshKnown();
    // 2026-10-26「精度到 1 m」: 静止多帧平均 + 报告精度的底线 + 第二朝向来源
    void testStationaryFixesAreAveraged();
    void testMovingFrameIsNotDraggedBack();
    void testCoarseFixDoesNotPoisonPool();
    void testCourseOnlyFromQtSource();

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

// 还没定位到时精度是 NaN. 短信里绝不能写"精度：0.0 米" —— 搜救队按零误差规划接近
// 方式, 那是假承诺; 也不能凭空写一个"海拔：0 米"(会被读成海平面).
// 用新实例而不是 m_service: 它没被任何别的测试喂过定位, 断言跟用例执行顺序无关.
void TestEmergencyService::testSmsAccuracyUnknownIsNotZero() {
    EmergencyService fresh(m_db, m_platform);
    QVERIFY(std::isnan(fresh.currentAccuracy()));
    QVERIFY(std::isnan(fresh.currentAltitude()));
    QVERIFY(fresh.getCurrentLocation().isEmpty());

    const QString msg = fresh.formatLocationMessage(39.9087, 116.3975);
    QVERIFY(msg.contains("精度：未知"));
    QVERIFY(!msg.contains("精度：0"));
    QVERIFY(!msg.contains("海拔："));
}

// Java → JNI 这条路以前只传 lat/lon/acc/time, 海拔永远是空 (2026-10-22 补 altitude).
void TestEmergencyService::testJavaLocationCarriesAltitude() {
    QSignalSpy spy(m_service, &EmergencyService::locationUpdated);
    feedJavaLocation(m_service, 39.9087, 116.3975, 12.0, 1180.0);
    QCOMPARE(spy.count(), 1);
    QCOMPARE(m_service->currentAccuracy(), 12.0);
    QCOMPARE(m_service->currentAltitude(), 1180.0);

    const QString msg = m_service->formatLocationMessage(39.9087, 116.3975);
    QVERIFY(msg.contains("精度：12.0 米"));
    QVERIFY(msg.contains("海拔：1180 米"));
    QVERIFY(m_service->isLocationValid());

    const QVariantMap loc = m_service->getCurrentLocation();
    QCOMPARE(loc.value("accuracy").toDouble(), 12.0);
    QCOMPARE(loc.value("altitude").toDouble(), 1180.0);
}

// 下一条定位没带高程时, 不许继续显示上一条的海拔 (用户会当成当前值).
void TestEmergencyService::testJavaLocationNaNAltitudeStaysUnknown() {
    feedJavaLocation(m_service, 40.0, 116.0, 5.0, kNaN);
    QVERIFY(std::isnan(m_service->currentAltitude()));
    QCOMPARE(m_service->currentAccuracy(), 5.0);

    const QString msg = m_service->formatLocationMessage(40.0, 116.0);
    QVERIFY(msg.contains("精度：5.0 米"));
    QVERIFY(!msg.contains("海拔："));
}

// 刚测到的读数不该被标成旧的 (否则"⚠️ 不是实时位置"天天都在, 等于没有).
void TestEmergencyService::testFreshLocationHasNoStaleNote() {
    EmergencyService fresh(m_db, m_platform);
    feedJavaLocation(&fresh, 39.9087, 116.3975, 12.0, 1180.0);
    const QString msg = fresh.formatLocationMessage(39.9087, 116.3975);
    QVERIFY2(!msg.contains("不是实时位置"), qPrintable(msg));
}

// 缓存了几小时/几天前的位置垫底时, 短信必须自己说清"这是几点采的、过了多久" ——
// 搜救队按短信里的"时间:"(发送时刻)规划接近方式, 拿旧坐标当实时位置比不发更糟.
void TestEmergencyService::testStaleLocationSaysHowOld() {
    const qint64 now = QDateTime::currentMSecsSinceEpoch();

    EmergencyService tenMin(m_db, m_platform);
    feedJavaLocation(&tenMin, 39.9087, 116.3975, 12.0, 1180.0, now - 10LL * 60 * 1000);
    const QString m1 = tenMin.formatLocationMessage(39.9087, 116.3975);
    QVERIFY2(m1.contains("不是实时位置"), qPrintable(m1));
    QVERIFY2(m1.contains("已 10 分钟"), qPrintable(m1));

    EmergencyService twoDays(m_db, m_platform);
    feedJavaLocation(&twoDays, 39.9087, 116.3975, 12.0, 1180.0, now - 50LL * 60 * 60 * 1000);
    const QString m2 = twoDays.formatLocationMessage(39.9087, 116.3975);
    QVERIFY2(m2.contains("已 2 天"), qPrintable(m2));
    // 天级读数必须带上"月-日": 只写时分, 三天前和昨天看起来一样
    const QString stamp = QDateTime::fromMSecsSinceEpoch(now - 50LL * 60 * 60 * 1000)
                              .toString("MM-dd HH:mm");
    QVERIFY2(m2.contains(stamp), qPrintable(m2));
}

// ---- 定位质量门 -----------------------------------------------------------
// 真机同时有 Qt 卫星源与 Java 网络源在往同一个 currentLocation 里写, 谁最后到
// 谁赢 → 仪表在 ±8 m 与 ±400 m 之间跳、短信可能带着粗坐标出去.
// 下面的断言就是"更好或更新才覆盖"这四条边界.

void TestEmergencyService::testLocationAcceptsBetterFix() {
    EmergencyService svc(m_db, m_platform);
    feedJavaLocation(&svc, 36.6749, 117.1239, 42.0, kNaN);
    feedJavaLocation(&svc, 36.6800, 117.1300, 8.0, 120.0);

    QCOMPARE(svc.currentAccuracy(), 8.0);
    QCOMPARE(svc.currentAltitude(), 120.0);
    QCOMPARE(svc.getCurrentLocation().value("lat").toDouble(), 36.6800);
}

// 粗的那条不但要留在位置上, 连 locationUpdated 都不许发 —— 否则仪表照样闪一下.
void TestEmergencyService::testLocationSkipsCoarseFixWhileFresh() {
    EmergencyService svc(m_db, m_platform);
    QSignalSpy spy(&svc, &EmergencyService::locationUpdated);
    feedJavaLocation(&svc, 36.6749, 117.1239, 8.0, 120.0);
    feedJavaLocation(&svc, 36.7000, 117.2000, 400.0, 900.0);

    QCOMPARE(spy.count(), 1);
    QCOMPARE(svc.currentAccuracy(), 8.0);
    QCOMPARE(svc.getCurrentLocation().value("lat").toDouble(), 36.6749);
    QCOMPARE(svc.currentAltitude(), 120.0);
}

// 同一颗 GPS 连续两次的正常抖动 (10~20%) 必须放行, 不然人是会走的, 位置冻住更糟.
void TestEmergencyService::testLocationAllowsNormalJitter() {
    EmergencyService svc(m_db, m_platform);
    feedJavaLocation(&svc, 36.6749, 117.1239, 10.0, 120.0);
    feedJavaLocation(&svc, 36.6750, 117.1240, 14.0, 121.0);

    QCOMPARE(svc.currentAccuracy(), 14.0);
    QCOMPARE(svc.getCurrentLocation().value("lat").toDouble(), 36.6750);
}

// 保鲜期外无条件接受: 手里的点已经两分钟没动了, 宁可换成一条粗的实时位置,
// 也不能把人钉在一个几分钟前的旧坐标上 (SOS 短信里"错"比"粗"危险).
void TestEmergencyService::testLocationAcceptsCoarseFixWhenStale() {
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    EmergencyService svc(m_db, m_platform);
    feedJavaLocation(&svc, 36.6749, 117.1239, 8.0, 120.0, now - 120LL * 1000);
    feedJavaLocation(&svc, 36.7000, 117.2000, 400.0, 900.0, now);

    QCOMPARE(svc.currentAccuracy(), 400.0);
    QCOMPARE(svc.getCurrentLocation().value("lat").toDouble(), 36.7000);
}

// 精度"不知道"的读数没有资格覆盖一个保鲜期内的已知点 (2026-10-26 改的这条判据).
// 原来判据里带 std::isfinite(accuracy), NaN 那条永远短路通过 → 仪表上的 ±8 m 天天
// 被一条没有 ± 的读数打回"精度：未知". 代价是位置最多滞后 60 秒 —— 超过保鲜期
// 就无条件接受, 不能为了一个好看的 ± 把人钉在几分钟前的旧坐标上.
void TestEmergencyService::testLocationUnknownAccuracyDoesNotClobberFreshKnown() {
    // A) 手里的点还在 60 秒保鲜期内: 没有 ± 的那条没有资格覆盖它
    EmergencyService held(m_db, m_platform);
    QSignalSpy spy(&held, &EmergencyService::locationUpdated);
    feedJavaLocation(&held, 36.6749, 117.1239, 8.0, 120.0);
    feedJavaLocation(&held, 36.6750, 117.1240, kNaN, kNaN);

    QCOMPARE(spy.count(), 1);                         // 未知精度那条连信号都不发
    QCOMPARE(held.currentAccuracy(), 8.0);            // ± 不许被打回未知
    QCOMPARE(held.getCurrentLocation().value("lat").toDouble(), 36.6749);

    // B) 配对断言: 判据看的是**手里那点**的年龄 (不是 incoming 的时刻). 手里那条
    //   已经两分钟没动 → 同一条没有 ± 的读数必须被收, 人不能冻在一个旧坐标上.
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    EmergencyService stale(m_db, m_platform);
    feedJavaLocation(&stale, 36.6749, 117.1239, 8.0, 120.0, now - 120LL * 1000);
    feedJavaLocation(&stale, 36.6750, 117.1240, kNaN, kNaN, now);

    QCOMPARE(stale.getCurrentLocation().value("lat").toDouble(), 36.6750);
    QVERIFY(std::isnan(stale.currentAccuracy()));
    QVERIFY(std::isnan(stale.currentAltitude()));     // 不拿上一条的海拔充数
    QVERIFY(stale.formatLocationMessage(36.6750, 117.1240).contains("精度：未知"));
}

// ---- 静止多帧平均 (2026-10-26「精度到 1 m」) --------------------------------
// 单帧 GNSS 在手机上一般 2~5 m, 静止时按 1/σ² 平均能把落点压到 1~2 m.
// 关键是**报告出去的 ±** 只取池内最好那一帧自己量出来的 σ: 1 Hz 的相邻帧高度相关,
// σ/√N 没有硬件依据, 写进短信就是假承诺.

void TestEmergencyService::testStationaryFixesAreAveraged() {
    EmergencyService svc(m_db, m_platform);
    // 三帧都在容差 (max(3 m, 池内最好 σ)) 之内 = 人没动, σ = 5 / 4 / 6
    feedJavaLocation(&svc, 36.674900, 117.123900, 5.0, kNaN);
    feedJavaLocation(&svc, 36.674910, 117.123900, 4.0, kNaN);   // ≈1.1 m 抖动
    feedJavaLocation(&svc, 36.674905, 117.123900, 6.0, kNaN);   // ≈0.6 m 抖动

    const double lat = svc.getCurrentLocation().value("lat").toDouble();
    QVERIFY2(std::fabs(lat - 36.674905) > 1e-9,
             qPrintable(QStringLiteral("落点等于最后一帧 (%1), 平均没有生效").arg(lat, 0, 'f', 7)));
    QVERIFY2(lat > 36.674890 && lat < 36.674920,
             qPrintable(QStringLiteral("均值跑出这三帧的包络: %1").arg(lat, 0, 'f', 7)));
    QCOMPARE(svc.currentAccuracy(), 4.0);   // = 池内最好那一帧自己的 σ
    // 正向配对: 不许出现 σ/√3 = 2.31 那种"平均出来的精度"
    QVERIFY2(svc.currentAccuracy() >= 4.0,
             qPrintable(QStringLiteral("报告精度 %1 m 优于实测最好一帧 4 m, 是统计幻觉")
                            .arg(svc.currentAccuracy())));
}

// 走动时平均绝不能把点拖在身后: 每帧跨出容差 → 清池, 落点就是当前这一帧.
void TestEmergencyService::testMovingFrameIsNotDraggedBack() {
    EmergencyService svc(m_db, m_platform);
    feedJavaLocation(&svc, 36.674900, 117.123900, 3.0, kNaN);
    feedJavaLocation(&svc, 36.675000, 117.123900, 3.0, kNaN);   // ≈11 m, 远超容差 3 m
    feedJavaLocation(&svc, 36.675100, 117.123900, 3.0, kNaN);   // 再 ≈11 m

    QCOMPARE(svc.getCurrentLocation().value("lat").toDouble(), 36.675100);
    QCOMPARE(svc.currentAccuracy(), 3.0);
}

// 网络级粗帧 (±40 m, 比 kRefineMaxAccM 粗) 不进池: 它自己透传, 还要把池清空,
// 否则下一条好帧会和它平均, 落点被拽向那条粗读数.
void TestEmergencyService::testCoarseFixDoesNotPoisonPool() {
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    EmergencyService svc(m_db, m_platform);
    // 第一条用旧时刻: 老到不进池, 但也把已有点顶掉 (保鲜期外无条件接受)
    feedJavaLocation(&svc, 36.674900, 117.123900, 5.0, kNaN, now - 120LL * 1000);
    feedJavaLocation(&svc, 36.680000, 117.130000, 40.0, kNaN, now);
    feedJavaLocation(&svc, 36.675000, 117.124000, 6.0, kNaN, now);

    // 若那条 ±40 m 还在池里, 这里的落点会被拉向 36.68 —— 必须严格等于当前帧
    QCOMPARE(svc.getCurrentLocation().value("lat").toDouble(), 36.675000);
    QCOMPARE(svc.currentAccuracy(), 6.0);
}

// 第二朝向来源: 这台机的 QCompass 一整轮没给过有效读数 (用户报"蓝点没有方向 /
// 右上方位不动"). Direction = Android getBearing(), 只有 Qt 那条源带得动;
// Java 桥没有这个属性 → 必须是 NaN, 不能写成 0 (0° 会被画成一支指北的针).
void TestEmergencyService::testCourseOnlyFromQtSource() {
    EmergencyService svc(m_db, m_platform);
    QVERIFY(std::isnan(svc.currentCourse()));

    feedJavaLocation(&svc, 36.6749, 117.1239, 8.0, kNaN);
    QVERIFY2(std::isnan(svc.currentCourse()),
             "Java 桥没有航向属性, 不许沿用上一条或补一个 0°");

    feedQtFix(&svc, 36.6750, 117.1240, 7.0, kNaN, 215.0);
    QCOMPARE(svc.currentCourse(), 215.0);

    // 静止: 后端不给 Direction → 跟着被接受的这一帧回到 NaN, 不能留 215° 充数
    feedQtFix(&svc, 36.6750, 117.1240, 6.0, kNaN, kNaN);
    QVERIFY2(std::isnan(svc.currentCourse()),
             qPrintable(QStringLiteral("航向沿用了上一条 (%1)").arg(svc.currentCourse())));
}

QTEST_MAIN(TestEmergencyService)
#include "test_emergency_service.moc"
