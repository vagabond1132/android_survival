/**
 * @file EmergencyService.cpp
 */

#include "EmergencyService.h"
#include "../common/DbHelper.h"  // 2026-09-21 阶段 L2.2
#include "../core/Database.h"
#include "../core/Logger.h"
#include "../core/Result.h"
#include "../core/ServiceErrors.h"
#include "../core/internal/QmlResultBridge.h"
#include "../platform/PlatformInterface.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QDateTime>
#include <QTimer>
#include <QStandardPaths>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QGeoPositionInfo>
#include <QGeoPositionInfoSource>
#include <QMetaObject>

#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <jni.h>
#endif

namespace outdoor {

// 静态单例指针初始化
EmergencyService* EmergencyService::s_instance = nullptr;

EmergencyService::EmergencyService(Database* db, PlatformInterface* platform,
                                     QObject* parent)
    : ServiceBase(db, "EmergencyService", parent), m_platform(platform) {
    // 设置单例, 供 JNI 桥接找到当前实例
    s_instance = this;
    // 创建 GPS 数据源(Android 上自动用系统定位)
    m_geoSource = QGeoPositionInfoSource::createDefaultSource(this);
    if (m_geoSource) {
        connect(m_geoSource, &QGeoPositionInfoSource::positionUpdated,
                this, &EmergencyService::onPositionUpdated);
        connect(m_geoSource, &QGeoPositionInfoSource::errorOccurred,
                this, [](QGeoPositionInfoSource::Error err) {
            Logger::warn(QString("GPS error: %1").arg(int(err)));
        });
        Logger::info("GPS source ready");
    } else {
        Logger::warn("No GPS source available on this device");
    }

    // 启动时检查表
    if (m_db && m_db->isOpen(Database::Name::User)) {
        // 2026-09-21 阶段 L2.2: 切 DbHelper::execDdl (内含错误日志)
        // 2026-10-16: 权威 schema 在 Database::createSchema(Name::User), 这里只是
        // "Database 还没 migrate 过" 的兜底. 两处字段必须一致 —— 之前正是因为
        // Database 那份漏了 is_deleted/updated_at 且先跑, 让本函数的 CREATE 空转,
        // 全表读取静默失败. 改表时两边一起改.
        QSqlQuery q(m_db->get(Database::Name::User));
        DbHelper::execDdl(q, R"(
            CREATE TABLE IF NOT EXISTS emergency_contacts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                phone TEXT NOT NULL,
                relation TEXT,
                is_primary INTEGER DEFAULT 0,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now')),
                is_deleted INTEGER DEFAULT 0
            )
        )", "EmergencyService::ctor.emergency_contacts");

        DbHelper::execDdl(q, R"(
            CREATE TABLE IF NOT EXISTS sos_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                triggered_at TEXT NOT NULL,
                location_lat REAL,
                location_lon REAL,
                accuracy REAL,
                actions TEXT,
                resolved_at TEXT
            )
        )", "EmergencyService::ctor.sos_history");
    }
}

