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
#include <cmath>  // 2026-10-22 #98: std::isfinite 判 NaN 哨兵 (精度/高程未知)
#include <algorithm>  // 2026-10-26: averageFixes 里的 std::min/max

// 与文件末尾那个 JNI 函数用同一个条件 (双保险), 否则只定义 __ANDROID__ 的工具链
// 会在 JNIEXPORT 处报未知类型.
#if defined(Q_OS_ANDROID) || defined(__ANDROID__)
#include <jni.h>   // JNIEXPORT / JNIEnv: 只给文件末尾那个 Java_..._nativeUpdateLocation 用
#endif

namespace outdoor {

// 静态单例指针初始化
EmergencyService* EmergencyService::s_instance = nullptr;

EmergencyService::EmergencyService(Database* db, PlatformInterface* platform,
                                     QObject* parent)
    : ServiceBase(db, "EmergencyService", parent), m_platform(platform) {
    // 设置单例, 供 JNI 桥接找到当前实例
    s_instance = this;
    // 创建 GPS 数据源(Android 上自动用系统定位).
    // 2026-10-22 #98: 这次建出来的源只用于"权限已开"的常规情况; 冷启动还没授权时
    // 它在建源那一刻读到空的 provider 列表, 之后只报错不出数, 所以授权回调里还会
    // 再 setupGeoSource() 一次 (见 startLocationUpdate).
    setupGeoSource();

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
    // 2026-10-23 #98 复盘: requestUpdate(8000) 是**异步**的, 而下面立刻组消息发出去,
    // 所以这条短信等不到它 —— 别说"等实时位置覆盖"(上一版注释就是这么写的, 做不到).
    // 手上没定位时先用系统缓存的最后一次位置垫上: 一个写明"几点测的"的旧位置, 强过
    // 一条"GPS 位置未获取到"的空坐标短信; 旧到什么程度由 positionAgeNote() 自己在
    // 短信里标出来. 实时读数到了之后更新的是界面与**下一条**短信.
    if (!isLocationValid()) seedFromLastKnown();

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

    // 2026-10-22 #98: 精度未知时不许写 "0.0 米" —— 那是给搜救队一个假承诺
    // (按零误差规划接近方式). 海拔同理: 没有就整行不出现, 而不是报 0 m 海平面.
    QString accuracyPart = std::isfinite(m_accuracy) && m_accuracy > 0
        ? QString("精度：%1 米").arg(m_accuracy, 0, 'f', 1)
        : QString("精度：未知（只有坐标本身可信）");
    if (std::isfinite(m_elevation)) {
        accuracyPart += QString("\n海拔：%1 米").arg(m_elevation, 0, 'f', 0);
    }
    // 位置过时才会多出这一行 (见文件末尾 positionAgeNote)
    const QString ageNote = positionAgeNote();
    if (!ageNote.isEmpty()) accuracyPart += "\n" + ageNote;

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

// 2026-10-23 #98: 短信里那行"时间:"是**发送**时刻, 不是位置的测量时刻. 手上这条读数
// 是系统缓存的 lastKnownPosition 时 (①/⑤ 进来没定位就垫它), 两个时刻能差几小时,
// 而搜救队会照着它规划接近方式 —— 那比不发位置更糟. 所以旧到一定程度的读数, 自己在
// 短信里写明"这是几点测的、已经过了多久".
QString EmergencyService::positionAgeNote() const {
    if (!m_positionTime.isValid()) return QString();   // 不知道测量时刻: 不编"刚刚"
    const qint64 ageMin = m_positionTime.msecsTo(QDateTime::currentDateTime()) / 60000;
    // 2 分钟: 第一颗定位本来就要十几秒到几十秒, 阈值再低会把正常的锁星延迟也标成旧数
    if (ageMin < 2) return QString();
    if (ageMin >= 60 * 24) {
        return QString("⚠️ 位置采于 %1（已 %2 天），不是实时位置")
            .arg(m_positionTime.toString("MM-dd HH:mm")).arg(ageMin / (60 * 24));
    }
    return QString("⚠️ 位置采于 %1（已 %2 分钟），不是实时位置")
        .arg(m_positionTime.toString("HH:mm")).arg(ageMin);
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
         // 未知精度存 NULL, 不存 NaN —— SQLite 的 REAL 装不下 NaN, 塞进去会被
         // 静默转成 0, 历史列表里就变成"当年精度 0 米".
         std::isfinite(m_accuracy) ? QVariant(m_accuracy) : QVariant(),
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
                            m_permGranted = true;
                            this->setupGeoSource();
                            this->requestLocationUpdate();
                        } else {
                            setDiag("未授予位置权限：系统设置里给荒野手册开「仅使用期间」定位");
                            emit errorOccurred("未授予位置权限,SOS GPS 链接将不可用");
                        }
                    });
                return;
            }
            Logger::info("Location permission granted, starting GPS updates");
            // 2026-10-22 #98: 权限到手后必须**重建**一次源. Qt 的 Android 插件在建源
            // 那一刻读一次 LocationManager.getProviders(true), 之后 provider/权限变化
            // 只报错不重读 —— 冷启动时还没授权 (或授权前系统开关刚被关过), 那次读到的
            // 是空数组, 于是这个源整辈子只回 UnknownSourceError(2). 真机证据: 日志里
            // "GPS source ready" 与 "GPS update started" 都在, 却一条 "GPS update: lat="
            // 都没有, error 2 刷了 79 次.
            // 另一个根因 —— 插件 Java 侧的 locationManager 恒为 null —— 在
            // OutdoorSurvivalApp.initQtPositioning 里补, 两处少一处都拿不到读数.
            m_permGranted = true;
            setupGeoSource();
            requestLocationUpdate();
        });
}

