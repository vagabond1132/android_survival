/**
 * @file AndroidPlatform.cpp
 */

#include "AndroidPlatform.h"
#include "../core/Logger.h"

#include <QCoreApplication>
#include <QMutex>
#include <QMutexLocker>
#include <QHash>
#include <QMetaObject>
#include <QCoreApplication>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QByteArray>
#include <QDateTime>
#include <QGuiApplication>
#include <QClipboard>
#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QJniEnvironment>
#endif

namespace outdoor {

namespace {
// Qt 6 把 QtNative 从 org.qtproject.qt5.android.QtNative 改为
// org.qtproject.qt.android.QtNative（去掉了 "qt5" 段）。
// 用 Qt 5 的旧类名时 callStaticObjectMethod 返回空对象，导致
// makePhoneCall / sendSMS / openUrl / openAppSettings 全部静默失败；
// 在 ProGuard 严格模式下还可能触发 ClassNotFoundException，
// 与 tombstone 中 "Native registration unable to find class ..." 同源。
// 集中用 kQtNativeClass 常量避免散落写法再次漂移。
// QJniObject / QtNative 类名只在 Android 下可用 (头文件在文件顶部同样有 guard),
// 否则桌面构建 (tests/) 报 incomplete type
#ifdef Q_OS_ANDROID
constexpr const char* kQtNativeClass = "org/qtproject/qt/android/QtNative";

QJniObject getActivity() {
    return QJniObject::callStaticObjectMethod(
        kQtNativeClass,
        "activity",
        "()Landroid/app/Activity;"
    );
}
#endif
}  // anonymous namespace

AndroidPlatform::AndroidPlatform(QObject* parent) : PlatformInterface(parent) {
    // Qt 6 已废弃 QtActivity::activity() static 方法, 不需要缓存 Activity 句柄.
    // 需要 Activity 时用 getActivity() 助手每次重新拿.
}

AndroidPlatform::~AndroidPlatform() {
    releaseWakeLock();
}
// 2026-09-19: 权限 callback 存储表 (requestCode -> C++ 端 std::function).
//   Java 端 PermissionHelper.sNextCode 自增产生 requestCode, 写入这里;
//   Activity.onRequestPermissionsResult 回调到达时, 反向 JNI
//   nativeHandlePermissionResult 按 requestCode take 出来投递到主线程触发.
//   用 QHash<int, ...> + QMutex 兜住多线程 (C++ 端 request 可能在 UI 线程,
//   Java 回调在 Android 主线程, 不会冲突, 但加锁稳一下).
QHash<int, std::function<void(bool)>> g_pendingPermCallbacks;
QMutex g_pendingPermMutex;

bool AndroidPlatform::checkPermission(const QString& permission) {
#ifdef Q_OS_ANDROID
    if (permission.isEmpty()) return false;
    // 调 Java 端 PermissionHelper.check(String) -> boolean
    // 返回 PackageManager.PERMISSION_GRANTED 比较结果
    QJniObject permStr = QJniObject::fromString(permission);
    jboolean granted = QJniObject::callStaticMethod<jboolean>(
        "com/outdoor/survival/PermissionHelper",
        "check",
        "(Ljava/lang/String;)Z",
        permStr.object()
    );
    QJniEnvironment env;
    if (env->ExceptionCheck()) {
        Logger::warn(QString("checkPermission: JNI exception for %1").arg(permission));
        env->ExceptionClear();
        return false;
    }
    return static_cast<bool>(granted);
#else
    Q_UNUSED(permission);
    return true;
#endif
}

void AndroidPlatform::requestPermission(const QString& permission,
                                          std::function<void(bool)> callback) {
#ifdef Q_OS_ANDROID
    if (permission.isEmpty()) {
        if (callback) callback(false);
        return;
    }
    // 短路: 已授权直接回调 granted=true, 不弹系统框
    if (checkPermission(permission)) {
        if (callback) callback(true);
        return;
    }
    // 发起异步申请. Java 端 sNextCode 自增产生 requestCode,
    // 我们在调 Java 前空出一个槽, Java 端的实际 requestCode 跟它一致
    // (Java 端 incrementAndGet 返回的就是最终 code), 然后回调时按 code 取
    QJniObject permStr = QJniObject::fromString(permission);
    jint code = QJniObject::callStaticMethod<jint>(
        "com/outdoor/survival/PermissionHelper",
        "peekNextCode",  // 先 peek 不消耗, Java request() 内部还会 incrementAndGet
        "()I"
    );
    {
        QJniEnvironment env;
        if (env->ExceptionCheck()) {
            Logger::warn(QString("requestPermission: peekNextCode JNI exception for %1").arg(permission));
            env->ExceptionClear();
            if (callback) callback(false);
            return;
        }
    }
    {
        QMutexLocker lock(&g_pendingPermMutex);
        g_pendingPermCallbacks.insert(static_cast<int>(code), callback);
    }
    // 真发起申请 (内部会再 incrementAndGet, 拿到的 code = peek + 1)
    //
    // 2026-09-20 修: 之前这里用 callStaticMethod<void> + signature "(Ljava/lang/String;)Z",
    //   但 Java PermissionHelper.request(String) 返回 boolean. Qt 6 JNI 在模板参数 T
    //   跟 signature 返回段不一致时, JNI 内部按 "void" 解析参数表, 导致 (String) 参数
    //   实际没正确传入 Java 端 → Java 端 permission==null 直接 return false,
    //   ActivityCompat.requestPermissions 根本没被调 → 系统权限框永远不弹
    //   (用户报"用户没授权定位 为什么不进行弹窗申请权限" 的根因).
    // 修复: 改用 callStaticMethod<jboolean> + signature "(Ljava/lang/String;)Z",
    //   跟 Java 签名严格一致.
    jboolean alreadyGranted = QJniObject::callStaticMethod<jboolean>(
        "com/outdoor/survival/PermissionHelper",
        "request",
        "(Ljava/lang/String;)Z",
        permStr.object()
    );
    {
        QJniEnvironment env;
        if (env->ExceptionCheck()) {
            Logger::warn(QString("requestPermission: request() JNI exception for %1").arg(permission));
            env->ExceptionClear();
            std::function<void(bool)> cb;
            {
                QMutexLocker lock(&g_pendingPermMutex);
                cb = g_pendingPermCallbacks.take(static_cast<int>(code));
            }
            if (cb) cb(false);
        } else {
            Logger::info(QString("requestPermission: requested %1 (code=%2, alreadyGranted=%3)")
                             .arg(permission).arg(code).arg(alreadyGranted));
            // 极端情况: peek 跟 request 之间, 另一个线程把权限授权了 (理论上不会发生,
            // 但保险). Java request() 返回 true = 已授权, 不需要异步回调,
            // 主动同步 callback(true) 并从 pending 表移除.
            if (alreadyGranted) {
                std::function<void(bool)> cb;
                {
                    QMutexLocker lock(&g_pendingPermMutex);
                    cb = g_pendingPermCallbacks.take(static_cast<int>(code));
                }
                if (cb) cb(true);
            }
        }
    }
#else
    Q_UNUSED(permission);
    if (callback) callback(true);
#endif
}

bool AndroidPlatform::makePhoneCall(const QString& number) {
    if (number.isEmpty()) return false;

#ifdef Q_OS_ANDROID
    // Android 10+ 使用 ACTION_DIAL 不需要权限
    // Android < 10 使用 ACTION_CALL 需要权限
    QJniObject activity = QJniObject::callStaticObjectMethod(
        kQtNativeClass,
        "activity",
        "()Landroid/app/Activity;"
    );
    if (!activity.isValid()) {
        Logger::warn("makePhoneCall: activity invalid (QtNative class lookup failed?)");
        return false;
    }

    QJniObject intent("android/content/Intent", "()V");

    // 使用 ACTION_DIAL（打开拨号界面，不直接拨打）
    QJniObject action = QJniObject::fromString("android.intent.action.DIAL");
    intent.callObjectMethod("setAction", "(Ljava/lang/String;)Landroid/content/Intent;",
                            action.object());

    QJniObject uriString = QJniObject::fromString("tel:" + number);
    QJniObject uri = QJniObject::callStaticObjectMethod(
        "android/net/Uri", "parse", "(Ljava/lang/String;)Landroid/net/Uri;",
        uriString.object()
    );
    if (!uri.isValid()) {
        Logger::warn("makePhoneCall: uri parse failed");
        return false;
    }
    intent.callObjectMethod("setData", "(Landroid/net/Uri;)Landroid/content/Intent;",
                            uri.object());

    QJniObject packageManager = activity.callObjectMethod(
        "getPackageManager", "()Landroid/content/pm/PackageManager;"
    );
    if (!packageManager.isValid()) {
        Logger::warn("makePhoneCall: getPackageManager returned null");
        return false;
    }

    QJniObject resolveActivity = packageManager.callObjectMethod(
        "resolveActivity", "(Landroid/content/Intent;)Landroid/content/pm/ResolveInfo;",
        intent.object()
    );

    bool handled = resolveActivity.isValid();
    if (handled) {
        activity.callMethod<void>("startActivity", "(Landroid/content/Intent;)V",
                                   intent.object());
    }
    return handled;
#else
    Q_UNUSED(number);
    return false;
#endif
}

bool AndroidPlatform::sendSMS(const QString& number, const QString& text) {
    if (number.isEmpty()) return false;

#ifdef Q_OS_ANDROID
    QJniObject activity = QJniObject::callStaticObjectMethod(
        kQtNativeClass,
        "activity",
        "()Landroid/app/Activity;"
    );

    // 使用 SmsManager 直接发送（需要权限）
    QJniObject smsManager = QJniObject::callStaticObjectMethod(
        "android/telephony/SmsManager", "getDefault", "()Landroid/telephony/SmsManager;"
    );

    if (!smsManager.isValid()) {
        Logger::error("Failed to get SmsManager");
        return false;
    }

    QJniObject dest = QJniObject::fromString(number);
    QJniObject msg = QJniObject::fromString(text);

    smsManager.callMethod<void>("sendTextMessage",
                                 "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;"
                                 "Landroid/app/PendingIntent;Landroid/app/PendingIntent;)V",
                                 dest.object(), nullptr, msg.object(), nullptr, nullptr);

    return true;
#else
    Q_UNUSED(number);
    Q_UNUSED(text);
    return false;
#endif
}

void AndroidPlatform::openUrl(const QString& url) {
    if (url.isEmpty()) return;
#ifdef Q_OS_ANDROID
    QJniObject activity = getActivity();
    if (!activity.isValid()) {
        Logger::warn("openUrl: activity invalid");
        return;
    }

    QJniObject intent("android/content/Intent", "()V");
    QJniObject action = QJniObject::fromString("android.intent.action.VIEW");
    intent.callObjectMethod("setAction", "(Ljava/lang/String;)Landroid/content/Intent;",
                            action.object());

    QJniObject uriString = QJniObject::fromString(url);
    QJniObject uri = QJniObject::callStaticObjectMethod(
        "android/net/Uri", "parse", "(Ljava/lang/String;)Landroid/net/Uri;",
        uriString.object()
    );
    if (!uri.isValid()) {
        Logger::warn("openUrl: uri parse failed for " + url);
        return;
    }
    intent.callObjectMethod("setData", "(Landroid/net/Uri;)Landroid/content/Intent;",
                            uri.object());
    intent.callObjectMethod("addFlags", "(I)Landroid/content/Intent;", 0x10000000);

    activity.callMethod<void>("startActivity", "(Landroid/content/Intent;)V",
                               intent.object());
#else
    Q_UNUSED(url);
#endif
}

bool AndroidPlatform::copyToClipboard(const QString& text) {
    if (text.isEmpty()) return false;
    // Qt 6 在 Android 上有自己的剪贴板后端 (ClipboardAndroid), 不必走 JNI.
    // 指针仍判空: 无头/离线跑单测时 QGuiApplication 可能还没建好.
    QClipboard* cb = QGuiApplication::clipboard();
    if (!cb) {
        Logger::warn("copyToClipboard: no clipboard available");
        return false;
    }
    cb->setText(text);
    return true;
}

bool AndroidPlatform::openSmsDraft(const QString& number, const QString& body) {
#ifdef Q_OS_ANDROID
    // 只拉起短信编辑页, 发送键留给用户 —— 见 PlatformInterface::openSmsDraft 注释.
    QJniObject activity = getActivity();
    if (!activity.isValid()) {
        Logger::warn("openSmsDraft: activity invalid");
        return false;
    }

    QJniObject intent("android/content/Intent", "()V");
    QJniObject action = QJniObject::fromString("android.intent.action.SENDTO");
    intent.callObjectMethod("setAction", "(Ljava/lang/String;)Landroid/content/Intent;",
                            action.object());

    // ACTION_SENDTO + smsto: 是唯一各家短信 App 都认的写法.
    // ACTION_VIEW + sms: 在第三方短信客户端里常被当成网址处理.
    const QString scheme = number.isEmpty() ? QStringLiteral("smsto:")
                                            : QStringLiteral("smsto:") + number;
    QJniObject uriString = QJniObject::fromString(scheme);
    QJniObject uri = QJniObject::callStaticObjectMethod(
        "android/net/Uri", "parse", "(Ljava/lang/String;)Landroid/net/Uri;",
        uriString.object()
    );
    if (!uri.isValid()) {
        Logger::warn("openSmsDraft: uri parse failed");
        return false;
    }
    intent.callObjectMethod("setData", "(Landroid/net/Uri;)Landroid/content/Intent;",
                            uri.object());

    if (!body.isEmpty()) {
        QJniObject key = QJniObject::fromString("sms_body");
        QJniObject val = QJniObject::fromString(body);
        intent.callObjectMethod(
            "putExtra",
            "(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;",
            key.object(), val.object());
    }
    intent.callObjectMethod("addFlags", "(I)Landroid/content/Intent;", 0x10000000);

    activity.callMethod<void>("startActivity", "(Landroid/content/Intent;)V",
                              intent.object());
    // 机器上没装短信应用时 startActivity 抛 ActivityNotFoundException.
    // JNI 的 Java 异常不会传播成 C++ 异常, 但会挂在环境里让下一次 JNI 调用崩,
    // 所以必须 ExceptionCheck + ExceptionClear 后再回 false.
    QJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        Logger::warn("openSmsDraft: startActivity threw (no SMS client?)");
        return false;
    }
    return true;
#else
    return PlatformInterface::openSmsDraft(number, body);
#endif
}

