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
#include <limits>  // 2026-10-20: quiet_NaN 表示"本次定位没有高程"
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
    // 2026-10-20: 定位读数直接成属性, 供 ①营地/⑤求助 的墨底仪表绑定.
    // 之前 QML 侧只能调 getCurrentLocation() 拿 map 再自己接 signal, 每个页面
    // 各写一遍刷新逻辑, 于是"海拔"这一路根本没人接 (仪表上写的是 -- 或假数).
    Q_PROPERTY(bool hasLocation READ isLocationValid NOTIFY locationUpdated)
    Q_PROPERTY(double currentLatitude READ currentLatitude NOTIFY locationUpdated)
    Q_PROPERTY(double currentLongitude READ currentLongitude NOTIFY locationUpdated)
    // 2026-10-22 #98: 精度未知是 NaN, 不再默认 0. 0 会被仪表写成 "±0 m"、被 SOS 短信
    // 写成 "精度：0.0 米" —— 搜救场景里这是假数, 比空着更坏.
    Q_PROPERTY(double currentAccuracy READ currentAccuracy NOTIFY locationUpdated)
    // 高程来自 QGeoCoordinate::altitude() (Qt 6.7 的 QGeoPositionInfo 没有 Elevation
    // 属性), 后端没给时它就是 NaN → 界面显示 "--" 并在仪表下写明原因.
    Q_PROPERTY(double currentAltitude READ currentAltitude NOTIFY locationUpdated)
    // 2026-10-26 用户实测「蓝点没有方向指示」: QGeoPositionInfo::Direction 就是 Android
    // Location.getBearing() —— 行进航向 (运动方位角), 静止时为 NaN/不可用. 它是罗盘之外
    // 的第二方向来源: 有些机器 QCompass 后端起不来 (右上方位盘一直 "--"), 而人一走起来
    // 航向是有数的, 蓝点楔形不该因此整块没方向.
    Q_PROPERTY(double currentCourse READ currentCourse NOTIFY locationUpdated)
    // 定位拿不到时的中文原因 (空 = 一切正常). ①/⑤ 的仪表把它单独画一行: 光有 "--"
    // 用户分不清"还没定到位"和"这台机器根本定不到位", 只会反复重进页面.
    Q_PROPERTY(QString locationDiag READ locationDiag NOTIFY locationDiagChanged)

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

    // 定位读数 (见上方 Q_PROPERTY 注释)
    double currentLatitude() const  { return m_currentLocation.latitude(); }
    double currentLongitude() const { return m_currentLocation.longitude(); }
    double currentAccuracy() const  { return m_accuracy; }
    double currentAltitude() const  { return m_elevation; }
    double currentCourse() const    { return m_course; }
    QString locationDiag() const    { return m_locationDiag; }

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
    void locationDiagChanged();
    void contactsChanged();
    void errorOccurred(QString error);

private slots:
    void onPositionUpdated(const QGeoPositionInfo& info);
    // 把 Qt 的定位错误码翻成中文原因 (0 缺权限 / 1 已关闭 / 2 后端不可用 / 3 无错 / 4 超时)
    void onSourceError(QGeoPositionInfoSource::Error err);