void EmergencyService::setupGeoSource() {
    if (m_geoSource) {
        m_geoSource->stopUpdates();
        // 旧源直接销毁即可: 连接跟着对象一起没, 不需要显式 disconnect
        m_geoSource->deleteLater();
        m_geoSource = nullptr;
    }

    m_geoSource = QGeoPositionInfoSource::createDefaultSource(this);
    if (!m_geoSource) {
        setDiag("这台设备没有可用的定位后端");
        Logger::warn("No GPS source available on this device");
        return;
    }
    connect(m_geoSource, &QGeoPositionInfoSource::positionUpdated,
            this, &EmergencyService::onPositionUpdated);
    connect(m_geoSource, &QGeoPositionInfoSource::errorOccurred,
            this, &EmergencyService::onSourceError);

    // 2026-10-23 精度优化: 默认 AllPositioningMethods 时, Qt 的 Android 插件把
    // GPS 与网络两个 provider 的读数混在同一个 positionUpdated 信号里往外发,
    // 谁后到谁覆盖. 真机日志实测每 20 s 夹一条网络定位 (acc 40 m 级、没有高程),
    // 正好落在 10 s 一次的卫星读数中间 —— 界面上的 ±42 m 与忽有忽无的海拔都是它.
    // 优先卫星之后室外拿到的是 GPS 本身 (A-GPS 一般 3~10 m); 室内可能长时间没新
    // 读数, 由 seedFromLastKnown() 垫底 + locationDiag 说明, 不会整片 "--".
    const QGeoPositionInfoSource::PositioningMethods supported =
        m_geoSource->supportedPositioningMethods();
    if (supported & QGeoPositionInfoSource::SatellitePositioningMethods) {
        m_geoSource->setPreferredPositioningMethods(
            QGeoPositionInfoSource::SatellitePositioningMethods);
    }

    // 把后端能力写进日志: "只有网络定位" (精度粗、通常没高程) 和 "GPS 后端没起"
    // 是两种完全不同的故障, 只看界面分不出来.
    // 2026-10-23: 原来这里 .arg(int(...), 0, 16) —— AllPositioningMethods 是 0xffffffff,
    // 转 int 成了 -1, 十六进制打成 "0x-1", 等于没写. 位掩码一律按无符号打.
    const quint32 methods = quint32(supported);
    Logger::info(QString("GPS source ready: name=%1 methods=0x%2 satellite=%3 preferred=0x%4")
                     .arg(m_geoSource->sourceName())
                     .arg(methods, 0, 16)
                     .arg(methods & quint32(QGeoPositionInfoSource::SatellitePositioningMethods)
                              ? "yes" : "no")
                     .arg(quint32(m_geoSource->preferredPositioningMethods()), 0, 16));
    setDiag(QString());
}

