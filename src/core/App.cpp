/**
 * @file App.cpp
 */

#include "App.h"
#include "Config.h"
#include "Logger.h"
#include "Database.h"
#include "ServiceRegistry.h"  // 2026-09-10: App.h 不能 include (会触发 Qt 6.7 incomplete type),
                                // 14 个 getter 委托实现放这里, ServiceRegistry 完整定义可见.

#include "../lifesaver/FirstAidService.h"
#include "../lifesaver/EmergencyService.h"
#include "../species/SpeciesService.h"
#include "../species/PlantService.h"
#include "../species/AnimalService.h"
#include "../species/InsectService.h"
#include "../species/MushroomService.h"
#include "../species/FieldGuideHistory.h"
#include "../survival/SurvivalService.h"
#include "../knots/KnotService.h"
#include "../travel/TravelService.h"
#include "../routes/RouteService.h"
#include "../preparation/ChecklistService.h"
#include "../platform/PlatformInterface.h"
#include "../map/MapService.h"  // 完整定义(unique_ptr reset 需要)
#include "../equipment/EquipmentService.h"  // 完整定义(unique_ptr reset 需要)

#include <QCoreApplication>
#include <QStandardPaths>
#include <QDir>
#include <QDebug>

namespace outdoor {

// 2026-09-10: 14 个 service getter 委托给 m_services, out-of-line 实现
// (不能在 App.h inline, 否则 ServiceRegistry.h 被 include 触发 Qt 6.7 incomplete type)
Config* App::config() const { return m_config.get(); }
FirstAidService*   App::firstAid()          const { return m_services ? m_services->firstAid()         : nullptr; }
EmergencyService*  App::emergency()         const { return m_services ? m_services->emergency()        : nullptr; }
SpeciesService*    App::species()           const { return m_services ? m_services->species()          : nullptr; }
PlantService*      App::plants()            const { return m_services ? m_services->plants()           : nullptr; }
AnimalService*     App::animals()           const { return m_services ? m_services->animals()          : nullptr; }
InsectService*     App::insects()           const { return m_services ? m_services->insects()          : nullptr; }
MushroomService*   App::mushrooms()         const { return m_services ? m_services->mushrooms()        : nullptr; }
FieldGuideHistory* App::fieldGuideHistory() const { return m_services ? m_services->fieldGuideHistory(): nullptr; }
SurvivalService*   App::survival()          const { return m_services ? m_services->survival()         : nullptr; }
KnotService*       App::knots()             const { return m_services ? m_services->knots()            : nullptr; }
TravelService*     App::travel()            const { return m_services ? m_services->travel()           : nullptr; }
RouteService*      App::routes()            const { return m_services ? m_services->routes()           : nullptr; }
ChecklistService*  App::checklist()         const { return m_services ? m_services->checklist()        : nullptr; }
EquipmentService*   App::equipment()         const { return m_services ? m_services->equipment()        : nullptr; }
MapService*        App::mapService()        const { return m_services ? m_services->mapService()       : nullptr; }

App& App::instance() {
    static App s_instance;
    return s_instance;
}

App::App(QObject* parent) : QObject(parent) {}
App::~App() = default;

bool App::initialize() {
    qInfo() << "Initializing" << version() << "...";

    if (!initLogger()) {
        qCritical() << "Failed to initialize logger";
        return false;
    }
    Logger::info("=== App starting ===");
    Logger::info(QString("Version: %1").arg(version()));

    if (!initConfig()) {
        Logger::error("Failed to initialize config");
        return false;
    }

    if (!initPlatform()) {
        Logger::warn("Platform layer init failed (non-fatal)");
    }

    if (!initDatabase()) {
        // 之前是 return false: 致命错误.
        // 但 release 模式下用户报告 pidof 空, 说明 initDatabase 失败可能
        // 是 SQLite 写权限/磁盘空间/DB 锁等偶发问题, 应该是 warn + 继续.
        // 后续 service 找不到 DB 时 ensureSchema 返回 false, 但 App 仍可启动
        // (只是数据存不了). 用户至少能看到 UI.
        Logger::error("Failed to initialize database (continuing startup)");
    }

    if (!initServices()) {
        Logger::error("Failed to initialize services");
        return false;
    }

    if (!initData()) {
        Logger::error("Failed to load initial data");
        return false;
    }

    m_ready = true;
    emit readyChanged();
    emit initialized();

    Logger::info("=== App initialized ===");
    return true;
}

void App::shutdown() {
    Logger::info("=== App shutting down ===");
    emit aboutToShutdown();

    // 2026-09-10: 14 个 service 由 ServiceRegistry 统一管理, 一次 reset 清空
    m_services.reset();
    m_database.reset();
    m_platform.reset();
    m_config.reset();
    m_logger.reset();

    m_ready = false;
    emit readyChanged();
}

QString App::dataPath() const {
    QString path = QStandardPaths::writableLocation(
        QStandardPaths::AppDataLocation);
    QDir().mkpath(path);
    return path;
}

bool App::initLogger() {
    m_logger = std::make_unique<Logger>();
    return m_logger->initialize(dataPath() + "/logs");
}

bool App::initConfig() {
    m_config = std::make_unique<Config>();
    return m_config->load(dataPath() + "/config.json");
}

bool App::initPlatform() {
    m_platform.reset(PlatformInterface::create());
    return m_platform != nullptr;
}

bool App::initDatabase() {
    m_database = std::make_unique<Database>();
    if (!m_database->open(dataPath())) return false;
    // 关键修复:启动时自动迁移建表(此前 migrate() 是空壳)
    m_database->migrate();
    return true;
}

bool App::initServices() {
    // 2026-09-10: 14 个 service 所有权移交给 ServiceRegistry
    m_services = std::make_unique<ServiceRegistry>();
    m_services->setDatabase(m_database.get());
    m_services->setPlatform(m_platform.get());
    if (!m_services->initializeAll()) {
        return false;
    }

    // EquipmentService 必须调用 initialize() 加载 items/rules + 偏好, 否则
    // QML 进入 EquipmentPage 时 equipmentService.getAllItems()/getList() 返回空
    // → page.onCompleted 拿到空 model, 用户体验退化
    if (!m_services->equipment()->initialize()) {
        Logger::error("EquipmentService::initialize() failed, equipment features unavailable");
        // 不返回 false: 不阻断 App 启动, 仅装备功能不可用
    }
    // MapService 必须调用 initialize() 设置 m_storagePath, 否则所有文件操作
    // 会写到根路径(/photo_*.json), Android 上无权限 → 功能完全不可用
    if (!m_services->mapService()->initialize()) {
        Logger::error("MapService::initialize() failed, map features unavailable");
        // 不返回 false: 不阻断 App 启动, 仅地图功能不可用
    }

    return true;
}

bool App::initData() {
    // 2026-09-10: 委托给 ServiceRegistry::loadDataAll
    return m_services->loadDataAll();
}

} // namespace outdoor