EmergencyService::~EmergencyService() {
    stopLocationUpdate();
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

// 2026-09-21: Phase 5 批次 3 - getContacts 返回 Result. DB 错误走 Result 包装
QVariantMap EmergencyService::getContacts() const {
    using namespace outdoor::internal;
    const char* ctx = "EmergencyService::getContacts";

    if (!m_db || !m_db->isOpen(Database::Name::User)) {
        return toQVariant(Ok(QVariantList{}));  // 无 DB 不视为错误, 直接返回空
    }

    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectList (失败已 log)
    QSqlQuery q(m_db->get(Database::Name::User));
    QVariantList list = DbHelper::selectList(q,
            "SELECT id, name, phone, relation, is_primary FROM emergency_contacts "
            "WHERE is_deleted = 0 ORDER BY is_primary DESC, id ASC", {},
            ctx,
            [](const QSqlQuery& q) -> QVariantMap {
                QVariantMap m;
                m["id"] = q.value(0).toInt();
                m["name"] = q.value(1).toString();
                m["phone"] = q.value(2).toString();
                m["relation"] = q.value(3).toString();
                m["isPrimary"] = q.value(4).toBool();
                return m;
            });
    return toQVariant(Ok(list));
}

QVariantMap EmergencyService::addContact(const QString& name, const QString& phone,
                                          const QString& relation, bool isPrimary) {
    using namespace outdoor::internal;
    const char* ctx = "EmergencyService::addContact";

    if (name.isEmpty() || phone.isEmpty()) {
        emit errorOccurred("姓名和电话不能为空");
        return fail(ServiceErrorCode::InvalidArgument,
                    QStringLiteral("姓名和电话不能为空"), ctx);
    }

    if (auto e = dbOpenCheck(m_db, Database::Name::User, ctx)) {
        emit errorOccurred("数据库未打开");
        return *e;
    }

    QSqlDatabase db = m_db->get(Database::Name::User);
    QSqlQuery q(db);

    // 如果是主联系人，先取消其他主联系人
    // 2026-09-21 阶段 L2.2: 切 DbHelper::execDml (无 binds)
    if (isPrimary) {
        if (DbHelper::execDml(q,
                "UPDATE emergency_contacts SET is_primary = 0 WHERE is_deleted = 0", {},
                "EmergencyService::addContact.clearPrimary")
            != DmlResult::Ok) {
            // 不阻断, 继续尝试 INSERT
            Logger::warn("EmergencyService::addContact: clearPrimary 失败,继续 INSERT");
        }
    }

    // 2026-09-21 阶段 L2.2: 切 DbHelper::execDmlPositional
    auto rc = DbHelper::execDmlPositional(q,
        "INSERT INTO emergency_contacts (name, phone, relation, is_primary) "
        "VALUES (?, ?, ?, ?)",
        {name, phone, relation, isPrimary ? 1 : 0},
        "EmergencyService::addContact");
    if (rc != DmlResult::Ok) {
        const QString err = q.lastError().text();
        emit errorOccurred(QStringLiteral("添加失败: %1").arg(err));
        return dbErr(rc, db, ctx);  // log + return fail
    }

    emit contactsChanged();
    Logger::info("Emergency contact added: " + name);
    return okVoid();
}

QVariantMap EmergencyService::deleteContact(int index) {
    using namespace outdoor::internal;
    const char* ctx = "EmergencyService::deleteContact";

    // 2026-09-21: getContacts 切 Result, 从 .value 解出 list
    QVariantList list = getContacts().value("value").toList();
    if (index < 0 || index >= list.size()) {
        return fail(ServiceErrorCode::InvalidArgument,
                    QStringLiteral("索引越界 (index=%1, size=%2)").arg(index).arg(list.size()),
                    ctx);
    }

    int id = list[index].toMap()["id"].toInt();
    if (id <= 0) {
        return fail(ServiceErrorCode::NotFound,
                    QStringLiteral("联系人 id 无效"), ctx);
    }

    // 2026-09-21 阶段 L2.2: 切 DbHelper::execDmlPositional
    QSqlDatabase db = m_db->get(Database::Name::User);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        "UPDATE emergency_contacts SET is_deleted = 1 WHERE id = ?",
        {id},
        "EmergencyService::deleteContact");
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }
    emit contactsChanged();
    return okVoid();
}