void AndroidPlatform::openAppSettings() {
#ifdef Q_OS_ANDROID
    QJniObject activity = QJniObject::callStaticObjectMethod(
        kQtNativeClass,
        "activity",
        "()Landroid/app/Activity;"
    );
    if (!activity.isValid()) {
        Logger::warn("openAppSettings: activity invalid (QtNative class lookup failed?)");
        return;
    }

    QJniObject intent("android/content/Intent", "()V");
    QJniObject action = QJniObject::fromString(
        "android.settings.APPLICATION_DETAILS_SETTINGS"
    );
    intent.callObjectMethod("setAction", "(Ljava/lang/String;)Landroid/content/Intent;",
                            action.object());

    // 关键: 用 Context.getPackageName() 取真实 applicationId, 不要硬编码
    // 原因: build.gradle 的 debug buildType 设了 applicationIdSuffix ".debug",
    //       实际包名是 com.outdoor.survival.debug. 硬编码会跳到错误的详情页
    //       (或不存在页面, Android 11+ 还会抛 ActivityNotFoundException).
    QJniObject context = activity.callObjectMethod(
        "getApplicationContext", "()Landroid/content/Context;"
    );
    if (!context.isValid()) {
        Logger::warn("openAppSettings: getApplicationContext returned null");
        return;
    }
    QJniObject packageName = context.callObjectMethod(
        "getPackageName", "()Ljava/lang/String;"
    );
    if (!packageName.isValid()) {
        Logger::warn("openAppSettings: getPackageName returned null");
        return;
    }
    QJniObject uriString = QJniObject::fromString("package:" + packageName.toString());

    QJniObject uri = QJniObject::callStaticObjectMethod(
        "android/net/Uri", "parse", "(Ljava/lang/String;)Landroid/net/Uri;",
        uriString.object()
    );
    if (!uri.isValid()) {
        Logger::warn("openAppSettings: uri parse failed");
        return;
    }
    intent.callObjectMethod("setData", "(Landroid/net/Uri;)Landroid/content/Intent;",
                            uri.object());
    intent.callObjectMethod("addFlags", "(I)Landroid/content/Intent;", 0x10000000);  // FLAG_ACTIVITY_NEW_TASK

    activity.callMethod<void>("startActivity", "(Landroid/content/Intent;)V",
                               intent.object());
#endif
}