private:
    void recordSosEvent(const QString& action, bool success,
                         const QString& detail = QString());
    void startLocationUpdate();
    void stopLocationUpdate();

    // 建/重建定位源. 拆成函数是因为它必须在"权限已授予"之后跑一次 (见 .cpp 注释)
    void setupGeoSource();
    // 实时定位还没到位时, 先用系统缓存的最后一次位置垫上
    void seedFromLastKnown();
    // 只改 locationDiag; 传空串 = 清掉原因 (拿到新定位之后调用)
    void setDiag(const QString& why);
    // 两条定位路 (Qt 源 / Java 桥) 唯一的落库口: 决定这条读数要不要覆盖当前值.
    // 见 .cpp —— 混进来的粗定位不许把好的那次冲掉, 这是"精度显示不上去"的真因.
    // course (行进航向, 度) 只有 Qt 源拿得到; Java 桥传 NaN.
    void acceptLocation(const QGeoCoordinate& coord, double accuracy,
                        const QDateTime& when, const char* source,
                        double course = std::numeric_limits<double>::quiet_NaN());
    // 2026-10-26「轨迹/标注点精度到 1 m」: 静止时把最近几帧按 1/σ² 加权求均值,
    // 走动时条件自动不成立 -> 清池退回单帧 (平均绝不能把轨迹点拖在人身后)。
    // 返回平均后的点; reportedAccuracy 只报池子里最好那一帧**自己量出来的** ±,
    // 不报理论 σ_mean —— 1 Hz 的 GNSS 帧高度相关, 那个数没有硬件依据, 报出去是假数。
    QGeoCoordinate averageFixes(const QGeoCoordinate& coord, double accuracy,
                                const QDateTime& when, double& reportedAccuracy);
    // 位置读数过时才会有的那行提示 (空串 = 不写). formatLocationMessage 拼进短信,
    // SOSPage 的"复制位置"用的是同一个函数, 所以两处口径天然一致
    QString positionAgeNote() const;

    // JNI 回调入口(由 Java EmergencyService.onLocationChanged 触发)
    // 私有 Q_INVOKABLE: 仅 JNI 桥接通过 QMetaObject::invokeMethod 调用
    // 2026-10-22 #98: 补 altitude —— Java 的 Location 一直有 getAltitude(), 之前
    // 桥接只传 lat/lon/acc/time, 走 SOS 前台服务这条路的海拔永远是 NaN.
    Q_INVOKABLE void onJavaLocationUpdated(double lat, double lon, double accuracy,
                                            double altitude, qint64 time);

    // 2026-09-21 阶段 L2: m_db 上移到 ServiceBase
    PlatformInterface* m_platform;
    bool m_sosActive = false;
    // 位置权限已经到手 (startLocationUpdate 的两个授权分支里置位). requestLocationUpdate
    // 拿它当闸: 没授权先去申请, 授权回调再调回来时靠它避免递归.
    bool m_permGranted = false;
    QGeoCoordinate m_currentLocation;
    // NaN = 未知 (见 Q_PROPERTY currentAccuracy 注释)
    double m_accuracy = std::numeric_limits<double>::quiet_NaN();
    // 2026-10-20: GPS 高程. NaN = 本次定位没带高程 (界面要显示 "--",
    // 不能显示 0 —— 0 m 会被读成"海平面", 在山地是错的数).
    double m_elevation = std::numeric_limits<double>::quiet_NaN();
    // 行进航向 (QGeoPositionInfo::Direction = Android Location.getBearing), 度.
    // NaN = 这一帧没给/静止不动 —— 蓝点的楔形据此决定画不画.
    double m_course = std::numeric_limits<double>::quiet_NaN();
    QGeoPositionInfoSource* m_geoSource = nullptr;
    QString m_locationDiag;
    // 这条读数的测量时刻 (无效 = 后端没给). 短信里的"时间:"是**发送**时刻, 不是位置
    // 时刻 —— 用系统缓存的 lastKnownPosition 垫底时两者能差几小时, 搜救队按当前
    // 位置规划接近方式就会被误导 (2026-10-23 #98 复盘).
    QDateTime m_positionTime;

    // 多帧平均的滑动池 (见 averageFixes). 只在 Qt 主线程访问, 不需要锁.
    struct FixSample {
        double lat = 0;
        double lon = 0;
        double accuracy = 0;
        QDateTime when;
    };
    QList<FixSample> m_fixPool;

    // 单例指针: 供 JNI 桥接找到当前实例.
    // 只在 EmergencyService 存活期间有效, 析构时清空.
    // private: 外部不能直接访问, 通过 instance() 公开访问器.
    static EmergencyService* s_instance;

public:
    // JNI 桥接用: 获取当前 EmergencyService 实例 (存活期间有效, 否则 nullptr)
    static EmergencyService* instance() { return s_instance; }
};

} // namespace outdoor