QVariantMap EmergencyService::updateContact(int index, const QString& name,
                                              const QString& phone,
                                              const QString& relation, bool isPrimary) {
    using namespace outdoor::internal;
    const char* ctx = "EmergencyService::updateContact";

    // 2026-09-21: getContacts 切 Result, 从 .value 解出 list
    QVariantList list = getContacts().value("value").toList();
    if (index < 0 || index >= list.size()) {
        return fail(ServiceErrorCode::InvalidArgument,
                    QStringLiteral("索引越界 (index=%1, size=%2)").arg(index).arg(list.size()),
                    ctx);
    }

    int id = list[index].toMap()["id"].toInt();
    if (id <= 0) {
        return fail(ServiceErrorCode::NotFound,
                    QStringLiteral("联系人 id 无效"), ctx);
    }

    // 2026-09-21 阶段 L2.2: 切 DbHelper::execDml / execDmlPositional
    // 旧实现 q0.exec 字符串拼接 id (SQL 注入风险), 改用 positional bind
    QSqlDatabase db = m_db->get(Database::Name::User);
    QSqlQuery q(db);

    if (isPrimary) {
        DbHelper::execDmlPositional(q,
            "UPDATE emergency_contacts SET is_primary = 0 WHERE id != ? AND is_deleted = 0",
            {id},
            "EmergencyService::updateContact.clearPrimary");
    }

    auto rc = DbHelper::execDmlPositional(q,
        "UPDATE emergency_contacts SET name=?, phone=?, relation=?, "
        "is_primary=?, updated_at=datetime('now') WHERE id=?",
        {name, phone, relation, isPrimary ? 1 : 0, id},
        "EmergencyService::updateContact");
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }
    emit contactsChanged();
    return okVoid();
}

void EmergencyService::setPrimary(int index) {
    // 2026-09-21: getContacts 切 Result, 从 .value 解出 list
    QVariantList list = getContacts().value("value").toList();
    if (index < 0 || index >= list.size()) return;

    int id = list[index].toMap()["id"].toInt();
    QSqlDatabase db = m_db->get(Database::Name::User);
    if (!db.transaction()) {
        Logger::error("setPrimary: transaction begin failed");
        return;
    }
    // 2026-09-21 阶段 L2.2: 切 DbHelper::execDml / execDmlPositional
    QSqlQuery q(db);
    DmlResult rc1 = DbHelper::execDml(q,
        "UPDATE emergency_contacts SET is_primary = 0 WHERE is_deleted = 0", {},
        "EmergencyService::setPrimary.clear");
    DmlResult rc2 = DbHelper::execDmlPositional(q,
        "UPDATE emergency_contacts SET is_primary = 1 WHERE id = ?",
        {id},
        "EmergencyService::setPrimary.set");
    if (rc1 != DmlResult::Ok || rc2 != DmlResult::Ok) {
        db.rollback();
        Logger::error(QString("setPrimary failed: %1").arg(q.lastError().text()));
        return;
    }
    if (!db.commit()) {
        Logger::error("setPrimary: commit failed");
        return;
    }

    emit contactsChanged();
}

int EmergencyService::contactCount() const {
    // 2026-09-21: getContacts 切 Result, 从 .value 解出 list
    return getContacts().value("value").toList().size();
}

void EmergencyService::triggerSOS() {
    if (m_sosActive) {
        Logger::warn("SOS already active");
        return;
    }

    Logger::info("=== SOS TRIGGERED ===");
    m_sosActive = true;
    emit sosStateChanged();
    emit sosTriggered(QDateTime::currentDateTime());

    // 1. 启动位置更新
    startLocationUpdate();

    // 2. 拨打 120
    call120();

    // 3. 延迟 1 秒后发送短信（让位置稳定）
    QTimer::singleShot(1500, this, [this]() {
        sendSosSMSToAll();
    });

    recordSosEvent("triggered", true);
}

void EmergencyService::cancelSOS() {
    if (!m_sosActive) return;
    Logger::info("SOS cancelled by user");
    m_sosActive = false;
    stopLocationUpdate();
    emit sosStateChanged();
    emit sosCancelled();
    recordSosEvent("cancelled", true);
}

void EmergencyService::call120() {
    if (!m_platform) {
        emit errorOccurred("平台服务未初始化");
        return;
    }
    bool ok = m_platform->makePhoneCall("120");
    emit callInitiated("120", ok);
    recordSosEvent("call_120", ok);
}

void EmergencyService::call110() {
    if (!m_platform) return;
    bool ok = m_platform->makePhoneCall("110");
    emit callInitiated("110", ok);
}