void AndroidPlatform::vibrate(int milliseconds) {
#ifdef Q_OS_ANDROID
    if (milliseconds <= 0) return;
    // 需要 VIBRATE 权限
    if (!checkPermission("android.permission.VIBRATE")) {
        requestPermission("android.permission.VIBRATE",
            [this, milliseconds](bool granted) {
                if (granted) {
                    this->vibrate(milliseconds);
                } else {
                    Logger::warn("VIBRATE permission denied");
                }
            });
        return;
    }
    QJniObject activity = getActivity();
    if (!activity.isValid()) {
        Logger::warn("vibrate: activity invalid");
        return;
    }
    // Vibrator.vibrate(long milliseconds)
    QJniObject vibratorService = activity.callObjectMethod(
        "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;",
        QJniObject::fromString("vibrator").object()
    );
    if (vibratorService.isValid()) {
        jlong ms = static_cast<jlong>(milliseconds);
        vibratorService.callMethod<void>("vibrate", "(J)V", ms);
        Logger::debug(QString("Vibrated %1ms").arg(milliseconds));
    } else {
        Logger::warn("vibrate: service unavailable");
    }
#else
    Q_UNUSED(milliseconds);
#endif
}

bool AndroidPlatform::hasFlashlight() {
#ifdef Q_OS_ANDROID
    QJniObject activity = getActivity();
    if (!activity.isValid()) return false;
    QJniObject packageManager = activity.callObjectMethod(
        "getPackageManager", "()Landroid/content/pm/PackageManager;"
    );
    if (!packageManager.isValid()) return false;
    // PackageManager.hasSystemFeature(String)
    return packageManager.callMethod<jboolean>(
        "hasSystemFeature", "(Ljava/lang/String;)Z",
        QJniObject::fromString("android.hardware.camera.flash").object()
    );
#else
    return false;
#endif
}

