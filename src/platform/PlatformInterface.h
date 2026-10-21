/**
 * @file PlatformInterface.h
 * @brief 平台抽象接口
 */

#pragma once

#include <QObject>
#include <QString>
#include <functional>

namespace outdoor {

/**
 * @class PlatformInterface
 * @brief 平台抽象（Android/iOS 各自实现）
 */
class PlatformInterface : public QObject {
    Q_OBJECT
public:
    static PlatformInterface* create();

    virtual ~PlatformInterface() = default;

    // 权限
    virtual bool checkPermission(const QString& permission) = 0;
    virtual void requestPermission(const QString& permission,
                                    std::function<void(bool)> callback) = 0;

    // 系统调用
    virtual bool makePhoneCall(const QString& number) = 0;
    virtual bool sendSMS(const QString& number, const QString& text) = 0;
    virtual void openUrl(const QString& url) = 0;
    virtual void openAppSettings() = 0;

    // 硬件
    virtual void vibrate(int milliseconds) = 0;
    virtual bool hasFlashlight() = 0;
    virtual void setFlashlight(bool on) = 0;
    virtual int getBatteryLevel() = 0;

    // 屏幕
    virtual void keepScreenOn(bool on) = 0;
    virtual void setBrightness(double value) = 0;

    // 进程
    virtual void acquireWakeLock() = 0;
    virtual void releaseWakeLock() = 0;

    // 应用信息
    virtual QString getVersionName() = 0;
    virtual QString getDeviceModel() = 0;
    virtual QString getManufacturer() = 0;

    // 拍照: 拉起系统相机/独立壳 Activity, 拍完回调 file:// URI (失败时 uri 为空).
    // 桌面端 (非 Android) 默认 stub: 立即回调空字符串.
    virtual void takePhoto(std::function<void(const QString& uri)> callback) {
        if (callback) callback(QString());
    }

    // 2026-09-15: QML 入口, 因为 std::function 不能跨 QML 边界,
    // 单独暴露一个无参 Q_INVOKABLE, QML 调, 内部转 std::function
    // 走 takePhoto 虚函数. QML 端通过 lastCapturedUri 属性 + photoTaken 信号接收结果.
    Q_INVOKABLE virtual void requestTakePhoto() {
        takePhoto(nullptr);
    }

    Q_PROPERTY(QString lastCapturedUri READ lastCapturedUri NOTIFY photoTaken)
    virtual QString lastCapturedUri() const { return m_lastCapturedUri; }
    void setLastCapturedUri(const QString& uri) { m_lastCapturedUri = uri; emit photoTaken(uri); }

    QString m_lastCapturedUri;

    // 2026-10-20: ⑤求助页「复制位置文本」.
    // 为什么放在平台层而不是 QML: QML 侧没有剪贴板 API, 且①⑤两处读数都要复用同一句
    // 文案 (emergencyService.formatLocationMessage), 复制动作必须跨端一致.
    // 桌面端 stub: 用 Qt 剪贴板, 无需 JNI.
    Q_INVOKABLE virtual bool copyToClipboard(const QString& text) {
        Q_UNUSED(text);
        return false;
    }

    // 2026-10-20: ⑤求助页「生成短信草稿」— 只拉起系统短信编辑页, 收件人和正文填好,
    // 发送键在用户手里. 与 sendSMS() 的区别是这条路径永远不会自己把短信发出去:
    // SmsManager.sendTextMessage (AndroidPlatform::sendSMS) 是直接发送, 在野外误触
    // 就是真发一条, 所以 SOS 流程一律走草稿, 不给直接发送留入口.
    // 桌面端 stub: 无事可做, 返回 false 让 UI 提示不可用.
    Q_INVOKABLE virtual bool openSmsDraft(const QString& number, const QString& body) {
        Q_UNUSED(number);
        Q_UNUSED(body);
        return false;
    }

    // 2026-09-16: 把任意 URI (file:// / content://) 复制到 app 沙盒, 返回本地绝对路径
    // 桌面端 stub: 原样返回 (没复制)
    Q_INVOKABLE virtual QString importImage(const QString& srcUri) {
        return srcUri;
    }

protected:
    // 显式转发 parent 给 QObject 基类(Qt 的 QObject 不可拷贝/移动,子类必须显式调用基类构造)
    explicit PlatformInterface(QObject* parent = nullptr) : QObject(parent) {}

signals:
    void photoTaken(QString uri);
    void permissionGranted(QString permission);
    void permissionDenied(QString permission);
    void batteryLevelChanged(int level);
};

} // namespace outdoor