void EmergencyService::call119() {
    if (!m_platform) return;
    bool ok = m_platform->makePhoneCall("119");
    emit callInitiated("119", ok);
}

void EmergencyService::callNumber(const QString& number) {
    if (!m_platform || number.isEmpty()) {
        Logger::warn(QString("callNumber failed: %1").arg(m_platform ? "empty number" : "no platform"));
        emit callInitiated(number, false);
        return;
    }
    bool ok = m_platform->makePhoneCall(number);
    if (!ok) {
        Logger::warn(QString("callNumber failed for: %1").arg(number));
    }
    emit callInitiated(number, ok);
}

// 2026-09-21: 阶段 L3.6 - sendSosSMSToAll 切 Result<bool>
QVariantMap EmergencyService::sendSosSMSToAll() {
    using namespace outdoor::internal;
    const char* ctx = "EmergencyService::sendSosSMSToAll";

    // 2026-09-21: getContacts 切 Result, 从 .value 解出 list
    QVariantList contacts = getContacts().value("value").toList();
    if (contacts.isEmpty()) {
        return toQVariant(Err<bool>(ServiceErrorCode::InvalidArgument,
                                      QStringLiteral("无紧急联系人"), ctx));
    }

    // 主动请求一次最新位置(超时 8 秒)
    if (m_geoSource) {
        m_geoSource->requestUpdate(8000);
    }

    QString message = formatLocationMessage(
        m_currentLocation.latitude(),
        m_currentLocation.longitude());

    int successCount = 0;
    for (const auto& c : contacts) {
        QString phone = c.toMap()["phone"].toString();
        QVariantMap r = sendSMS(phone, message);
        if (isOk(r)) {
            successCount++;
        }
    }

    Logger::info(QString("SOS SMS sent: %1/%2 (location valid: %3)")
                      .arg(successCount)
                      .arg(contacts.size())
                      .arg(isLocationValid() ? "yes" : "no"));
    if (successCount == 0) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                      QStringLiteral("所有短信发送失败"), ctx));
    }
    return toQVariant(Ok(true));
}

// 2026-09-21: 阶段 L3.6 - sendSMS 切 Result<bool>
QVariantMap EmergencyService::sendSMS(const QString& number, const QString& text) {
    using namespace outdoor::internal;
    const char* ctx = "EmergencyService::sendSMS";

    if (!m_platform) {
        return toQVariant(Err<bool>(ServiceErrorCode::InternalError,
                                      QStringLiteral("平台服务未初始化"), ctx));
    }
    bool ok = m_platform->sendSMS(number, text);
    if (!ok) {
        Logger::warn(QString("sendSMS failed for: %1").arg(number));
    }
    emit smsSent(number, ok);
    return ok ? toQVariant(Ok(true))
              : toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                       QStringLiteral("短信发送失败"), ctx));
}

QVariantMap EmergencyService::getCurrentLocation() {
    QVariantMap result;
    if (m_currentLocation.isValid()) {
        result["lat"] = m_currentLocation.latitude();
        result["lon"] = m_currentLocation.longitude();
        result["accuracy"] = m_accuracy;
        result["altitude"] = m_elevation;  // NaN = 本次定位没带高程
    }
    return result;
}