void AndroidPlatform::setFlashlight(bool on) {
#ifdef Q_OS_ANDROID
    if (!hasFlashlight()) {
        Logger::warn("Device has no flashlight");
        return;
    }
    // 简化实现:用 CameraManager 切换手电筒
    QJniObject activity = getActivity();
    if (!activity.isValid()) return;

    QJniObject context = activity.callObjectMethod(
        "getApplicationContext", "()Landroid/content/Context;"
    );
    if (!context.isValid()) {
        Logger::warn("setFlashlight: getApplicationContext returned null");
        return;
    }
    QJniObject cameraManager = context.callObjectMethod(
        "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;",
        QJniObject::fromString("cameraservice").object()
    );
    if (!cameraManager.isValid()) {
        Logger::warn("CameraManager unavailable");
        return;
    }

    // 找后置摄像头
    QJniObject cameraIdList = cameraManager.callObjectMethod(
        "getCameraIdList", "()Ljava/util/ArrayList;"
    );
    if (!cameraIdList.isValid()) return;

    // 简化:用 ID "0"(通常后置),并控制 torch
    QJniObject cameraId = QJniObject::fromString("0");
    jboolean on_j = on ? JNI_TRUE : JNI_FALSE;
    cameraManager.callMethod<void>(
        "setTorchMode", "(Ljava/lang/String;Z)V",
        cameraId.object(), on_j
    );
    m_flashlightOn = on;
    Logger::info(QString("Flashlight %1").arg(on ? "ON" : "OFF"));
#else
    Q_UNUSED(on);
    m_flashlightOn = false;
#endif
}

int AndroidPlatform::getBatteryLevel() {
#ifdef Q_OS_ANDROID
    QJniObject activity = getActivity();
    if (!activity.isValid()) return -1;

    QJniObject context = activity.callObjectMethod(
        "getApplicationContext", "()Landroid/content/Context;"
    );
    if (!context.isValid()) return -1;

    QJniObject batteryManager = context.callObjectMethod(
        "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;",
        QJniObject::fromString("batterymanager").object()
    );

    if (!batteryManager.isValid()) return -1;

    int level = batteryManager.callMethod<int>(
        "getIntProperty", "(I)I", 4  // BATTERY_PROPERTY_CAPACITY
    );

    return level;
#else
    return 100;
#endif
}

