/**
 * @file main.cpp
 * @brief 应用入口
 *
 * 启动流程:
 *   1) 解析命令行 (debug/release 标志)
 *   2) 创建 QGuiApplication, 设置组织/应用名
 *   3) Material 主题
 *   4) 单例化 App, 调 initialize() (initLogger/Config/Platform/Database/Services/Data)
 *   5) 把 App 注册到 QML (OutdoorSurvival 1.0 / App), QML 可直接读 App.* / App.xxx()
 *   6) 通过 engine.loadFromModule("OutdoorSurvival", "Main") 加载 qml/Main.qml
 *   7) 进入事件循环
 *
 * 启动诊断:
 *   - release 模式: 写 /sdcard/Android/data/<pkg>/files/stage0.log + /data/local/tmp/stage0.log
 *   - debug 模式: 只用 qInfo
 */

#include "core/App.h"
#include "core/Logger.h"
#include "core/Database.h"
#include "core/Config.h"
#include "core/ServiceRegistry.h"  // 2026-09-10: main.cpp 调 theApp.services()->registerToQmlContext
                                    // 需要 ServiceRegistry 完整定义. App.h 只 forward decl.
#include "core/CommonOptions.h"    // 2026-09-11: C++ 单例, 替换 QML pragma Singleton
                                    // (QML pragma Singleton + qmlcachegen 静态编译下
                                    // 目录式 import "components/CommonOptions.qml"
                                    // 报 "no such directory", 改用 C++ 单例 + qmlRegisterSingletonInstance)
#include "core/ImageColorExtractor.h"  // 2026-09-14: P0 图鉴拍照真匹配 - 提取主色 HSV

// 关键: 包含所有 service 完整定义, 让编译器看到 RouteService : public QObject
// 等继承关系, 否则 static_cast<QObject*>(theApp.routes()) 报 "not related by inheritance"
#include "lifesaver/FirstAidService.h"  // 2026-09-10: E 阶段 firstaid/ → lifesaver/
#include "lifesaver/EmergencyService.h" // 2026-09-10: 同上
#include "species/SpeciesService.h"
#include "species/PlantService.h"
#include "species/AnimalService.h"
#include "species/InsectService.h"
#include "species/MushroomService.h"
#include "species/FieldGuideHistory.h"
#include "survival/SurvivalService.h"
#include "knots/KnotService.h"
#include "travel/TravelService.h"
#include "routes/RouteService.h"
#include "preparation/ChecklistService.h"  // 2026-09-10: E 阶段 emergency/ → preparation/
#include "equipment/EquipmentService.h"
#include "map/MapService.h"

#include <cstdio>
#include <QGuiApplication>
#include <QLoggingCategory>     // 2026-09-30: 开启 qt.network.ssl 等分类日志 (排查 HTTPS/地图/图册)
#include <QSslSocket>           // 2026-09-30: 启动时打印 TLS 后端能力 (HTTPS 是否可用)
#ifdef Q_OS_ANDROID
#include <android/log.h>        // 2026-09-30: __android_log_print 保 logcat 通道
#endif
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>            // 监听 QML warnings 需要完整类型
#include <QQuickStyle>
#include <QStandardPaths>
#include <QDir>
#include <QDateTime>            // stage1.log 时间戳
#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <QtQml>
#include <QFontDatabase>  // 2026-09-14: 加载 Material Icons 字体

using namespace outdoor;

// 2026-09-30: 诊断日志文件句柄 (stage0.log / stage0_tmp.log) 提升到文件作用域.
//   原因: qInstallMessageHandler 只接受函数指针 QtMessageHandler,
//   必须传 "无捕获 lambda"; 而 main 里的 logFiles 是局部变量, 无捕获 lambda
//   无法引用自动存储期变量 → 编译报 "no known conversion ... to QtMessageHandler".
//   提升为 static g_diagLogFiles (static storage duration) 后, 无捕获 lambda 即可直接引用.
static QList<QFile*> g_diagLogFiles;