void EmergencyService::seedFromLastKnown() {
    if (!m_geoSource || isLocationValid()) return;
    const QGeoPositionInfo last = m_geoSource->lastKnownPosition(false);
    if (!last.isValid()) {
        Logger::info("System has no lastKnownPosition to seed from");
        return;
    }
    Logger::info("Seeded position from system lastKnownPosition");
    onPositionUpdated(last);
    // 顺序不能反: onPositionUpdated 会清空 diag, 这条"是缓存不是实时"要写在它之后.
    // 第一颗卫星定位到达时会被覆盖成实时值.
    setDiag("先用的是系统缓存的上一次定位，等新 GPS 读数到达后自动更新");
}

void EmergencyService::setDiag(const QString& why) {
    if (m_locationDiag == why) return;
    m_locationDiag = why;
    emit locationDiagChanged();
}

void EmergencyService::onSourceError(QGeoPositionInfoSource::Error err) {
    // Qt 6.7 的 QGeoPositionInfoSource::Error: 0 缺权限 / 1 已关闭 / 2 后端不可用 /
    // 3 无错 / 4 超时 (抄自 qgeopositioninfosource.h, 别按直觉猜序号).
    // 翻成人话写进 locationDiag, 仪表下面那行就有话说 —— 光显示 "--" 用户只能反复重进页面.
    switch (err) {
    case QGeoPositionInfoSource::UpdateTimeoutError:
        setDiag("定位超时：GPS 还没锁星，到开阔处再等十几秒");
        break;
    case QGeoPositionInfoSource::AccessError:
        setDiag("未授予位置权限：系统设置里给荒野手册开定位");
        break;
    case QGeoPositionInfoSource::UnknownSourceError:
        // 真机上就是这个码: 系统「位置信息」总开关关着, 或 GPS/网络两个 provider
        // 都被关. 后端在提供不了任何 provider 时直接报它, 不会给更细的原因.
        setDiag("系统定位服务不可用：确认「位置信息」开关已打开");
        break;
    case QGeoPositionInfoSource::ClosedError:
        setDiag("定位后端已关闭：退出本页再进来一次");
        break;
    default:   // NoError 以及后端自定义的码: 不猜, 只记日志
        Logger::warn(QString("GPS error: %1").arg(int(err)));
        return;
    }
    Logger::warn(QString("GPS error: %1 -> %2").arg(int(err)).arg(m_locationDiag));
}

void EmergencyService::stopLocationUpdate() {
    if (m_geoSource) {
        m_geoSource->stopUpdates();
        Logger::info("GPS updates stopped");
    }
}

void EmergencyService::requestLocationUpdate() {
    // 2026-10-22 #98: 这个函数是 QML 各页进来直接调的入口, 原来它不看权限就
    // startUpdates() —— 新装用户没授权时后端只回一个 AccessError, 界面整片 "--",
    // 用户既没被弹框也没地方知道原因 (只有 triggerSOS 那条路才走授权门).
    // 现在统一先过门: startLocationUpdate() 授权成功后调回本函数, m_permGranted
    // 就是防止两次调用互相递归的那颗闸.
    if (!m_permGranted) {
        startLocationUpdate();
        return;
    }
    if (!m_geoSource) {
        setDiag("这台设备没有可用的定位后端");
        emit errorOccurred("设备无 GPS 模块");
        return;
    }
    // 2026-10-26「轨迹/标注点精度到 1 m」: 10 秒 -> 1 秒. 下面那两条路 (Java 前台服务
    // 1 Hz + Qt 源) 现在都以 1 Hz 出帧, 这个源再按 10 s 抽稀等于把 9 帧原料丢掉,
    // averageFixes 的多帧平均就没有样本可平均. 耗电增量只在这个 app 主动定位期间产生.
    m_geoSource->setUpdateInterval(1000);
    m_geoSource->startUpdates();
    // 立即请求单次更新
    m_geoSource->requestUpdate(10000);
    // 第一颗定位通常要几秒到几十秒, 先用系统缓存垫上, 仪表不至于整片 "--"
    seedFromLastKnown();
    Logger::info("GPS update started, interval 1s");
}

