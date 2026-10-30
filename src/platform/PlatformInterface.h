/**
 * @file PlatformInterface.h
 * @brief 平台抽象接口
 */

#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
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

    // 2026-10-28 (#148): 轨迹导入要能"搜"本机文件, 不能只有系统选择器一条路 ——
    // 微信把收到的 .kml/.gpx 落在自己的下载目录里, 用户记不住也不可能记住那串路径.
    // 桌面端 stub 返回空列表 (单测走 FileScanner 本身, 不经过这里).
    Q_INVOKABLE virtual QVariantList searchTrackFiles(const QString& keyword) {
        Q_UNUSED(keyword);
        return {};
    }

    // 现在这个进程能不能读到共享存储里"别人家的"目录 (微信下载目录就是典型).
    // Android 11+ 看的是"所有文件访问"特殊权限, 10 及以下看 READ_EXTERNAL_STORAGE.
    // 桌面端 stub: 恒 true (本地文件本来就能读), 这样 UI 的权限提示在桌面不会碍事.
    Q_INVOKABLE virtual bool canReadAllFiles() { return true; }

    // 把用户送到系统里能开这个权限的页面 (不是代码授权, 授权动作始终在用户手里).
    // 桌面端 stub: 无事可做.
    Q_INVOKABLE virtual void openAllFilesAccessSettings() {}

    // 2026-10-29: 根页按返回键不再 finish Activity, 改为退到后台.
    // 真机 crash buffer 里从 10-22 起反复出现 hwuiTask0/1 的
    //   FORTIFY: pthread_mutex_lock called on a destroyed mutex → SIGABRT,
    // 触发点都落在"返回/冷退"这一条路径上. 把正常返回降级为 moveTaskToBack 后
    // 就不再销毁 Activity → 不再进入那次 surface 拆除竞态.
    // 注意: 这是规避, 不是证明过的根因修复 —— 从最近任务划掉进程仍会走系统拆除.
    // 桌面端 stub: 没有"后台"概念, 返回 false.
    Q_INVOKABLE virtual bool moveTaskToBack() { return false; }

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