void AndroidPlatform::keepScreenOn(bool on) {
#ifdef Q_OS_ANDROID
    QJniObject activity = getActivity();
    if (!activity.isValid()) return;
    // Window.FLAG_KEEP_SCREEN_ON = 0x00000080
    // 直接修改 Window flag,避免依赖 Java 类
    QJniObject window = activity.callObjectMethod(
        "getWindow", "()Landroid/view/Window;"
    );
    if (!window.isValid()) return;
    if (on) {
        window.callMethod<void>("addFlags", "(I)V", 0x00000080);
    } else {
        window.callMethod<void>("clearFlags", "(I)V", 0x00000080);
    }
    Logger::info(QString("keepScreenOn: %1").arg(on ? "ON" : "OFF"));
#else
    Q_UNUSED(on);
#endif
}

void AndroidPlatform::setBrightness(double value) {
#ifdef Q_OS_ANDROID
    if (value < 0.0 || value > 1.0) {
        Logger::warn("brightness must be 0.0-1.0");
        return;
    }
    QJniObject activity = getActivity();
    if (!activity.isValid()) return;
    // Window.LayoutParams.screenBrightness(0.0-1.0, -1 = 系统默认)
    QJniObject window = activity.callObjectMethod(
        "getWindow", "()Landroid/view/Window;"
    );
    if (!window.isValid()) return;
    QJniObject params = window.callObjectMethod(
        "getAttributes", "()Landroid/view/WindowManager$LayoutParams;"
    );
    if (!params.isValid()) return;
    params.callMethod<void>(
        "setScreenBrightness", "(F)V",
        static_cast<jfloat>(value)
    );
    window.callMethod<void>("setAttributes",
        "(Landroid/view/WindowManager$LayoutParams;)V",
        params.object());
    Logger::debug(QString("Brightness set to %1").arg(value, 0, 'f', 2));
#else
    Q_UNUSED(value);
#endif
}

void AndroidPlatform::acquireWakeLock() {
#ifdef Q_OS_ANDROID
    if (m_wakeLock) {
        Logger::info("WakeLock already held");
        return;
    }
    if (!checkPermission("android.permission.WAKE_LOCK")) {
        requestPermission("android.permission.WAKE_LOCK",
            [this](bool granted) {
                if (granted) this->acquireWakeLock();
            });
        return;
    }
    QJniObject activity = getActivity();
    if (!activity.isValid()) return;
    QJniObject context = activity.callObjectMethod(
        "getApplicationContext", "()Landroid/content/Context;"
    );
    if (!context.isValid()) {
        Logger::warn("acquireWakeLock: getApplicationContext returned null");
        return;
    }
    QJniObject powerManager = context.callObjectMethod(
        "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;",
        QJniObject::fromString("power").object()
    );
    if (!powerManager.isValid()) return;
    QJniObject wakeLock = powerManager.callObjectMethod(
        "newWakeLock", "(ILjava/lang/String;)Landroid/os/PowerManager$WakeLock;",
        0x0000000A,  // SCREEN_BRIGHT_WAKE_LOCK
        QJniObject::fromString("outdoor:field_guide").object()
    );
    if (wakeLock.isValid()) {
        wakeLock.callMethod<void>("acquire", "(J)V",
                                   static_cast<jlong>(24LL * 60 * 60 * 1000));
        // 转移所有权到 QJniObject*
        m_wakeLock = new QJniObject(wakeLock);
        Logger::info("WakeLock acquired (24h)");
    }
#else
#endif
}

void AndroidPlatform::releaseWakeLock() {
#ifdef Q_OS_ANDROID
    if (m_wakeLock) {
        m_wakeLock->callMethod<void>("release", "()V");
        delete m_wakeLock;
        m_wakeLock = nullptr;
        Logger::info("WakeLock released");
    }
#endif
}

QString AndroidPlatform::getVersionName() {
#ifdef Q_OS_ANDROID
    return QCoreApplication::applicationVersion();
#else
    return "0.1.0";
#endif
}

QString AndroidPlatform::getDeviceModel() {
#ifdef Q_OS_ANDROID
    QJniObject model = QJniObject::getStaticObjectField<jstring>(
        "android/os/Build", "MODEL"
    );
    if (model.isValid()) {
        return model.toString();
    }
#endif
    return "Unknown";
}

QString AndroidPlatform::getManufacturer() {
#ifdef Q_OS_ANDROID
    QJniObject manu = QJniObject::getStaticObjectField<jstring>(
        "android/os/Build", "MANUFACTURER"
    );
    if (manu.isValid()) {
        return manu.toString();
    }
#endif
    return "Unknown";
}