// 2026-10-26「精度到 1 m」: 单帧 GNSS 的 68% 半径在手机上一般是 2~5 m, 里面随机分量
// 约占一半, 静止时按 1/σ² 把最近几帧平均掉, 落点能压到 1~2 m; 固定偏差 (多路径、
// 钟差) 平均不掉, 所以**报告出去的精度只取池内最好那一帧自己量出来的 σ**, 不报
// σ/√N —— 那个数是统计幻觉, 1 Hz 的相邻帧高度相关, 写进界面/短信就是假读数。
namespace {
constexpr int    kRefineWindowSec   = 6;    // 只平均 6 秒内的帧
constexpr int    kRefineMaxSamples  = 8;    // 再多收益已被帧间相关性吃掉
constexpr double kRefineMaxAccM     = 15.0; // 粗于此的帧 (网络/Wi-Fi 级) 不进池
constexpr double kRefineMinJumpTolM = 3.0;  // 换地方的最小判据
}

QGeoCoordinate EmergencyService::averageFixes(const QGeoCoordinate& coord, double accuracy,
                                              const QDateTime& when, double& reportedAccuracy) {
    reportedAccuracy = accuracy;

    // 不合格的帧: 直接透传, 并清空池 —— 一条粗帧之后的好帧必须重新攒, 不能和它平均
    const bool poolable = std::isfinite(accuracy) && accuracy > 0
                          && accuracy <= kRefineMaxAccM
                          && std::isfinite(coord.latitude())
                          && std::isfinite(coord.longitude());
    const QDateTime now = QDateTime::currentDateTime();
    // 测量时刻本身太旧 (系统缓存补的那一帧) 也不进池: 它和实时帧平均会把点拽回旧位置,
    // 而 positionAgeNote 那句"这是几分钟前的"就不再成立了。
    const bool fresh = when.isValid() && when.secsTo(now) <= kRefineWindowSec;
    if (!poolable || !fresh) {
        m_fixPool.clear();
        return coord;
    }

    // 丢窗外的旧帧
    while (!m_fixPool.isEmpty() && m_fixPool.first().when.secsTo(now) > kRefineWindowSec) {
        m_fixPool.removeFirst();
    }

    // 与池内加权均值的距离超过容差 = 人换地方了 (走路/坐车), 清池重新攒。
    // 容差 = max(3 m, 池内最好一帧的 σ): 静止抖动落在里面能平均, 每帧走 1.5 m 以上
    // 就连续超差 -> 轨迹点退回"当前这一帧", 不会被平均值拖在身后。
    if (!m_fixPool.isEmpty()) {
        double wsum = 0, latSum = 0, lonSum = 0, bestInPool = 1e9;
        for (const FixSample& s : m_fixPool) {
            const double w = 1.0 / (s.accuracy * s.accuracy);
            wsum += w; latSum += s.lat * w; lonSum += s.lon * w;
            bestInPool = std::min(bestInPool, s.accuracy);
        }
        const QGeoCoordinate mean(latSum / wsum, lonSum / wsum);
        if (mean.distanceTo(coord) > std::max(kRefineMinJumpTolM, bestInPool)) {
            m_fixPool.clear();
        }
    }

    m_fixPool.append(FixSample{coord.latitude(), coord.longitude(), accuracy, when});
    if (m_fixPool.size() > kRefineMaxSamples) m_fixPool.removeFirst();

    double wsum = 0, latSum = 0, lonSum = 0, bestInPool = accuracy;
    for (const FixSample& s : m_fixPool) {
        const double w = 1.0 / (s.accuracy * s.accuracy);
        wsum += w; latSum += s.lat * w; lonSum += s.lon * w;
        bestInPool = std::min(bestInPool, s.accuracy);
    }
    reportedAccuracy = bestInPool;   // 只报实测值, 见上面注释
    // 高程取**这一帧自己的**: 平均池里可能有 hasAltitude=false(NaN) 的帧, 而 GNSS
    // 高程本来就不准; 更不能拿上一条的海拔顶着 (会被读成当前值)。
    return QGeoCoordinate(latSum / wsum, lonSum / wsum, coord.altitude());
}