QString EmergencyService::formatLocationMessage(double lat, double lon) {
    QString coordPart = QString("纬度 %1, 经度 %2")
        .arg(lat, 0, 'f', 6)
        .arg(lon, 0, 'f', 6);

    QString accuracyPart = QString("精度：%1 米").arg(m_accuracy, 0, 'f', 1);

    QString mapLinks = QString(
        "地图链接:\n"
        "  高德: https://uri.amap.com/marker?position=%1,%2\n"
        "  Google: https://maps.google.com/?q=%1,%2")
        .arg(lat, 0, 'f', 6)
        .arg(lon, 0, 'f', 6);

    if (lat == 0.0 && lon == 0.0) {
        // GPS 位置无效(0/0)
        return QString("【紧急求救】我在荒野手册 App 中触发 SOS。\n"
                       "⚠️ GPS 位置未获取到,请尽快联系!\n"
                       "时间:%1\n"
                       "请尽快联系或救援!")
            .arg(QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss"));
    }

    return QString("【紧急求救】我在荒野手册 App 中触发 SOS。\n"
                   "位置:%1\n"
                   "%2\n"
                   "时间:%3\n"
                   "%4\n"
                   "请尽快联系或救援!")
        .arg(coordPart)
        .arg(accuracyPart)
        .arg(QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss"))
        .arg(mapLinks);
}

QVariantList EmergencyService::getSosHistory(int limit) {
    if (!m_db || !m_db->isOpen(Database::Name::User)) return {};

    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectList
    QSqlQuery q(m_db->get(Database::Name::User));
    return DbHelper::selectList(q,
            "SELECT id, triggered_at, location_lat, location_lon, "
            "actions, resolved_at FROM sos_history "
            "ORDER BY triggered_at DESC LIMIT ?",
            {limit},
            "EmergencyService::getSosHistory",
            [](const QSqlQuery& q) -> QVariantMap {
                QVariantMap m;
                m["id"] = q.value(0).toInt();
                m["triggeredAt"] = q.value(1).toString();
                m["lat"] = q.value(2).toDouble();
                m["lon"] = q.value(3).toDouble();
                m["actions"] = q.value(4).toString();
                m["resolvedAt"] = q.value(5).toString();
                return m;
            });
}

void EmergencyService::recordSosEvent(const QString& action, bool success,
                                         const QString& detail) {
    if (!m_db || !m_db->isOpen(Database::Name::User)) return;

    // 2026-09-21 阶段 L2.2: 切 DbHelper::execDmlPositional
    QSqlDatabase db = m_db->get(Database::Name::User);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        "INSERT INTO sos_history (triggered_at, location_lat, location_lon, "
        "accuracy, actions) VALUES (?, ?, ?, ?, ?)",
        {QDateTime::currentDateTime().toString(Qt::ISODate),
         m_currentLocation.latitude(),
         m_currentLocation.longitude(),
         m_accuracy,
         QString("{\"action\":\"%1\",\"success\":%2,\"detail\":\"%3\"}")
             .arg(action)
             .arg(success ? "true" : "false")
             .arg(detail)},
        "EmergencyService::recordSosEvent");
    if (rc != DmlResult::Ok) {
        // 失败已 log
    }
}

void EmergencyService::startLocationUpdate() {
    if (!m_platform) return;

    m_platform->requestPermission("android.permission.ACCESS_FINE_LOCATION",
        [this](bool granted) {
            if (!granted) {
                Logger::warn("Fine location denied, trying coarse");
                m_platform->requestPermission("android.permission.ACCESS_COARSE_LOCATION",
                    [this](bool granted2) {
                        if (granted2) {
                            Logger::info("Coarse location granted");
                            this->requestLocationUpdate();
                        } else {
                            emit errorOccurred("未授予位置权限,SOS GPS 链接将不可用");
                        }
                    });
                return;
            }
            Logger::info("Location permission granted, starting GPS updates");
            this->requestLocationUpdate();
        });
}

void EmergencyService::stopLocationUpdate() {
    if (m_geoSource) {
        m_geoSource->stopUpdates();
        Logger::info("GPS updates stopped");
    }
}

void EmergencyService::requestLocationUpdate() {
    if (!m_geoSource) {
        emit errorOccurred("设备无 GPS 模块");
        return;
    }
    // 10 秒一次,SOS 场景够用,耗电可控
    m_geoSource->setUpdateInterval(10000);
    m_geoSource->startUpdates();
    // 立即请求单次更新
    m_geoSource->requestUpdate(10000);
    Logger::info("GPS update started, interval 10s");
}

void EmergencyService::onPositionUpdated(const QGeoPositionInfo& info) {
    if (!info.isValid()) return;
    QGeoCoordinate coord = info.coordinate();
    if (!coord.isValid()) return;

    m_currentLocation = coord;
    m_accuracy = info.hasAttribute(QGeoPositionInfo::HorizontalAccuracy)
                     ? info.attribute(QGeoPositionInfo::HorizontalAccuracy)
                     : 0;
    // 2026-10-20: ①营地/⑤求助 的仪表要读海拔. Qt 6.7 的 QGeoPositionInfo::Attribute
    // 里根本没有 Elevation/Altitude (只有 Direction/Speed/Accuracy 那几个), 高程走
    // coordinate().altitude(), 后端没给时它自己返回 NaN —— 界面据此显示 "--".
    m_elevation = coord.altitude();
    emit locationUpdated(coord.latitude(), coord.longitude(), m_accuracy);
    Logger::debug(QString("GPS update: lat=%1 lon=%2 acc=%3")
                      .arg(coord.latitude(), 0, 'f', 6)
                      .arg(coord.longitude(), 0, 'f', 6)
                      .arg(m_accuracy, 0, 'f', 1));
}

bool EmergencyService::isLocationValid() const {
    return m_currentLocation.isValid() &&
           !(m_currentLocation.latitude() == 0.0 && m_currentLocation.longitude() == 0.0);
}

void EmergencyService::onJavaLocationUpdated(double lat, double lon,
                                              double accuracy, qint64 time) {
    QGeoCoordinate coord(lat, lon);
    if (!coord.isValid()) return;
    m_currentLocation = coord;
    m_accuracy = accuracy;
    // JNI 这条路只给 lat/lon/acc, QGeoCoordinate 的 altitude 是 NaN, 海拔就跟着
    // 变"无" —— 不要留着上一条定位的海拔继续显示 (用户会以为是当前值).
    m_elevation = coord.altitude();
    emit locationUpdated(lat, lon, accuracy);
    Logger::debug(QString("GPS update (from Java): lat=%1 lon=%2 acc=%3 time=%4")
                      .arg(lat, 0, 'f', 6)
                      .arg(lon, 0, 'f', 6)
                      .arg(accuracy, 0, 'f', 1)
                      .arg(time));
}

} // namespace outdoor