// 2026-09-11: 拍照入口. 策略:
//   1. C++ 端 startActivity (不指望 startActivityForResult 回灌, 因 Qt 6.7 Activity
//      onActivityResult 不开放给外部 C++ 监听).
//   2. PhotoCaptureActivity (独立壳, 不继承 QtActivity) 拉起系统相机, 拍完
//      setResult + finish; 同时通过 JNI 反向调 PhotoCaptureContract.notifyResult
//      把 file:// URI 直接灌回 C++ 端 pending 队列.
//   3. C++ 端 queued 到主线程触发 JS callback.

#ifdef Q_OS_ANDROID
namespace {
struct PendingPhotoRequest {
    std::function<void(const QString&)> callback;
    bool active = false;
};
QMutex g_pendingMutex;
PendingPhotoRequest g_pending;

void notifyPhotoResultImpl(const QString& uri) {
    QMutexLocker lock(&g_pendingMutex);
    if (!g_pending.active || !g_pending.callback) return;
    auto cb = g_pending.callback;
    g_pending.callback = nullptr;
    g_pending.active = false;
    QMetaObject::invokeMethod(qApp, [cb, uri]() {
        cb(uri);
    }, Qt::QueuedConnection);
}
}  // anonymous namespace

// Java 反向 JNI: com.outdoor.survival.PhotoCaptureContract.notifyResult(String)
extern "C" JNIEXPORT void JNICALL
Java_com_outdoor_survival_PhotoCaptureContract_notifyResult(
    JNIEnv* env, jclass /*clazz*/, jstring jUri)
{
    if (!jUri) {
        notifyPhotoResultImpl(QString());
        return;
    }
    const char* chars = env->GetStringUTFChars(jUri, nullptr);
    QString uri = QString::fromUtf8(chars);
    env->ReleaseStringUTFChars(jUri, chars);
    notifyPhotoResultImpl(uri);
}

// 2026-09-19: Java 反向 JNI: MainActivity.nativeHandlePermissionResult(int, String[], int[])
//   PermissionHelper.dispatchResult 回调到 Java MainActivity -> native, Java 侧签名:
//     public static native void nativeHandlePermissionResult(int, String[], int[]);
//   JNI 签名: (I[Ljava/lang/String;[I)V
//   permissions[] 与 grantResults[] 等长, grantResults[i] == 0 表示第 i 个权限授权成功.
//   Android 系统回调本就在主线程, 但 QML 端 callback 可能跨线程访问 Qt 对象,
//   用 Qt::QueuedConnection 投递回 Qt 主事件循环, 避免线程问题.
extern "C" JNIEXPORT void JNICALL
Java_com_outdoor_survival_MainActivity_nativeHandlePermissionResult(
    JNIEnv* env, jclass /*clazz*/, jint requestCode,
    jobjectArray /*permissions*/, jintArray grantResults)
{
    std::function<void(bool)> cb;
    {
        QMutexLocker lock(&g_pendingPermMutex);
        cb = g_pendingPermCallbacks.take(static_cast<int>(requestCode));
    }
    if (!cb) {
        Logger::warn(QString("nativeHandlePermissionResult: no callback for code=%1").arg(requestCode));
        return;
    }

    bool anyGranted = false;
    if (grantResults) {
        jsize len = env->GetArrayLength(grantResults);
        if (len > 0) {
            jint* results = env->GetIntArrayElements(grantResults, nullptr);
            if (results) {
                for (jsize i = 0; i < len; ++i) {
                    if (results[i] == 0 /* PackageManager.PERMISSION_GRANTED */) {
                        anyGranted = true;
                        break;
                    }
                }
                env->ReleaseIntArrayElements(grantResults, results, JNI_ABORT);
            }
        }
    }
    Logger::info(QString("nativeHandlePermissionResult: code=%1 granted=%2")
                     .arg(requestCode).arg(anyGranted));

    // 投递回 Qt 主线程 (此函数本身在 Android 主线程, Qt::QueuedConnection 会切到 QEventLoop)
    QMetaObject::invokeMethod(qApp, [cb, anyGranted]() {
        cb(anyGranted);
    }, Qt::QueuedConnection);
}
#endif  // Q_OS_ANDROID