void EmergencyService::acceptLocation(const QGeoCoordinate& coord, double accuracy,
                                      const QDateTime& when, const char* source,
                                      double course) {
    // "更好或更新才覆盖", 不是"最后到的那条赢". 阈值 1.5 倍是这么定的: 同一颗 GPS
    // 连续两次的抖动在 10~20% 之间, 不该把位置冻住; 而真机上混进来的网络定位比卫星
    // 粗一个量级 (40 m vs 3~10 m), 那才是要挡的那一类.
    // 60 s 这个"保鲜期": 超过它就无条件接受 —— 宁可换一条粗的, 也不能把人冻在
    // 一个几分钟前的旧点上 (SOS 短信里发出去的位置错比粗危险得多).
    const bool heldIsFresh = isLocationValid()
                             && std::isfinite(m_accuracy) && m_accuracy > 0
                             && m_positionTime.isValid()
                             && m_positionTime.secsTo(QDateTime::currentDateTime()) < 60;
    // 2026-10-26: 判据里原来带 std::isfinite(accuracy), 于是"精度未知"(NaN)的读数
    // 永远短路通过、把精度已知的手里点顶掉 —— 界面上的 ± 数字就是这么被打回 NaN 的。
    // 精度未知的读数没有资格覆盖一个保鲜期内的已知点; 但超过 60 秒仍然无条件接受,
    // 不能为了好看的 ± 把人冻在一个几分钟前的旧坐标上 (SOS 短信里位置错比粗危险)。
    const bool incomingKnown = std::isfinite(accuracy) && accuracy > 0;
    if (heldIsFresh && (!incomingKnown || accuracy > m_accuracy * 1.5)) {
        Logger::debug(QString("GPS %1 skipped: acc=%2 m worse than held %3 m")
                          .arg(QString::fromLatin1(source))
                          .arg(accuracy, 0, 'f', 1)
                          .arg(m_accuracy, 0, 'f', 1));
        return;
    }
    double reported = accuracy;
    const QGeoCoordinate refined = averageFixes(coord, accuracy, when, reported);
    m_currentLocation = refined;
    // 2026-10-22 #98: 没有 HorizontalAccuracy 属性时是 NaN, 不是 0 —— 0 会被仪表
    // 写成 "±0 m"、被短信写成"精度：0.0 米", 那是假数.
    m_accuracy = reported;
    // 2026-10-20: ①营地/求助 的仪表要读海拔. Qt 6.7 的 QGeoPositionInfo::Attribute
    // 里根本没有 Elevation/Altitude (只有 Direction/Speed/Accuracy 那几个), 高程走
    // coordinate().altitude(), 后端没给时它自己返回 NaN —— 界面据此显示 "--".
    // 不拿上一条的海拔顶着: 用户会以为是当前值.
    m_elevation = refined.altitude();
    // 行进航向: 只跟着**被接受的这一帧**走, 不沿用上一帧的 (静止时航向会变成假读数)。
    m_course = std::isfinite(course) ? course : std::numeric_limits<double>::quiet_NaN();
    // 记下这条读数的时刻 (positionAgeNote 的"位置旧不旧"全靠它).
    // 后端没给 timestamp 时保持"不知道", 宁可不写也不编一个"刚刚".
    m_positionTime = when;
    setDiag(QString());   // 有数了, 上一条故障原因不再成立
    emit locationUpdated(refined.latitude(), refined.longitude(), m_accuracy);
    Logger::debug(QString("GPS update (%1): lat=%2 lon=%3 acc=%4 alt=%5 pool=%6")
                      .arg(QString::fromLatin1(source))
                      .arg(refined.latitude(), 0, 'f', 6)
                      .arg(refined.longitude(), 0, 'f', 6)
                      .arg(m_accuracy, 0, 'f', 1)
                      .arg(m_elevation, 0, 'f', 1)
                      .arg(m_fixPool.size()));
}