// ============================================================================
// JNI 桥接: Java 端 EmergencyService.onLocationChanged 触发
// ============================================================================
// Java 端 (android/src/com/outdoor/survival/EmergencyService.java:172) 声明:
//   private static native void nativeUpdateLocation(long callback,
//                                                    double lat, double lon,
//                                                    double accuracy, long time);
// C++ 端必须实现此函数, 否则 Java 触发 onLocationChanged 时 UnsatisfiedLinkError.
// 注意: 必须在 namespace 外, 用 C 链接, 函数名严格匹配 JNI 规范.
// 关键: 用 Q_OS_ANDROID || __ANDROID__ 双保险, 防止某些工具链未传 Q_OS_ANDROID
// 但仍按 Android NDK 编译的情况 (CMake 未加 -DQ_OS_ANDROID=1 时函数不导出,
// Java 端调 nativeUpdateLocation 会立即 UnsatisfiedLinkError).
#if defined(Q_OS_ANDROID) || defined(__ANDROID__)
extern "C" {

JNIEXPORT void JNICALL
Java_com_outdoor_survival_EmergencyService_nativeUpdateLocation(
        JNIEnv* /*env*/, jclass /*clazz*/,
        jlong callback, jdouble lat, jdouble lon,
        jdouble accuracy, jlong time) {
    Q_UNUSED(callback)
    // 找到当前 C++ EmergencyService 实例 (由 App 持有), 异步转发
    // 必须用 QueuedConnection, 因为 Java 线程不是 Qt 线程
    if (outdoor::EmergencyService* svc = outdoor::EmergencyService::instance()) {
        QMetaObject::invokeMethod(svc,
            "onJavaLocationUpdated", Qt::QueuedConnection,
            Q_ARG(double, lat),
            Q_ARG(double, lon),
            Q_ARG(double, accuracy),
            Q_ARG(qint64, time));
    }
}

} // extern "C"
#endif
