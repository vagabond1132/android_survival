/**
 * @file EmergencyService.h
 * @brief 紧急服务 - SOS、紧急联系人、紧急呼叫
 */

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QList>
#include <QDateTime>
#include <QGeoCoordinate>
#include <QGeoPositionInfo>
#include <QGeoPositionInfoSource>
#include "../common/ServiceBase.h"  // 2026-09-21 阶段 L2

namespace outdoor {

class PlatformInterface;

/**
 * @class EmergencyService
 * @brief 紧急服务（救命核心）
 *
 * 关键功能：
 * - 一键 SOS（长按 3 秒）
 * - 拨打 120/110/119
 * - 短信给紧急联系人（含 GPS）
 * - 紧急联系人管理
 *
 * @warning 涉及生命安全，必须充分测试
 */
class EmergencyService : public ServiceBase {
    Q_OBJECT
    Q_PROPERTY(bool isSosActive READ isSosActive NOTIFY sosStateChanged)
    Q_PROPERTY(int contactCount READ contactCount NOTIFY contactsChanged)

public:
    /**
     * @struct Contact
     * @brief 紧急联系人
     */
    struct Contact {
        QString name;
        QString phone;
        QString relation;
        bool isPrimary;
    };

    explicit EmergencyService(Database* db, PlatformInterface* platform,
                                QObject* parent = nullptr);
    ~EmergencyService() override;

    // 联系人管理
    // 2026-09-21: Phase 5 批次 3 - getContacts 返回 Result (EmergencyContactsPage + SOSPage 主列表)
    Q_INVOKABLE QVariantMap getContacts() const;
    // 2026-09-21: Phase 5 - 写操作切到 Result {ok, value, error}. QML 端用 result.ok 判断.
    Q_INVOKABLE QVariantMap addContact(const QString& name, const QString& phone,
                                        const QString& relation, bool isPrimary = false);
    Q_INVOKABLE QVariantMap deleteContact(int index);
    Q_INVOKABLE QVariantMap updateContact(int index, const QString& name,
                                           const QString& phone,
                                           const QString& relation, bool isPrimary);
    Q_INVOKABLE void setPrimary(int index);

    int contactCount() const;

    // SOS
    Q_INVOKABLE void triggerSOS();
    Q_INVOKABLE void cancelSOS();
    bool isSosActive() const { return m_sosActive; }

    // 快速拨号
    Q_INVOKABLE void call120();
    Q_INVOKABLE void call110();
    Q_INVOKABLE void call119();
    Q_INVOKABLE void callNumber(const QString& number);

    // 短信
    // 2026-09-21: 阶段 L3.6 - 写操作切 Result<bool>
    Q_INVOKABLE QVariantMap sendSosSMSToAll();
    Q_INVOKABLE QVariantMap sendSMS(const QString& number, const QString& text);

    // 位置
    Q_INVOKABLE QVariantMap getCurrentLocation();
    Q_INVOKABLE QString formatLocationMessage(double lat, double lon);
    Q_INVOKABLE bool isLocationValid() const;
    Q_INVOKABLE void requestLocationUpdate();

    // SOS 历史
    Q_INVOKABLE QVariantList getSosHistory(int limit = 20);

signals:
    void sosStateChanged();
    void sosTriggered(QDateTime timestamp);
    void sosCancelled();
    void callInitiated(QString number, bool success);
    void smsSent(QString number, bool success);
    void locationUpdated(double lat, double lon, double accuracy);
    void contactsChanged();
    void errorOccurred(QString error);

private slots:
    void onPositionUpdated(const QGeoPositionInfo& info);

private:
    void recordSosEvent(const QString& action, bool success,
                         const QString& detail = QString());
    void startLocationUpdate();
    void stopLocationUpdate();

    // JNI 回调入口(由 Java EmergencyService.onLocationChanged 触发)
    // 私有 Q_INVOKABLE: 仅 JNI 桥接通过 QMetaObject::invokeMethod 调用
    Q_INVOKABLE void onJavaLocationUpdated(double lat, double lon, double accuracy, qint64 time);

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    PlatformInterface* m_platform;
    bool m_sosActive = false;
    QGeoCoordinate m_currentLocation;
    double m_accuracy = 0;
    QGeoPositionInfoSource* m_geoSource = nullptr;

    // 单例指针: 供 JNI 桥接找到当前实例.
    // 只在 EmergencyService 存活期间有效, 析构时清空.
    // private: 外部不能直接访问, 通过 instance() 公开访问器.
    static EmergencyService* s_instance;

public:
    // JNI 桥接用: 获取当前 EmergencyService 实例 (存活期间有效, 否则 nullptr)
    static EmergencyService* instance() { return s_instance; }
};

} // namespace outdoor
