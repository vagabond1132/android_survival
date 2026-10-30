/**
 * @file AndroidPlatform.h
 * @brief Android 平台实现（JNI）
 */

#pragma once

#include "PlatformInterface.h"

QT_BEGIN_NAMESPACE
class QJniObject;
QT_END_NAMESPACE

namespace outdoor {

/**
 * @class AndroidPlatform
 * @brief Android 平台实现
 */
class AndroidPlatform : public PlatformInterface {
    Q_OBJECT
public:
    explicit AndroidPlatform(QObject* parent = nullptr);
    ~AndroidPlatform() override;

    bool checkPermission(const QString& permission) override;
    void requestPermission(const QString& permission,
                            std::function<void(bool)> callback) override;

    bool makePhoneCall(const QString& number) override;
    bool sendSMS(const QString& number, const QString& text) override;
    void openUrl(const QString& url) override;
    void openAppSettings() override;

    void vibrate(int milliseconds) override;
    bool hasFlashlight() override;
    void setFlashlight(bool on) override;
    int getBatteryLevel() override;

    void keepScreenOn(bool on) override;

    void acquireWakeLock() override;
    void releaseWakeLock() override;

    QString getVersionName() override;
    QString getDeviceModel() override;
    QString getManufacturer() override;

    // 2026-09-11: 拍照入口. 拉起 PhotoCaptureActivity (独立壳), 拍完回调 file:// URI.
    void takePhoto(std::function<void(const QString& uri)> callback) override;

    // 2026-09-16: 复制任意 URI (file:// / content://) 到 app 沙盒, 返回本地绝对路径
    QString importImage(const QString& srcUri) override;

    // 2026-10-20: ⑤求助页两个读数动作 (见 PlatformInterface 注释)
    bool copyToClipboard(const QString& text) override;
    bool openSmsDraft(const QString& number, const QString& body) override;

    // 2026-10-28 (#148): 轨迹导入的本机文件搜索 (见 PlatformInterface 注释)
    QVariantList searchTrackFiles(const QString& keyword) override;
    bool canReadAllFiles() override;
    void openAllFilesAccessSettings() override;

    // 2026-10-29: Activity.moveTaskToBack(true) (见 PlatformInterface 注释)
    bool moveTaskToBack() override;

private:
    bool m_flashlightOn = false;
    QJniObject* m_wakeLock = nullptr;  // 延迟构造避免 #ifdef 复杂度
};

} // namespace outdoor