void AndroidPlatform::takePhoto(std::function<void(const QString& uri)> callback) {
#ifndef Q_OS_ANDROID
    Q_UNUSED(callback);
    if (callback) callback(QString());
    return;
#else
    if (!callback) return;
    // 2026-10-16: 修 run.txt 15:58:23 "Permission Denial: ... IMAGE_CAPTURE ...
    //   com.hihonor.camera/.ThirdCamera ... with revoked permission CAMERA".
    //   荣耀系统相机 Activity 声明要求调用方持有 CAMERA, 未授予时 PhotoCaptureActivity
    //   的 startActivityForResult(IMAGE_CAPTURE) 被 ActivityManager 直接拒绝 → 拍照无响应.
    //   在真正拉起前统一 gate: 无权限 → 先申请, 授予后递归再走 (传原始 callback, 避免
    //   二次包装导致 photoTaken 重复发射); 用户拒绝 → 回调空串, 上层提示.
    if (!checkPermission("android.permission.CAMERA")) {
        Logger::warn("takePhoto: CAMERA 未授予, 先申请再拉起");
        requestPermission("android.permission.CAMERA",
                          [this, callback](bool granted) {
                              if (granted) {
                                  takePhoto(callback);
                              } else {
                                  Logger::warn("takePhoto: 用户拒绝 CAMERA 权限");
                                  callback(QString());
                              }
                          });
        return;
    }
    // 2026-09-15: 包装 callback, 触发后同时发 photoTaken 信号 (QML 入口)
    // Q_INVOKABLE requestTakePhoto() 内部也会到这里, 通过 photoTaken 信号送达 QML.
    std::function<void(const QString&)> wrapped = [this, callback](const QString& uri) {
        this->setLastCapturedUri(uri);
        emit this->photoTaken(uri);
        if (callback) callback(uri);
    };

    if (!wrapped) return;  // unreachable, kept for symmetry
    {
        QMutexLocker lock(&g_pendingMutex);
        if (g_pending.active) {
            // 上一次拍照还没回, 丢弃新的 callback (UI 应当防抖, 这里兜底)
            Logger::warn("takePhoto: previous request still pending, dropping");
            wrapped(QString());
            return;
        }
        g_pending.callback = wrapped;
        g_pending.active = true;
    }

    QJniObject activity = getActivity();
    if (!activity.isValid()) {
        Logger::warn("takePhoto: activity invalid");
        notifyPhotoResultImpl(QString());
        return;
    }

    // Intent: action = com.outdoor.survival.action.CAPTURE_PHOTO
    // class  = com.outdoor.survival.PhotoCaptureActivity
    QJniObject action = QJniObject::fromString("com.outdoor.survival.action.CAPTURE_PHOTO");
    QJniObject intent("android/content/Intent", "(Ljava/lang/String;)V",
                      action.object());
    if (!intent.isValid()) {
        Logger::warn("takePhoto: Intent construct failed");
        notifyPhotoResultImpl(QString());
        return;
    }
    intent.callObjectMethod("setAction",
                            "(Ljava/lang/String;)Landroid/content/Intent;",
                            action.object());

    // 2026-09-28: 修 run.txt native SIGSEGV (takePhoto+1060) + 编译错误.
    //   旧写法 QJniObject::fromString("com/outdoor/...").object<jclass>() 有两处错:
    //   1) fromString 返回 jstring, 取 .object<jclass>() 类型错误;
    //   2) 临时 QJniObject 在完整表达式结束后析构 → 局部引用悬空,
    //      随后 getMethodID(Class::GetDescriptor) 解引用非法 jclass → SIGSEGV @ 0x50.
    //   第一版修复误用 QJniObject::findClass — 该 API 在 Qt 6.7 不存在
    //   (loadClass 是 private, findClass 只在 QJniEnvironment 上), 直接编译失败.
    //   正解: 用 ComponentName(Context, String) 按类全名构造, 交给 Intent.setComponent
    //   解析. ComponentName 走 PackageManager 查 manifest 注册项, 不依赖 jclass /
    //   FindClass 的线程与 ClassLoader 限制, 且不影响其他进程对本 app 组件的拉起.
    QJniObject componentName("android/content/ComponentName", "(Landroid/content/Context;Ljava/lang/String;)V",
                             activity.object(),
                             QJniObject::fromString("com.outdoor.survival.PhotoCaptureActivity").object());
    if (!componentName.isValid()) {
        Logger::warn("takePhoto: ComponentName construct failed");
        notifyPhotoResultImpl(QString());
        return;
    }
    intent.callObjectMethod("setComponent",
                            "(Landroid/content/ComponentName;)Landroid/content/Intent;",
                            componentName.object());

    // 用 startActivity (不传 requestCode). PhotoCaptureActivity 拍完通过 JNI 反灌结果.
    activity.callMethod<void>("startActivity", "(Landroid/content/Intent;)V",
                              intent.object());

    Logger::info("takePhoto: PhotoCaptureActivity launched");
#endif  // Q_OS_ANDROID
}