int main(int argc, char* argv[]) {
    // 2026-09-11 (G13.E2): 删早期 fopen /data/local/tmp/stage0_earliest.log 临时诊断
    // Android 11+ scoped storage 已不可写, 且启动期无崩溃, 不再需要.
    // 先创建 App 实例 (singleton 内部 static, 多线程安全)
    App& theApp = App::instance();

    // 关键: release 包 debuggable=false, run-as 不能用
    // 写日志位置: 同时写两个, 取能读的那个:
    //   1. /sdcard/Android/data/com.outdoor.survival/files/stage0.log  (应用沙盒, 无权限)
    //   2. /data/local/tmp/stage0.log (全局可写, adb shell 可读)
    // 注意: QStandardPaths 需要 QGuiApplication 才能正确解析, 这里直接用硬编码路径.
    QStringList logPaths = {
        "/sdcard/Android/data/com.outdoor.survival/files/stage0.log",
        "/data/local/tmp/stage0.log"
    };
    // 2026-09-30: 写入文件作用域的 g_diagLogFiles (而非局部 logFiles),
    //   使下面无捕获的 qInstallMessageHandler lambda 能引用到它.
    for (const QString& p : logPaths) {
        QDir().mkpath(QFileInfo(p).absolutePath());
        auto* f = new QFile(p);
        f->open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
        if (f->isOpen()) {
            g_diagLogFiles.append(f);
        } else {
            delete f;
        }
    }

    auto logToFile = [](const QString& msg) {
        for (auto* f : g_diagLogFiles) {
            if (f && f->isOpen()) {
                QTextStream(f) << msg << "\n";
                f->flush();
            }
        }
        qInfo() << msg;
    };

    // ===== 2026-09-30 诊断: 全局 Qt message handler (排查 地图白底 / 图册下载) =====
    // 背景: QML console.log 走 qDebug, 默认只进 logcat 且 release 包被过滤掉;
    //       Logger::info/warn 只写应用沙盒 QFile 不进 logcat. 两条链路互不相通.
    // 本 handler 把 "所有来自 Qt 的消息" (qWarning/qCritical + qt.network.ssl 分类日志)
    // 同时写入 stage0.log (可由 adb pull 的文件) + stderr (logcat).
    // 去重技巧: Qt 对一条多行消息会逐行回调 handler, 用 "上一次时间戳" 区分
    //   "新消息" 与 "同一条消息的续行", 避免续行被重复打散.
    static QString s_diagLastTs;
    qInstallMessageHandler([](QtMsgType type, const QMessageLogContext& ctx, const QString& msg) {
        // 2026-09-30: 级别过滤.
        //   - QtInfoMsg 一律丢弃 (logToFile 尾部 qInfo 会与自身写文件重复).
        //   - QtDebugMsg 全放行: 本进程已用 QLoggingCategory::setFilterRules 放开
        //     qml/default/qt.network/qt.location 的 debug; 未被放开的分类 (如
        //     qt.qpa.*) 根本不会回调 handler, 故这里无需再按 category 过滤,
        //     否则一旦分类名恰好是空串 (partially initialized), 埋点会被误丢.
        //   - WARN/CRIT/FATAL 全放行.
        if (type == QtInfoMsg) return;
        QString ts = QDateTime::currentDateTime().toString("MM-dd HH:mm:ss.zzz");
        // 去重: Qt 对同一条多行消息逐行回调 handler 时时间戳相同.
        //   但 STAGE 0 启动日志是逐行 logToFile 写的, 每行时间戳可能相同,
        //   故对含 "=== STAGE 0" 的行放行 (见下方 isNew 判断).
        const bool isNew = (ts != s_diagLastTs) || msg.contains("=== STAGE 0");
        s_diagLastTs = ts;
        if (!isNew) return;  // 同一时刻的续行 → 跳过 (避免重复写入/重复 fprintf)
        const char* lvl = type == QtFatalMsg    ? "FATAL"
                        : type == QtCriticalMsg ? "CRIT"
                        : type == QtWarningMsg  ? "WARN"
                                                : "INFO";
        QString line;
        if (ctx.category && *ctx.category && qstrcmp(ctx.category, "default") != 0)
            line = QString("[%1] %2: %3").arg(lvl, QString::fromLatin1(ctx.category), msg);
        else
            line = QString("[%1] %2").arg(lvl, msg);
        for (auto* hf : g_diagLogFiles) {
            if (hf && hf->isOpen()) { QTextStream(hf) << line << "\n"; hf->flush(); }
        }
        // 2026-09-30: Android 上 app 的 stdout/stderr 默认被重定向到 /dev/null,
        //   fprintf(stderr) 不进 logcat. 用户取证习惯是 logcat/run.txt, 故显式调
        //   __android_log_print 保证 logcat 通道也拿到 (与 stage0.log 双保险).
#ifdef Q_OS_ANDROID
        __android_log_print(ANDROID_LOG_ERROR, "OutdoorDiag", "%s", line.toUtf8().constData());
#else
        fprintf(stderr, "%s\n", line.toUtf8().constData());
#endif
    });
    // 开启关键分类日志 (默认被过滤掉的关键诊断信息):
    //   qt.network.ssl  → OpenSSL 后端加载 / 握手 / 证书问题 (HTTPS 拉不到的根因)
    //   qt.network.*    → HTTP 层请求/响应细节
    //   qt.location.*   → 地图 plugin / 瓦片 provider 加载失败
    //   qml / default   → QML console.log 走此分类, release 默认 *.debug=false 会
    //                     拦掉 → 必须显式放开, 否则 QML 侧诊断埋点不进 stage0.log.
    QLoggingCategory::setFilterRules(
        "qt.network.ssl.debug=true\n"
        "qt.network.debug=true\n"
        "qt.location.debug=true\n"
        "qt.location.mapping.debug=true\n"
        "qml.debug=true\n"
        "default.debug=true\n");

    logToFile("=== STAGE 0: main entered ===");
    logToFile(QString("dataPath: %1").arg(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)));
    logToFile(QString("log files opened: %1 / 2").arg(g_diagLogFiles.size()));

    QGuiApplication app(argc, argv);
    logToFile("=== STAGE 0: QGuiApplication created ===");

    // 诊断桩 2026-09-10: 卡死定位
    // PID 静默 10s 无输出, 没 crash log, 锁死在 116→128 之间某处
    // 每个可疑点前加 logToFile + stderr, 看具体卡哪
    logToFile("=== STAGE 0: before setOrganizationName ===");
    QCoreApplication::setOrganizationName("Outdoor");
    logToFile("=== STAGE 0: before setOrganizationDomain ===");
    QCoreApplication::setOrganizationDomain("outdoor.com");
    logToFile("=== STAGE 0: before setApplicationName ===");
    QCoreApplication::setApplicationName("荒野手册");
    logToFile("=== STAGE 0: before setApplicationVersion ===");
    QCoreApplication::setApplicationVersion(APP_VERSION);
    logToFile("=== STAGE 0: QCoreApplication metadata set ===");

    // Material 主题
    logToFile("=== STAGE 0: before QQuickStyle::setStyle(Material) ===");
    QQuickStyle::setStyle("Material");
    logToFile("=== STAGE 0: after QQuickStyle::setStyle ===");

    // 初始化 App (logger/config/platform/database/services/data)
    logToFile("=== STAGE 0: calling App::initialize() ===");
    if (!theApp.initialize()) {
        logToFile("=== STAGE 0: App::initialize() FAILED ===");
        qCritical() << "App initialization failed";
        return -1;
    }
    logToFile("=== STAGE 0: App::initialize() OK ===");

    // ===== 2026-09-30 诊断: TLS 后端能力 =====
    // 判定 "HTTPS 是否可用" 的一锤定音证据:
    //   图册走 https://commons.wikimedia.org, 地图若走 https 瓦片同样依赖它.
    //   supportsSsl()=false 或 backends 为空 → OpenSSL 3 未加载 → https 请求
    //   既不成功也不回调错误 (静默挂起) → 图册永远"正在加载图片".
    logToFile(QString("=== STAGE 0: [TLS] supportsSsl=%1 activeBackend=%2 "
                      "ver=%3 backends=[%4] ===")
              .arg(QSslSocket::supportsSsl() ? "true" : "false",
                   QSslSocket::activeBackend(),
                   QSslSocket::sslLibraryVersionString(),
                   QSslSocket::availableBackends().join(",")));

    // 注册 App 单例到 QML: QML 内可直接用 App.version / App.firstAid() / App.database() ...
    qmlRegisterSingletonInstance("OutdoorSurvival", 1, 0, "App", &theApp);
    logToFile("=== STAGE 0: App singleton registered to QML ===");

    // 2026-09-11: 注册 CommonOptions 单例 (颜色 + 下拉选项)
    // 单点注册, 避免 ServiceRegistry 14+ 个 qmlRegisterSingletonInstance 一起注册
    // 触发 "ReferenceError is not defined" 的 Qt 内部 bug.
    static CommonOptions g_commonOptions;
    qmlRegisterSingletonInstance("OutdoorSurvival", 1, 0, "CommonOptions", &g_commonOptions);
    logToFile("=== STAGE 0: CommonOptions singleton registered to QML ===");

    // 2026-09-14: 注册 ImageColorExtractor 单例 (P0 图鉴真匹配)
    static ImageColorExtractor g_imageColorExtractor;
    qmlRegisterSingletonInstance("OutdoorSurvival", 1, 0, "ImageColorExtractor", &g_imageColorExtractor);
    logToFile("=== STAGE 0: ImageColorExtractor singleton registered to QML ===");

    // 2026-09-14: 加载 Material Icons 字体到 QFontDatabase
    // Qt 不会自动从 qrc 加载字体, 必须显式调 addApplicationFont.
    // Qt 6.7 Android: addApplicationFont(QString) 返回 int (-1=失败),
    //   用 applicationFontFamilies(int) 拿 family 名字列表.
    // 重要: 资源路径在 Android 上是 :/qt/qml/<URI>/assets/...
    //   同一路径 QFile 能打开 (AssetLoader 已验证), QFontDatabase 应该也能.
    {
        const QStringList candidatePaths = {
            QStringLiteral(":/qt/qml/OutdoorSurvival/assets/fonts/MaterialIcons-Regular.ttf"),
            QStringLiteral("qrc:/qt/qml/OutdoorSurvival/assets/fonts/MaterialIcons-Regular.ttf"),
            QStringLiteral(":/assets/fonts/MaterialIcons-Regular.ttf")
        };
        int fontId = -1;
        QString successPath;
        for (const QString& path : candidatePaths) {
            fontId = QFontDatabase::addApplicationFont(path);
            if (fontId != -1) {
                successPath = path;
                break;
            }
        }
        if (fontId == -1) {
            logToFile("=== STAGE 0: ⚠ Material Icons 字体加载失败 (3 paths tried) ===");
            qWarning() << "Material Icons font load failed - icons will show as tofu";
        } else {
            const QStringList families = QFontDatabase::applicationFontFamilies(fontId);
            logToFile(QString("=== STAGE 0: Material Icons 字体已加载 id=%1 from=%2, families=%3 ===")
                .arg(fontId).arg(successPath).arg(families.join(",")));
        }
    }

    QQmlApplicationEngine engine;
    logToFile("=== STAGE 0: QQmlApplicationEngine created ===");

    // 2026-09-21: 监听 QML 加载错误, 写到 logcat + 文件, 不阻断主流程
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() {
        qCritical() << "QML objectCreationFailed - QML 加载失败";
        QFile f("/data/local/tmp/stage1.log");
        if (f.open(QIODevice::WriteOnly | QIODevice::Append)) {
            QTextStream(&f) << "objectCreationFailed at "
                             << QDateTime::currentDateTime().toString(Qt::ISODate) << "\n";
        }
    }, Qt::QueuedConnection);
    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
                     [](const QList<QQmlError>& warnings) {
        for (const auto& w : warnings) {
            qWarning() << "QML warning:" << w.toString();
        }
    });

    // 2026-09-10: 注册 FirstAidService 枚举 (Category/Urgency) 让 QML 端能取
    // 之前 setContextProperty 注入的 firstAidService 是裸 QObject, Q_ENUM 不能直接
    // 在 QML 端通过 service.Category.Critical 访问, 报 "Critical of undefined".
    // 用 qmlRegisterUncreatableType 把 type 注入, QML 可用 FirstAidService.Critical
    {
        qmlRegisterUncreatableType<FirstAidService>(
            "OutdoorSurvival", 1, 0, "FirstAidService",
            QStringLiteral("FirstAidService cannot be created from QML"));
        logToFile("=== STAGE 0: FirstAidService Q_ENUM registered ===");
    }

    // 2026-09-15: 注册 SpeciesService 枚举 (Category), 让 QML 端能取 SpeciesService.Snake 等
    {
        qmlRegisterUncreatableType<SpeciesService>(
            "OutdoorSurvival", 1, 0, "SpeciesService",
            QStringLiteral("SpeciesService cannot be created from QML"));
        logToFile("=== STAGE 0: SpeciesService Q_ENUM registered ===");
    }

    // 关键: 把 14 个 service / engine 注入到 QML 上下文
    // 原因: QML 页面直接用裸 service 名调用, 如 firstAidService.getById() / mapService.getAllPhotos() 等.
    //       若不注入, 这些引用是 undefined, 启动后任何 service 调用都报 ReferenceError.
    // 命名规则: Qt 把 C++ 类名 FirstAidService 自动转成 firstAidService (首字母小写).
    // 必须在 engine.loadFromModule() 之前调用, 否则 QML 加载时上下文里还没有这些属性.
    // 2026-09-10: 改用 ServiceRegistry::registerToQmlContext 统一注册
    {
        theApp.services()->registerToQmlContext(engine.rootContext());
        logToFile("=== STAGE 0: 15 services injected via ServiceRegistry ===");
    }

    // 通过 qt_add_qml_module 注册的模块 URI 加载 (Qt 6.5+ 推荐)
    // URI = OutdoorSurvival, qmldir 里的 Main = Main.qml
    logToFile("=== STAGE 0: before engine.loadFromModule ===");
    engine.loadFromModule("OutdoorSurvival", "Main");
    logToFile("=== STAGE 0: after engine.loadFromModule (returned) ===");
    logToFile(QString("=== STAGE 0: rootObjects().size()=%1 ===").arg(engine.rootObjects().size()));

    if (engine.rootObjects().isEmpty()) {
        logToFile("=== STAGE 0: FAILED to load QML (rootObjects empty) ===");
        // 2026-09-15: 之前直接 return -1, 跳过 theApp.shutdown(), 后续
        //   ~App() 析构 static App 时 QSqlDatabase::removeDatabase 在 QGuiApplication
        //   已死之后调用, 触发 "QSqlDatabase requires a QCoreApplication"
        //   + FORTIFY pthread_mutex_lock on destroyed mutex -> SIGABRT.
        theApp.shutdown();
        return -1;
    }
    logToFile("=== STAGE 0: loadFromModule returned ===");
    logToFile("=== STAGE 0: QML rootObjects OK, entering event loop ===");

    int ret = app.exec();
    logToFile(QString("=== STAGE 0: event loop exited, ret=%1 ===").arg(ret));

    // 退出时关闭日志文件
    for (auto* f : g_diagLogFiles) {
        if (f) f->close();
        delete f;
    }
    g_diagLogFiles.clear();

    theApp.shutdown();
    return ret;
}