void EmergencyService::onPositionUpdated(const QGeoPositionInfo& info) {
    if (!info.isValid()) return;
    const QGeoCoordinate coord = info.coordinate();
    if (!coord.isValid()) return;
    const double acc = info.hasAttribute(QGeoPositionInfo::HorizontalAccuracy)
                           ? info.attribute(QGeoPositionInfo::HorizontalAccuracy)
                           : std::numeric_limits<double>::quiet_NaN();
    // 2026-10-26「蓝点没有方向」: Direction 属性 = Android Location.getBearing(),
    // 是**运动方位角** (走过来的航向), 静止时后端不给或为 0 —— 交给 QML 侧判 NaN.
    const double course = info.hasAttribute(QGeoPositionInfo::Direction)
                              ? info.attribute(QGeoPositionInfo::Direction)
                              : std::numeric_limits<double>::quiet_NaN();
    acceptLocation(coord, acc, info.timestamp(), "qt", course);
}

bool EmergencyService::isLocationValid() const {
    return m_currentLocation.isValid() &&
           !(m_currentLocation.latitude() == 0.0 && m_currentLocation.longitude() == 0.0);
}

void EmergencyService::onJavaLocationUpdated(double lat, double lon,
                                              double accuracy, double altitude,
                                              qint64 time) {
    // Java 的 Location 没测到高程时传 NaN 过来 (见 EmergencyService.java 的 hasAltitude
    // 判断); QGeoCoordinate 接受 NaN 高程, altitude() 原样返回 NaN.
    QGeoCoordinate coord(lat, lon, altitude);
    if (!coord.isValid()) return;
    // Java 的 Location.getTime() 是**这条读数自己的时刻** (缓存定位就是它被记下
    // 的那一刻, 不是现在) —— 必须原样带过来, 否则短信里的"位置旧不旧"算不出来.
    // time <= 0 = 没给, 保持"不知道".
    acceptLocation(coord, accuracy,
                   time > 0 ? QDateTime::fromMSecsSinceEpoch(time) : QDateTime(),
                   "java");
}

} // namespace outdoor

// ============================================================================
// JNI 桥接: Java 端 EmergencyService.onLocationChanged 触发
// ============================================================================
// Java 端 (android/src/com/outdoor/survival/EmergencyService.java) 声明:
//   private static native void nativeUpdateLocation(long callback,
//                                                    double lat, double lon,
//                                                    double accuracy,
//                                                    double altitude, long time);
// C++ 端必须实现此函数, 否则 Java 触发 onLocationChanged 时 UnsatisfiedLinkError.
// 2026-10-22 #98: 形参多了 altitude —— 签名改了必须 Java/C++ 两侧同时改, 否则
// 运行期 UnsatisfiedLinkError (整条 Java 定位链路静默失效, 比没海拔更糟).
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
        jdouble accuracy, jdouble altitude, jlong time) {
    Q_UNUSED(callback)
    // 找到当前 C++ EmergencyService 实例 (由 App 持有), 异步转发
    // 必须用 QueuedConnection, 因为 Java 线程不是 Qt 线程
    if (outdoor::EmergencyService* svc = outdoor::EmergencyService::instance()) {
        QMetaObject::invokeMethod(svc,
            "onJavaLocationUpdated", Qt::QueuedConnection,
            Q_ARG(double, lat),
            Q_ARG(double, lon),
            Q_ARG(double, accuracy),
            Q_ARG(double, altitude),
            Q_ARG(qint64, time));
    }
}

} // extern "C"
#endif