QString AndroidPlatform::importImage(const QString& srcUri) {
#ifndef Q_OS_ANDROID
    Q_UNUSED(srcUri);
    return srcUri;
#else
    // 解析 srcUri: file:// / content:// / 裸路径
    QString path = srcUri;
    if (path.startsWith("file://")) {
        path = path.mid(7);
    }

    // 已经是本地路径, 直接返回
    if (!path.startsWith("content://")) {
        return path;
    }

    // content:// - 用 Java ContentResolver 复制到 app 沙盒
    QJniObject activity = getActivity();
    if (!activity.isValid()) {
        Logger::warn("importImage: activity invalid");
        return QString();
    }
    // 2026-09-30 修 SIGSEGV: 之前 contentUri = fromString(path) 造出的是
    //   java.lang.String, 却按 openInputStream(Landroid/net/Uri;) 传入.
    //   QJniObject::callObjectMethod 不做类型校验, ART 把 String 当 Uri 用,
    //   在 Uri.getScheme() -> String.getChars 处对非法对象解引用 -> 崩.
    //   (run.txt backtrace: #00 String.getChars / #01 ContentResolver.openInputStream
    //    / #06 importImage+476). 必须经 android.net.Uri::parse 拿到真 Uri,
    //   与同文件 makePhoneCall/openGeo 的 tel:/geo: 惯用法一致.
    QJniObject pathString = QJniObject::fromString(path);
    QJniObject contentUri = QJniObject::callStaticObjectMethod(
        "android/net/Uri", "parse", "(Ljava/lang/String;)Landroid/net/Uri;",
        pathString.object());
    if (!contentUri.isValid()) {
        Logger::warn("importImage: Uri parse failed for " + path);
        return QString();
    }
    QJniObject resolver = activity.callObjectMethod("getContentResolver",
                                                    "()Landroid/content/ContentResolver;");
    if (!resolver.isValid()) {
        Logger::warn("importImage: ContentResolver invalid");
        return QString();
    }

    // 打开 InputStream
    QJniObject inputStream = resolver.callObjectMethod(
        "openInputStream", "(Landroid/net/Uri;)Ljava/io/InputStream;",
        contentUri.object());
    if (!inputStream.isValid()) {
        Logger::warn("importImage: openInputStream failed for " + path);
        return QString();
    }

    // 用 QStandardPaths 拿 cache 目录
    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (cacheDir.isEmpty()) cacheDir = "/data/data/com.outdoor.survival/cache";
    QDir().mkpath(cacheDir);

    QString outPath = cacheDir + QString("/imported_%1.jpg")
                          .arg(QDateTime::currentMSecsSinceEpoch());
    QFile outFile(outPath);
    if (!outFile.open(QIODevice::WriteOnly)) {
        Logger::warn("importImage: cannot write " + outPath);
        return QString();
    }

    // 2026-10-19 真机 (Magic5 / Android 14) stage0.log:
    //   java.lang.NoSuchMethodError: no non-static method
    //   "Landroid/os/ParcelFileDescriptor$AutoCloseInputStream;.readAll()[B"
    //   → importImage 每次都返回空, 拍照检索整条链路拿不到图片字节.
    //   原因: InputStream.readAll() 是 Java 9 API, ART 只在新版本的部分流实现上
    //   补齐, AutoCloseInputStream 这条包装链没有; callObjectMethod 不做编译期校验,
    //   到运行时才抛 NoSuchMethodError, 表现为"返回 null".
    //   改成分块 read([B) + ByteArrayOutputStream 循环拷贝, 只用 API 1 就有的方法.
    constexpr int kChunkBytes = 64 * 1024;
    QJniEnvironment env;
    jobject inObj = inputStream.object();
    jclass inCls = env->GetObjectClass(inObj);
    jmethodID readMid = env->GetMethodID(inCls, "read", "([B)I");
    if (env->ExceptionCheck()) env->ExceptionClear();
    QJniObject baos = QJniObject("java/io/ByteArrayOutputStream");
    if (readMid == nullptr || !baos.isValid()) {
        Logger::warn("importImage: JNI stream bridge unavailable for " + path);
        inputStream.callMethod<void>("close");
        outFile.close();
        outFile.remove();
        return QString();
    }
    jclass baosCls = env->GetObjectClass(baos.object());
    jmethodID writeMid = env->GetMethodID(baosCls, "write", "([BII)V");
    jmethodID toArrMid = env->GetMethodID(baosCls, "toByteArray", "()[B");
    jbyteArray chunk = env->NewByteArray(kChunkBytes);

    qint64 total = 0;
    bool failed = false;
    for (;;) {
        jint n = env->CallIntMethod(inObj, readMid, chunk);
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            failed = true;
            break;
        }
        if (n < 0) break;          // EOF
        // read([B) 只有在数组长度为 0 时才可能返回 0, 我们的 chunk 恒为 64KB,
        // 所以 n==0 只可能是异常实现 —— 当结束处理, 避免死循环.
        if (n == 0) break;
        env->CallVoidMethod(baos.object(), writeMid, chunk, 0, n);
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            failed = true;
            break;
        }
        total += n;
        if (total > 64 * 1024 * 1024) {  // 64MB 兜底, 防异常大文件撑爆内存
            Logger::warn("importImage: source larger than 64MB, aborting " + path);
            failed = true;
            break;
        }
    }
    inputStream.callMethod<void>("close");
    env->DeleteLocalRef(chunk);

    QJniObject byteArr;
    if (!failed) {
        byteArr = QJniObject::fromLocalRef(
            env->CallObjectMethod(baos.object(), toArrMid));
        if (env->ExceptionCheck()) env->ExceptionClear();
    }
    if (failed || !byteArr.isValid()) {
        Logger::warn("importImage: stream copy failed for " + path);
        outFile.close();
        outFile.remove();
        return QString();
    }
    // 2026-09-17: Java 数组 length 是字段, 不是方法 - 必须用 GetArrayLength
    // 之前用 callMethod<jsize>("length") 会 pending JNI exception, 下次 JNI 调用 abort
    jbyteArray jba = static_cast<jbyteArray>(byteArr.object());
    jsize len = env->GetArrayLength(jba);
    if (len <= 0) {
        outFile.close();
        outFile.remove();
        return QString();
    }
    jbyte* bytes = QJniEnvironment()->GetByteArrayElements(jba, nullptr);
    if (bytes) {
        outFile.write(reinterpret_cast<const char*>(bytes), len);
        QJniEnvironment()->ReleaseByteArrayElements(jba, bytes, JNI_ABORT);
    }
    outFile.close();
    Logger::info(QString("importImage: copied %1 bytes to %2").arg(len).arg(outPath));
    return outPath;
#endif
}

} // namespace outdoor
